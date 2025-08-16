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
      unless File.exist?(CREDENTIALS_FILE)
        raise "Google credentials file not found: #{CREDENTIALS_FILE}"
      end
      
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
    
    def get_grocery_list
      # Get all data from sheet
      range = "#{sheet_name}!A:Z"  # Use wider range to handle any number of columns
      
      response = @service.get_spreadsheet_values(SHEET_ID, range)
      rows = response.values || []
      return [] if rows.empty?
      
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
      
      grocery_items = []
      # Skip header row
      rows[1..-1]&.each do |row|
        # Skip completely empty rows or rows without item name
        next if row.nil? || row.empty? 
        next if row.all? { |cell| cell.nil? || cell.to_s.strip.empty? }
        next if item_col && (row[item_col].nil? || row[item_col].to_s.strip.empty?)
        
        grocery_items << {
          purchased: purchased_col ? (row[purchased_col]&.strip || '') : '',
          item: item_col ? (row[item_col]&.strip || '') : '',
          modifier: modifier_col ? (row[modifier_col]&.strip || '') : '',
          priority: priority_col && row[priority_col] && !row[priority_col].strip.empty? ? row[priority_col].strip.to_i : 1,
          quantity: quantity_col ? (row[quantity_col]&.strip&.to_i || 1) : 1,
          last_purchased: last_purchased_col ? (row[last_purchased_col]&.strip || '') : '',
          itemno: itemno_col ? (row[itemno_col]&.strip || '') : '',
          url: url_col ? (row[url_col]&.strip || '') : ''
        }
      end
      
      grocery_items
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
        next if index == 0  # Skip header row
        if row[item_col]&.strip&.downcase == item_name.strip.downcase
          row_index = index + 1  # Convert to 1-based index for Google Sheets
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
        next if index == 0  # Skip header row
        if row[item_col]&.strip&.downcase == item_name.strip.downcase
          row_index = index + 1  # Convert to 1-based index for Google Sheets
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
      puts "📊 Syncing Google Sheets data to database..."
      
      items = get_grocery_list
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
          if !item[:item].empty?
            updates[:description] = item[:item]
          end
          
          # Only update URL if sheet has non-empty value
          if !item[:url].empty?
            updates[:url] = item[:url]
          end
          
          # Only update modifier if sheet has non-empty value
          if !item[:modifier].empty?
            updates[:modifier] = item[:modifier]
          end
          
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
        
        # Record purchase history if last_purchased date exists
        if !item[:last_purchased].empty? && item[:last_purchased] != 'last purchased'
          begin
            purchase_date = Date.parse(item[:last_purchased])
            
            # Check if this purchase already exists
            existing_purchases = database.get_purchase_history(prod_id, limit: 5)
            unless existing_purchases.any? { |p| p[:purchase_date] == purchase_date }
              database.record_purchase(
                prod_id: prod_id,
                quantity: item[:quantity] || 1,
                purchase_date: purchase_date
              )
            end
          rescue Date::Error
            # Skip invalid dates
          end
        end
      end
      
      puts "✅ Sync complete: #{synced_count} new items, #{updated_count} updated, #{deleted_count} deleted"
      { new: synced_count, updated: updated_count, deleted: deleted_count }
    end

    def sync_from_database(database)
      puts "📤 Syncing database items back to Google Sheets..."
      
      # Get all items from database
      db_items = database.get_all_items_by_priority
      
      # Get current sheet data
      current_items = get_grocery_list
      current_items_map = current_items.map { |item| [item[:item].downcase, item] }.to_h
      
      # Check if sheet needs headers first
      range = "#{sheet_name}!A:Z"
      response = @service.get_spreadsheet_values(SHEET_ID, range)
      existing_rows = response.values || []
      
      # If sheet is completely empty, add headers first
      if existing_rows.empty?
        headers = ['Purchased', 'Item Name', 'Modifier', 'Priority', 'Qty', 'Last Purchased', 'ItemNo', 'URL']
        header_range = "#{sheet_name}!A1:H1"
        header_value_range = Google::Apis::SheetsV4::ValueRange.new(
          range: header_range,
          values: [headers]
        )
        
        begin
          @service.update_spreadsheet_value(
            SHEET_ID,
            header_range,
            header_value_range,
            value_input_option: 'RAW'
          )
          existing_rows = [headers]  # Update our local copy
        rescue => e
          puts "❌ Error creating headers: #{e.message}"
        end
      end
      
      new_items = []
      
      db_items.each do |db_item|
        item_name = db_item[:description]
        
        # Skip if item already exists in sheet
        next if current_items_map.key?(item_name.downcase)
        
        # Get most recent purchase for this item
        recent_purchase = database.get_purchase_history(db_item[:prod_id], limit: 1).first
        last_purchased = recent_purchase ? recent_purchase[:purchase_date].to_s : ''
        
        # Build row with fixed column order: Purchased, Item Name, Modifier, Priority, Qty, Last Purchased, ItemNo, URL
        # Leave priority blank if it's 1 (highest priority default)
        # Leave quantity blank instead of showing 0
        priority_display = (db_item[:priority] == 1) ? '' : db_item[:priority].to_s
        row = ['', item_name, db_item[:modifier] || '', priority_display, '', last_purchased, db_item[:prod_id], db_item[:url]]
        
        new_items << row
      end
      
      if new_items.empty?
        puts "ℹ️  No new items to add to sheet"
        return { added: 0 }
      end
      
      last_row = existing_rows.length + 1
      
      # Append new items (8 columns: A to H)
      new_range = "#{sheet_name}!A#{last_row}:H#{last_row + new_items.length - 1}"
      value_range = Google::Apis::SheetsV4::ValueRange.new(
        range: new_range,
        values: new_items
      )
      
      begin
        
        @service.update_spreadsheet_value(
          SHEET_ID,
          new_range,
          value_range,
          value_input_option: 'RAW'
        )
        
        puts "✅ Added #{new_items.length} new items to Google Sheets"
        { added: new_items.length }
      rescue => e
        puts "❌ Error writing to Google Sheets: #{e.message}"
        puts "🔍 Debug: #{e.class}: #{e.backtrace.first}"
        { added: 0, error: e.message }
      end
    end
  end
  
  def self.create_sync_client
    SheetsSync.new
  rescue => e
    puts "⚠️  Failed to initialize Google Sheets sync: #{e.message}"
    nil
  end
  
  def self.available?
    File.exist?(SheetsSync::CREDENTIALS_FILE)
  end
end