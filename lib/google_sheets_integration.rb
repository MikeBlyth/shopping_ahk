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

    def initialize(readonly: false)
      @readonly = readonly
      @service = Google::Apis::SheetsV4::SheetsService.new
      @service.authorization = authorize
    end

    def readonly?
      @readonly
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
      subscribable_col = find_column_index(header_map, 'subscribable', 'subscribe', 'sub', 'subscription')
      category_col = find_column_index(header_map, 'category')

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
        item_name = item_col ? (row[item_col]&.strip&.gsub(/[[:punct:]\s]+$/, '') || '') : ''
        next if item_name.empty?

        # Skip TOTAL
        next if item_name.include?('TOTAL')

        # Parse subscribable field: check mark or '1' = 1, 'x' or blank = 0
        subscribable_value = subscribable_col ? (row[subscribable_col]&.strip || '') : ''
        subscribable = subscribable_value.downcase.include?('✓') || subscribable_value.downcase.include?('check') || subscribable_value == '1' ? 1 : 0

        item_data = {
          purchased: purchased_col ? (row[purchased_col]&.strip || '') : '',
          item: item_name,
          modifier: modifier_col ? (row[modifier_col]&.strip || '') : '',
          priority: priority_col && row[priority_col] && !row[priority_col].strip.empty? ? row[priority_col].strip.to_i : 1,
          quantity: quantity_col ? parse_quantity(row[quantity_col]) : 1,
          last_purchased: last_purchased_col ? (row[last_purchased_col]&.strip || '') : '',
          itemno: itemno_col ? (row[itemno_col]&.strip || '') : '',
          url: url_col ? (row[url_col]&.strip || '') : '',
          subscribable: subscribable,
          category: category_col ? (row[category_col]&.strip || '') : '',
          original_row_index: index + 2 # +2 because we skipped header and arrays are 0-indexed
        }

        if in_shopping_section
          # Shopping list has different structure - extract price from column C (index 2)
          shopping_item = item_data.dup
          shopping_item[:price] = row[2]&.strip || '' # Column C is price in shopping list

          # Parse purchased field to extract quantity and normalize format
          purchased_text = shopping_item[:purchased] || ''
          if purchased_text.include?('✅')
            # Extract quantity from ✅1, ✅2, etc.
            quantity_match = purchased_text.match(/✅(\d+)/)
            shopping_item[:purchased_quantity] = quantity_match ? quantity_match[1].to_i : 1
            shopping_item[:purchased] = 'purchased' # Store as simple flag
          elsif purchased_text.include?('✓')
            shopping_item[:purchased_quantity] = 1 # Default quantity for simple checkmark
            shopping_item[:purchased] = 'purchased' # Store as simple flag
          elsif purchased_text.include?('❌')
            shopping_item[:purchased_quantity] = 0
            shopping_item[:purchased] = 'skipped' # Store as skipped flag
          else
            shopping_item[:purchased_quantity] = 0
            shopping_item[:purchased] = '' # Not purchased
          end

          #          puts "🔍 DEBUG: Loaded shopping item '#{shopping_item[:item]}' with price '#{shopping_item[:price]}', purchased: #{shopping_item[:purchased]}, qty: #{shopping_item[:purchased_quantity]}"
          shopping_list << shopping_item
        else
          product_list << item_data
        end
      end

      { product_list: product_list, shopping_list: shopping_list }
    end

    def update_item_url(item_name, url)
      if readonly?
        puts "🔒 Read-only mode: Skipping Google Sheets URL update for #{item_name}"
        return false
      end

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
      if readonly?
        puts "🔒 Read-only mode: Skipping marking item #{item_name} as completed in Google Sheets"
        return false
      end

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
      if readonly?
        puts "🔒 Read-only mode: Skipping sync from Sheets to Database (would modify database)"
        return { new: 0, updated: 0, reactivated: 0, deactivated: 0 }
      end

      puts '📊 Syncing Google Sheets data to database...'

      sheet_data = get_grocery_list
      items = sheet_data[:product_list]
      
      synced_count = 0
      updated_count = 0
      reactivated_count = 0

      # Get a list of all product IDs present on the sheet
      sheet_prod_ids = items.map do |item|
        database.extract_prod_id_from_url(item[:url])
      end.compact

      items.each do |item|
        next if item[:item].empty? || item[:url].empty?

        prod_id = database.extract_prod_id_from_url(item[:url])
        next unless prod_id

        existing_item = database.find_item_by_prod_id(prod_id)

        if existing_item
          updates = { updated_at: Time.now }
          
          # Reactivate if it was inactive
          if existing_item[:status] == 'inactive'
            updates[:status] = 'active'
            reactivated_count += 1
          end

          updates[:description] = item[:item] unless item[:item].empty?
          updates[:modifier] = item[:modifier] unless item[:modifier].empty?
          updates[:category] = item[:category] unless item[:category].empty?
          updates[:priority] = item[:priority]
          updates[:subscribable] = item[:subscribable]

          if updates.keys.length > 1
            database.update_item(prod_id, updates)
            updated_count += 1
          end
        else
          # Create new item
          database.create_item(
            prod_id: prod_id,
            description: item[:item],
            modifier: item[:modifier],
            default_quantity: item[:quantity] || 1,
            priority: item[:priority],
            subscribable: item[:subscribable],
            category: item[:category]
            # status defaults to 'active'
          )
          synced_count += 1
        end
      end
      
      # Deactivate items that are in the DB but are no longer on the sheet
      deactivated_count = 0
      deactivated_count = database.deactivate_missing_items(sheet_prod_ids) if items.any?

      puts "✅ Sync complete: #{synced_count} new, #{updated_count} updated, #{reactivated_count} reactivated, #{deactivated_count} deactivated."
      { new: synced_count, updated: updated_count, reactivated: reactivated_count, deactivated: deactivated_count }
    end

    def sync_from_database(database, shopping_list_data = [])
      if readonly?
        puts "🔒 Read-only mode: Skipping sync from Database to Sheets"
        return { products: 0, shopping_items: 0 }
      end

      puts '📤 Rewriting entire Google Sheets with updated data...'

      # Get only ACTIVE items from database
      db_items = database.get_all_active_items_by_priority

      # Build complete sheet data
      all_rows = []

      # 1. Headers
      headers = ['Purchased', 'Item Name', 'Modifier', 'Priority', 'Qty', 'Last Purchased', 'ItemNo', 'URL',
                 'Subscribable', 'Category', 'Units/Week', 'Avg Cost/Month']
      all_rows << headers

      # 2. Product list section
      db_items.each do |db_item|
        # Get most recent purchase for this item
        recent_purchase = database.get_purchase_history(db_item[:prod_id], limit: 1).first
        last_purchased = recent_purchase ? recent_purchase[:purchase_date].to_s : ''

        # Calculate units per week and average cost per month
        units_per_week = database.units_ordered_per_week(db_item[:prod_id])
        avg_cost_per_month = database.average_cost_per_month(db_item[:prod_id])

        # Build row with fixed column order: Purchased, Item Name, Modifier, Priority, Qty, Last Purchased, ItemNo, URL, Subscribable
        # Leave priority blank if it's 1 (highest priority default)
        # Leave quantity blank in product list (not used for ordering)
        # Display subscribable as green check for 1, blank for 0
        priority_display = db_item[:priority] == 1 ? '' : db_item[:priority].to_s
        subscribable_display = db_item[:subscribable] == 1 ? '✅' : ''
        url = database.construct_url_from_prod_id(db_item[:prod_id])
        row = ['', db_item[:description], db_item[:modifier] || '', priority_display, '', last_purchased,
               db_item[:prod_id], url, subscribable_display, db_item[:category] || '', units_per_week, avg_cost_per_month]

        all_rows << row
      end

      # 3. Blank line separator
      all_rows << ['', '', '', '', '', '', '', '', '', '', '', '']

      # 4. Shopping List delimiter
      all_rows << ['Shopping List', '', '', '', '', '', '', '', '', '', '', '']

      # 5. Shopping list items (simple format)
      shopping_list_start_row = all_rows.length + 1 # Track where shopping list starts for formula
      puts "🔍 DEBUG: Shopping list will start at row #{shopping_list_start_row} (1-indexed)"

      shopping_list_data.each_with_index do |shopping_item, index|
        puts "🔍 DEBUG: Item #{index + 1}: #{shopping_item[:item]} - price: '#{shopping_item[:price]}' (#{shopping_item[:price].class}), purchased: '#{shopping_item[:purchased]}', qty: #{shopping_item[:purchased_quantity]}"

        # Format purchased display consistently
        if (shopping_item[:purchased] == 'purchased' || shopping_item[:purchased] == '✓') && shopping_item[:purchased_quantity] && shopping_item[:purchased_quantity] > 0
          purchased_display = "✅#{shopping_item[:purchased_quantity]}"
        else
          purchased_display = '❌'
        end

        # Put actual numeric price in price column (or empty if no price)
        if shopping_item[:price] && !shopping_item[:price].to_s.strip.empty?
          # Strip $ and other currency formatting, then convert to float
          price_string = shopping_item[:price].to_s.gsub(/[$,\s]/, '')
          price_value = price_string.to_f
          if price_value > 0
          #            puts "🔍 DEBUG: Using numeric price: #{price_value} (from '#{shopping_item[:price]}')"
          else
            price_value = ''
            puts "🔍 DEBUG: Invalid price format '#{shopping_item[:price]}' - using empty cell"
          end
        else
          price_value = '' # Empty cell for items without prices
          puts '🔍 DEBUG: No price - using empty cell'
        end

        item_number = shopping_item[:itemno] || ''

        # Shopping list format: purchased_display | description | price_value | itemid
        row = [purchased_display, shopping_item[:item], price_value, item_number]

        all_rows << row
      end

      # 6. Add TOTAL row with SUM formula
      shopping_list_end_row = all_rows.length
      # Formula sums column C (price column) from shopping list start to end
      total_formula = "=SUM(C#{shopping_list_start_row + 1}:C#{shopping_list_end_row})"
      total_row = ['TOTAL', '', total_formula, '']
      all_rows << total_row

      # Clear entire sheet and rewrite
      begin
        # Clear the sheet
        clear_range = "#{sheet_name}!A:Z"
        @service.clear_values(SHEET_ID, clear_range)

        # Write all data at once
        if all_rows.length > 1 # More than just headers
          write_range = "#{sheet_name}!A1:L#{all_rows.length}"
          value_range = Google::Apis::SheetsV4::ValueRange.new(
            range: write_range,
            values: all_rows
          )

          @service.update_spreadsheet_value(
            SHEET_ID,
            write_range,
            value_range,
            value_input_option: 'USER_ENTERED' # This allows formulas to be interpreted
          )

          # Format price column as currency and make TOTAL row bold
          total_row_index = all_rows.length # Last row (1-indexed)

          # Format price column (column C, index 2) as currency
          # shopping_list_start_row + 1 because we need to skip the "Shopping List" delimiter row
          price_format_start = shopping_list_start_row # This should be the first actual shopping item
          puts "🔍 DEBUG: Formatting currency from row #{price_format_start} to #{total_row_index}"

          price_column_format = {
            repeat_cell: {
              range: {
                sheet_id: 0, # Assuming first sheet
                start_row_index: price_format_start - 1, # Convert to 0-indexed (subtract 1)
                end_row_index: total_row_index, # Include TOTAL row
                start_column_index: 2, # Column C (price column)
                end_column_index: 3
              },
              cell: {
                user_entered_format: {
                  number_format: {
                    type: 'CURRENCY',
                    pattern: '"$"#,##0.00'
                  }
                }
              },
              fields: 'userEnteredFormat.numberFormat'
            }
          }

          bold_request = {
            repeat_cell: {
              range: {
                sheet_id: 0, # Assuming first sheet
                start_row_index: total_row_index - 1, # Convert to 0-indexed
                end_row_index: total_row_index,
                start_column_index: 0,
                end_column_index: 12
              },
              cell: {
                user_entered_format: {
                  text_format: {
                    bold: true
                  }
                }
              },
              fields: 'userEnteredFormat.textFormat.bold'
            }
          }

          batch_request = Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new(
            requests: [price_column_format, bold_request]
          )

          @service.batch_update_spreadsheet(SHEET_ID, batch_request)
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

  def self.create_sync_client(readonly: false)
    SheetsSync.new(readonly: readonly)
  rescue StandardError => e
    puts "⚠️  Failed to initialize Google Sheets sync: #{e.message}"
    nil
  end

  def self.available?
    File.exist?(SheetsSync::CREDENTIALS_FILE)
  end
end
