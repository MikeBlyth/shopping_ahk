#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'lib/database'

# Add original_name column to items table
begin
  db = Database.instance
  
  puts "🗄️  Connecting to database..."
  
  # Check if column already exists
  columns = db.db[:items].columns
  if columns.include?(:original_name)
    puts "✅ Column 'original_name' already exists"
  else
    puts "➕ Adding 'original_name' column to items table..."
    db.db.alter_table(:items) do
      add_column :original_name, String
    end
    puts "✅ Column 'original_name' added successfully"
  end
  
rescue => e
  puts "❌ Error: #{e.message}"
  exit 1
end