#!/usr/bin/env ruby

require 'google/apis/sheets_v4'
require 'googleauth'
require 'json'

module GoogleSheetsIntegration
  class SheetsSync
    SHEET_ID = '1LPB1mStjDhOCmLCgsD_Q9wnf2LLpWVOzmL3wGeOLvGQ'
    CREDENTIALS_FILE = 'google_credentials.json'

    def sheet_name
      environment = ENV['WALMART_ENVIRONMENT'] || 'development'
      case environment.downcase
      when 'production'
        'Sheet1'  # Use Sheet1 for now since Walmart-Prod doesn't exist
      when 'development', 'dev'
        'Sheet1'  # Use Sheet1 for now since Walmart-Dev doesn't exist
      else
        'Sheet1'  # Default to Sheet1
      end
    end

    def initialize
      @service = Google::Apis::SheetsV4::SheetsService.new
      @service.authorization = authorize
    end

    private

    def authorize
      raise "Google credentials file not found: #{CREDENTIALS_FILE}" unless File.exist?(CREDENTIALS_FILE)

      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(CREDENTIALS_FILE),
        scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS
      )
    end

    public

    def get_column_headers
      # Read first row to get column headers
      range = "#{sheet_name}!1:1"
      response = @service.get_spreadsheet_values(SHEET_ID, range)
      headers = response.values&.first || []

      # Create mapping of column name to index
      header_map = {}
      headers.each_with_index do |header, index|
        next unless header && !header.strip.empty?

        # Normalize header names for easier matching
        normalized = header.strip.downcase.gsub(/[^a-z0-9]/, '')
        header_map[normalized] = index
      end

      header_map
    end

    def find_column_index(header_map, *possible_names)
      # Try to find column by various possible names
      possible_names.each do |name|
        normalized = name.downcase.gsub(/[^a-z0-9]/, '')
        return header_map[normalized] if header_map[normalized]
      end
      nil
    end

    def parse_quantity(quantity_cell)
      # Handle quantity parsing with new logic:
      # - Blank/empty = 1 (want to order 1 unit)
      # - Explicit 0 = 0 (don't order)
      # - Any other number = that number
      return 1 if quantity_cell.nil? || quantity_cell.strip.empty?

      quantity_cell.strip.to_i
    end

    def get_grocery_list
      # Get all data from sheet
      range = "#{sheet_name}!A:Z" # Use wider range to handle any number of columns

      response = @service.get_spreadsheet_values(SHEET_ID, range)
      rows = response.values || []
      return { product_list: [], shopping_list: [] } if rows.empty?

      # Get column mapping from headers
      header_map = get_column_headers

      # Find column indices for each field
      purchased_col = find_column_index(header_map, 'purchased', 'checkmark', 'check', 'done', 'completed')
      item_col = find_column_index(header_map, 'item', 'itemname', 'item name', 'name', 'product')
      modifier_col = find_column_index(header_map, 'modifier', 'mod', 'variation', 'variant')
      priority_col = find_column_index(header_map, 'priority', 'prio', 'pri', 'rank')
      quantity_col = find_column_index(header_map, 'qty', 'quantity', 'quantifier', 'amount')
      last_purchased_col = find_column_index(header_map, 'lastpurchased', 'last purchased', 'date')
      itemno_col = find_column_index(header_map, 'itemno', 'item no', 'itemid', 'item id', 'prodid', 'product id', 'id')
      url_col = find_column_index(header_map, 'url', 'link', 'website')

      product_list = []
      shopping_list = []
      in_shopping_section = false

      # Skip header row and process sections
      rows[1..-1]&.each_with_index do |row, index|
        # Skip completely empty rows
        next if row.nil? || row.empty?
        next if row.all? { |cell| cell.nil? || cell.to_s.strip.empty? }

        # Check if this is the "Shopping List" delimiter
        first_col_text = purchased_col ? (row[purchased_col]&.strip || '') : ''
        if first_col_text.downcase.include?('shopping list')
          in_shopping_section = true
          next
        end

        # Skip rows without item names
        item_name = item_col ? (row[item_col]&.strip || '') : ''
        next if item_name.empty?

        # Skip TOTAL
        next if item_name.include?('TOTAL')

        item_data = {
          purchased: purchased_col ? (row[purchased_col]&.strip || '') : '',
          item: item_name,
          modifier: modifier_col ? (row[modifier_col]&.strip || '') : '',
          priority: priority_col && row[priority_col] && !row[priority_col].strip.empty? ? row[priority_col].strip.to_i : 1,
          quantity: quantity_col ? parse_quantity(row[quantity_col]) : 1,
          last_purchased: last_purchased_col ? (row[last_purchased_col]&.strip || '') : '',
          itemno: itemno_col ? (row[itemno_col]&.strip || '') : '',
          url: url_col ? (row[url_col]&.strip || '') : '',
          original_row_index: index + 2 # +2 because we skipped header and arrays are 0-indexed
        }

        if in_shopping_section
          shopping_list << item_data
        else
          product_list << item_data
        end
      end

      { product_list: product_list, shopping_list: shopping_list }
    end

    def update_item_url(item_name, url)
      # Get all data and column mapping
      range = "#{sheet_name}!A:Z"
      response = @service.get_spreadsheet_values(SHEET_ID, range)
      rows = response.values || []
      return false if rows.empty?

      header_map = get_column_headers
      item_col = find_column_index(header_map, 'item', 'itemname', 'item name', 'name', 'product')
      url_col = find_column_index(header_map, 'url', 'link', 'website')

      return false unless item_col && url_col

      # Find the row with matching item name
      row_index = nil
      rows.each_with_index do |row, index|
        next if index == 0 # Skip header row

        if row[item_col]&.strip&.downcase == item_name.strip.downcase
          row_index = index + 1 # Convert to 1-based index for Google Sheets
          break
        end
      end

      if row_index
        # Convert column index to letter (A, B, C, etc.)
        col_letter = ('A'.ord + url_col).chr
        update_range = "#{sheet_name}!#{col_letter}#{row_index}"

        value_range = Google::Apis::SheetsV4::ValueRange.new(
          range: update_range,
          values: [[url]]
        )

        @service.update_spreadsheet_value(
          SHEET_ID,
          update_range,
          value_range,
          value_input_option: 'RAW'
        )

        true
      else
        false
      end
    end

    def mark_item_completed(item_name)
      # Get all data and column mapping
      range = "#{sheet_name}!A:Z"
      response = @service.get_spreadsheet_values(SHEET_ID, range)
      rows = response.values || []
      return false if rows.empty?

      header_map = get_column_headers
      item_col = find_column_index(header_map, 'item', 'itemname', 'item name', 'name', 'product')
      purchased_col = find_column_index(header_map, 'purchased', 'checkmark', 'check', 'done', 'completed')

      return false unless item_col && purchased_col

      # Find the row with matching item name
      row_index = nil
      rows.each_with_index do |row, index|
        next if index == 0 # Skip header row

        if row[item_col]&.strip&.downcase == item_name.strip.downcase
          row_index = index + 1 # Convert to 1-based index for Google Sheets
          break
        end
      end

      if row_index
        # Convert column index to letter (A, B, C, etc.)
        col_letter = ('A'.ord + purchased_col).chr
        update_range = "#{sheet_name}!#{col_letter}#{row_index}"

        value_range = Google::Apis::SheetsV4::ValueRange.new(
          range: update_range,
          values: [['✓']]
        )

        @service.update_spreadsheet_value(
          SHEET_ID,
          update_range,
          value_range,
          value_input_option: 'RAW'
        )

        true
      else
        false
      end
    end

    def sync_to_database(database)
      puts '📊 Syncing Google Sheets data to database...'

      sheet_data = get_grocery_list
      # Only sync product list to database, ignore shopping list
      items = sheet_data[:product_list]
      synced_count = 0
      updated_count = 0
      deleted_count = 0

      items.each do |item|
        # Handle deletion request
        if item[:item].strip.downcase == 'delete'
          next if item[:url].empty?

          prod_id = database.extract_prod_id_from_url(item[:url])
          if prod_id && database.find_item_by_prod_id(prod_id)
            database.delete_item(prod_id)
            deleted_count += 1
            puts "🗑️  Deleted item with prod_id: #{prod_id}"
          end
          next
        end

        next if item[:item].empty? || item[:url].empty?

        # Extract product ID from URL
        prod_id = database.extract_prod_id_from_url(item[:url])
        next unless prod_id

        # Check if item exists in database
        existing_item = database.find_item_by_prod_id(prod_id)

        if existing_item
          # Update existing item - only update non-empty values from sheet
          updates = { updated_at: Time.now }

          # Only update description if sheet has non-empty value
          updates[:description] = item[:item] unless item[:item].empty?

          # Only update URL if sheet has non-empty value
          updates[:url] = item[:url] unless item[:url].empty?

          # Only update modifier if sheet has non-empty value
          updates[:modifier] = item[:modifier] unless item[:modifier].empty?

          # Always update priority (blank cells default to 1)
          updates[:priority] = item[:priority]

          # Only perform update if there are actual changes beyond timestamp
          if updates.keys.length > 1
            database.update_item(prod_id, updates)
            updated_count += 1
          end
        else
          # Create new item
          database.create_item(
            prod_id: prod_id,
            url: item[:url],
            description: item[:item],
            modifier: item[:modifier],
            default_quantity: item[:quantity] || 1,
            priority: item[:priority]
          )
          synced_count += 1
        end

        # NOTE: Last Purchased column is now display-only and not used to create purchase records
        # Purchase records are only created by actual purchase transactions
      end

      puts "✅ Sync complete: #{synced_count} new items, #{updated_count} updated, #{deleted_count} deleted"
      { new: synced_count, updated: updated_count, deleted: deleted_count }
    end

    def sync_from_database(database, shopping_list_data = [])
      puts '📤 Rewriting entire Google Sheets with updated data...'

      # Get all items from database (sorted by priority)
      db_items = database.get_all_items_by_priority

      # Build complete sheet data
      all_rows = []

      # 1. Headers
      headers = ['Purchased', 'Item Name', 'Modifier', 'Priority', 'Qty', 'Last Purchased', 'ItemNo', 'URL']
      all_rows << headers

      # 2. Product list section
      db_items.each do |db_item|
        # Get most recent purchase for this item
        recent_purchase = database.get_purchase_history(db_item[:prod_id], limit: 1).first
        last_purchased = recent_purchase ? recent_purchase[:purchase_date].to_s : ''

        # Build row with fixed column order: Purchased, Item Name, Modifier, Priority, Qty, Last Purchased, ItemNo, URL
        # Leave priority blank if it's 1 (highest priority default)
        # Leave quantity blank in product list (not used for ordering)
        priority_display = db_item[:priority] == 1 ? '' : db_item[:priority].to_s
        row = ['', db_item[:description], db_item[:modifier] || '', priority_display, '', last_purchased,
               db_item[:prod_id], db_item[:url]]

        all_rows << row
      end

      # 3. Blank line separator
      all_rows << ['', '', '', '', '', '', '', '']

      # 4. Shopping List delimiter
      all_rows << ['Shopping List', '', '', '', '', '', '', '']

      # 5. Shopping list items with new display format
      total_cost = 0.0
      
      shopping_list_data.each do |shopping_item|
        # Format: {✅{qty} | ❌ } | {description} | {total_price = qty*price} | itemid
        
        # Check if this item was already purchased in the initial sheet load
        # (has a checkmark in the 'purchased' field from original sheet)
        originally_purchased = shopping_item[:purchased] && 
                              !shopping_item[:purchased].empty? && 
                              shopping_item[:purchased] != '❌'
        
        if originally_purchased
          # Item was already purchased - keep unchanged, preserve original format
          # Extract quantity from original purchased display if it contains ✅ with number
          if shopping_item[:purchased].match(/✅(\d+)/)
            orig_qty = shopping_item[:purchased].match(/✅(\d+)/)[1].to_i
            # Try to extract price from modifier field if present
            if shopping_item[:modifier] && shopping_item[:modifier].match(/\$?([\d.]+)/)
              orig_price = shopping_item[:modifier].match(/\$?([\d.]+)/)[1].to_f
              orig_total = orig_qty * orig_price
              total_cost += orig_total
              total_price_display = sprintf('%.2f', orig_total)
            else
              total_price_display = shopping_item[:modifier] || ''
            end
            purchased_display = shopping_item[:purchased]
          else
            # Simple checkmark or other format - preserve as is
            purchased_display = shopping_item[:purchased]
            total_price_display = shopping_item[:modifier] || ''
          end
          item_number = shopping_item[:itemno] || ''
        elsif shopping_item[:price_paid] && shopping_item[:quantity_purchased]
          # Item was purchased in current session - calculate total price
          quantity = shopping_item[:quantity_purchased]
          unit_price = shopping_item[:price_paid]
          item_total = quantity * unit_price
          total_cost += item_total
          
          purchased_display = "✅#{quantity}"
          total_price_display = sprintf('%.2f', item_total)
          item_number = shopping_item[:itemno] || ''
        else
          # Item not purchased
          purchased_display = '❌'
          total_price_display = ''
          item_number = shopping_item[:itemno] || ''
        end
        
        # Build row: purchased_display | description | total_price | itemid | (other cols empty)
        row = [purchased_display, shopping_item[:item], total_price_display, item_number, '', '', '', '']

        all_rows << row
      end
      
      # 6. Add TOTAL row as last item
      if total_cost > 0
        total_row = ['TOTAL', '', sprintf('%.2f', total_cost), '', '', '', '', '']
        all_rows << total_row
      end

      # Clear entire sheet and rewrite
      begin
        # Clear the sheet
        clear_range = "#{sheet_name}!A:Z"
        @service.clear_values(SHEET_ID, clear_range)

        # Write all data at once
        if all_rows.length > 1 # More than just headers
          write_range = "#{sheet_name}!A1:H#{all_rows.length}"
          value_range = Google::Apis::SheetsV4::ValueRange.new(
            range: write_range,
            values: all_rows
          )

          @service.update_spreadsheet_value(
            SHEET_ID,
            write_range,
            value_range,
            value_input_option: 'RAW'
          )
        end

        puts "✅ Rewrote entire sheet: #{db_items.length} products, #{shopping_list_data.length} shopping items"
        { products: db_items.length, shopping_items: shopping_list_data.length }
      rescue StandardError => e
        puts "❌ Error rewriting Google Sheets: #{e.message}"
        puts "🔍 Debug: #{e.class}: #{e.backtrace.first}"
        { products: 0, shopping_items: 0, error: e.message }
      end
    end
  end

  def self.create_sync_client
    SheetsSync.new
  rescue StandardError => e
    puts "⚠️  Failed to initialize Google Sheets sync: #{e.message}"
    nil
  end

  def self.available?
    File.exist?(SheetsSync::CREDENTIALS_FILE)
  end
end
