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
        'Walmart-Prod'
      when 'development', 'dev'
        'Walmart-Dev'
      else
        'Walmart-Dev'
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
    
    def get_grocery_list
      # For now, since sheet structure is: item, url, itemno, quantity, 'last purchased', 'prev'
      # We'll just return all items from the sheet for selection
      # Later this could be enhanced to only return items marked for shopping
      range = "Sheet1!A:F"
      
      response = @service.get_spreadsheet_values(SHEET_ID, range)
      rows = response.values || []
      
      # Skip header row if exists
      if rows.first && rows.first[0]&.downcase == 'item'
        rows = rows[1..-1]
      end
      
      grocery_items = []
      rows.each do |row|
        next if row.empty? || row[0].nil? || row[0].strip.empty?
        
        grocery_items << {
          item: row[0]&.strip || '',                    # Column A: item
          url: row[1]&.strip || '',                     # Column B: url  
          itemno: row[2]&.strip || '',                  # Column C: itemno
          quantity: row[3]&.strip&.to_i || 1,           # Column D: quantity
          last_purchased: row[4]&.strip || '',          # Column E: last purchased
          prev: row[5]&.strip || ''                     # Column F: prev
        }
      end
      
      grocery_items
    end
    
    def update_item_url(item_name, url)
      range = "#{sheet_name}!A:C"
      
      response = @service.get_spreadsheet_values(SHEET_ID, range)
      rows = response.values || []
      
      row_index = nil
      rows.each_with_index do |row, index|
        next if index == 0
        if row[0]&.strip&.downcase == item_name.strip.downcase
          row_index = index + 1
          break
        end
      end
      
      if row_index
        update_range = "#{sheet_name}!B#{row_index}"
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
      range = "#{sheet_name}!A:C"
      
      response = @service.get_spreadsheet_values(SHEET_ID, range)
      rows = response.values || []
      
      row_index = nil
      rows.each_with_index do |row, index|
        next if index == 0
        if row[0]&.strip&.downcase == item_name.strip.downcase
          row_index = index + 1
          break
        end
      end
      
      if row_index
        update_range = "#{sheet_name}!C#{row_index}"
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
      
      items.each do |item|
        next if item[:item].empty? || item[:url].empty?
        
        # Extract product ID from URL
        prod_id = database.extract_prod_id_from_url(item[:url])
        next unless prod_id
        
        # Check if item exists in database
        existing_item = database.find_item_by_prod_id(prod_id)
        
        if existing_item
          # Update existing item
          updates = {
            description: item[:item],
            url: item[:url],
            updated_at: Time.now
          }
          database.update_item(prod_id, updates)
          updated_count += 1
        else
          # Create new item
          database.create_item(
            prod_id: prod_id,
            url: item[:url],
            description: item[:item],
            modifier: nil,
            default_quantity: 1,
            priority: 5
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
                quantity: 1,
                purchase_date: purchase_date
              )
            end
          rescue Date::Error
            # Skip invalid dates
          end
        end
      end
      
      puts "✅ Sync complete: #{synced_count} new items, #{updated_count} updated"
      { new: synced_count, updated: updated_count }
    end

    def sync_from_database(database)
      puts "📤 Syncing database items back to Google Sheets..."
      
      # Get all items from database
      db_items = database.get_all_items_by_priority
      
      # Get current sheet data
      current_items = get_grocery_list
      current_items_map = current_items.map { |item| [item[:item].downcase, item] }.to_h
      
      new_items = []
      
      db_items.each do |db_item|
        item_name = db_item[:description]
        
        # Skip if item already exists in sheet
        next if current_items_map.key?(item_name.downcase)
        
        # Get most recent purchase for this item
        recent_purchase = database.get_purchase_history(db_item[:prod_id], limit: 1).first
        last_purchased = recent_purchase ? recent_purchase[:purchase_date].to_s : ''
        
        new_items << [
          item_name,                    # Column A: item
          db_item[:url],               # Column B: url
          db_item[:prod_id],           # Column C: itemno
          0,                           # Column D: quantity (default to 0)
          last_purchased,              # Column E: last purchased
          ''                           # Column F: prev
        ]
      end
      
      if new_items.empty?
        puts "ℹ️  No new items to add to sheet"
        return { added: 0 }
      end
      
      # Find the last row with data
      range = "Sheet1!A:F"
      response = @service.get_spreadsheet_values(SHEET_ID, range)
      existing_rows = response.values || []
      last_row = existing_rows.length + 1
      
      # Append new items
      new_range = "Sheet1!A#{last_row}:F#{last_row + new_items.length - 1}"
      value_range = Google::Apis::SheetsV4::ValueRange.new(
        range: new_range,
        values: new_items
      )
      
      @service.update_spreadsheet_value(
        SHEET_ID,
        new_range,
        value_range,
        value_input_option: 'RAW'
      )
      
      puts "✅ Added #{new_items.length} new items to Google Sheets"
      { added: new_items.length }
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