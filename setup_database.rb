#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'lib/database'

def setup_database
  puts "🗃️  Walmart Grocery Database Setup"
  puts "================================="
  
  puts "Database configuration:"
  puts "  Host: #{ENV['POSTGRES_HOST']}"
  puts "  Database: #{ENV['POSTGRES_DB']}"
  puts "  User: #{ENV['POSTGRES_USER']}"
  puts ""
  
  # Test initial connection
  puts "Testing database connection..."
  db = Database.instance
  
  unless db.test_connection
    puts "❌ Cannot connect to database. Please ensure:"
    puts "   1. PostgreSQL is running (WSL/Docker: docker-compose up -d)"
    puts "   2. Port 5432 is accessible from Windows"
    puts "   3. Database credentials in .env are correct"
    puts ""
    puts "For WSL connection, you may need to:"
    puts "   - Use WSL IP instead of localhost: wsl hostname -I" 
    puts "   - Check Windows Defender/firewall settings"
    exit 1
  end
  
  # Check if tables exist
  tables = db.db.tables
  puts "Current tables: #{tables}"
  
  if tables.empty?
    puts ""
    puts "🔧 No tables found. You can:"
    puts "  1. Import existing data: psql -h #{ENV['POSTGRES_HOST']} -U #{ENV['POSTGRES_USER']} -d #{ENV['POSTGRES_DB']} < walmart_data_export.sql"
    puts "  2. Create fresh schema: psql -h #{ENV['POSTGRES_HOST']} -U #{ENV['POSTGRES_USER']} -d #{ENV['POSTGRES_DB']} < schema.sql"
  else
    puts ""
    puts "✅ Database appears to be set up!"
    
    # Show some stats
    if tables.include?(:items)
      item_count = db.db[:items].count
      puts "📦 Items in database: #{item_count}"
      
      if item_count > 0
        puts "Sample items:"
        db.db[:items].limit(3).each do |item|
          puts "  - #{item[:description]} (#{item[:prod_id]})"
        end
      end
    end
    
    if tables.include?(:purchases)
      purchase_count = db.db[:purchases].count
      puts "🛒 Purchase records: #{purchase_count}"
    end
  end
  
  puts ""
  puts "🚀 Database setup complete! You can now run: ruby grocery_bot.rb"
  
rescue => e
  puts "❌ Setup failed: #{e.message}"
  puts ""
  puts "Troubleshooting:"
  puts "  - Ensure PostgreSQL is running"
  puts "  - Check .env file settings"
  puts "  - For WSL: make sure port forwarding is working"
  exit 1
end

if __FILE__ == $0
  setup_database
end