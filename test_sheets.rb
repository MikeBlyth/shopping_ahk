#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'lib/google_sheets_integration'
require_relative 'lib/database'

puts "🧪 Testing Google Sheets Integration"
puts "=================================="

# Test environment variables
puts "\n📋 Environment Check:"
puts "  GOOGLE_SHEET_ID: #{ENV['GOOGLE_SHEET_ID'] ? 'Set' : 'Missing'}"
puts "  Sheet ID: #{ENV['GOOGLE_SHEET_ID']}"

# Test database connection
puts "\n🗃️  Database Check:"
begin
  db = Database.instance
  if db.test_connection
    puts "  Database: Connected ✅"
  else
    puts "  Database: Failed ❌"
  end
rescue => e
  puts "  Database Error: #{e.message}"
end

# Test Google Sheets connection
puts "\n📊 Google Sheets Check:"
begin
  sheets_sync = GoogleSheetsIntegration.create_sync_client
  if sheets_sync
    puts "  Google Sheets: Connected ✅"
    
    puts "\n📝 Loading grocery list..."
    items = sheets_sync.get_grocery_list
    
    puts "  Items found: #{items.length}"
    if items.length > 0
      puts "  Sample items:"
      items.first(3).each do |item|
        puts "    - #{item[:item]} (Status: #{item[:status]})"
      end
    else
      puts "  No items found in sheet"
    end
  else
    puts "  Google Sheets: Failed to connect ❌"
  end
rescue => e
  puts "  Google Sheets Error: #{e.message}"
  puts "  #{e.backtrace.first}"
end

puts "\n✅ Test complete!"