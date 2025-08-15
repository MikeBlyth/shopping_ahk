#!/usr/bin/env ruby

require 'csv'
require 'dotenv/load'
require_relative 'lib/database'

class SimplifiedItemsImporter
  def initialize(csv_file_path)
    @csv_file_path = csv_file_path
    @db = Database.instance
    @stats = {
      updated: 0,
      created: 0,
      errors: 0,
      skipped: 0
    }
  end

  def import
    puts "📄 Reading CSV file: #{@csv_file_path}"
    
    # Read file content and handle encoding issues
    begin
      content = File.read(@csv_file_path, encoding: 'UTF-8')
    rescue Encoding::InvalidByteSequenceError
      puts "⚠️  Encoding issue detected, trying with Windows-1252..."
      content = File.read(@csv_file_path, encoding: 'Windows-1252:UTF-8')
    end
    
    # Process CSV from cleaned content
    CSV.parse(content, headers: true) do |row|
      process_row(row)
    end
    
    print_summary
  end

  private

  def process_row(row)
    prod_id = row['product_id']
    original_name = row['original_name']
    simplified_name = row['simplified_name'] 
    modifier = row['modifier']
    priority = row['priority']
    url = row['url']
    
    # Skip rows with missing essential data
    if prod_id.nil? || prod_id.empty? || simplified_name.nil? || simplified_name.empty?
      puts "⚠️  Skipping row with missing data: #{row.to_h}"
      @stats[:skipped] += 1
      return
    end
    
    # Convert priority to integer, default to 5 if empty
    priority_int = if priority.nil? || priority.empty?
                     5
                   else
                     priority.to_i
                   end
    
    begin
      # Check if item exists
      existing_item = @db.find_item_by_prod_id(prod_id)
      
      if existing_item
        # Update existing item
        update_existing_item(existing_item, simplified_name, modifier, priority_int, original_name)
      else
        # Create new item
        create_new_item(prod_id, url, simplified_name, modifier, priority_int, original_name)
      end
      
    rescue => e
      puts "❌ Error processing product #{prod_id}: #{e.message}"
      @stats[:errors] += 1
    end
  end

  def update_existing_item(existing_item, simplified_name, modifier, priority, original_name)
    prod_id = existing_item[:prod_id]
    
    # Prepare updates - only update fields that have changed
    updates = {}
    
    if existing_item[:description] != simplified_name
      updates[:description] = simplified_name
    end
    
    if existing_item[:modifier] != modifier
      updates[:modifier] = modifier
    end
    
    if existing_item[:priority] != priority
      updates[:priority] = priority
    end
    
    # Update original_name if it's different or missing
    if existing_item[:original_name] != original_name && !original_name.nil? && !original_name.empty?
      updates[:original_name] = original_name
    end
    
    if updates.any?
      @db.update_item(prod_id, updates)
      puts "🔄 Updated: #{simplified_name} (ID: #{prod_id})"
      puts "   Changes: #{updates.keys.join(', ')}"
      @stats[:updated] += 1
    else
      puts "⏭️  No changes needed: #{simplified_name} (ID: #{prod_id})"
      @stats[:skipped] += 1
    end
  end

  def create_new_item(prod_id, url, simplified_name, modifier, priority, original_name)
    # Create item with all fields including original_name
    item_data = {
      prod_id: prod_id,
      url: url,
      description: simplified_name,
      modifier: modifier,
      default_quantity: 1,
      priority: priority
    }
    
    # Add original_name if we have it
    item_data[:original_name] = original_name if original_name && !original_name.empty?
    
    @db.db[:items].insert(item_data)
    
    puts "➕ Created: #{simplified_name} (ID: #{prod_id})"
    @stats[:created] += 1
  end

  def print_summary
    puts "\n" + "="*50
    puts "📊 Import Summary"
    puts "="*50
    puts "Items updated: #{@stats[:updated]}"
    puts "Items created: #{@stats[:created]}"
    puts "Items skipped: #{@stats[:skipped]}"
    puts "Errors: #{@stats[:errors]}"
    puts "Total processed: #{@stats.values.sum}"
    puts "="*50
    
    if @stats[:errors] > 0
      puts "⚠️  Some errors occurred during import. Check the output above for details."
    else
      puts "✅ Import completed successfully!"
    end
  end
end

# Run the importer if called directly
if __FILE__ == $0
  unless ARGV[0]
    puts "Usage: ruby import_simplified_items.rb <csv_file_path>"
    puts "Example: ruby import_simplified_items.rb extracted_walmart_items_simplified.csv"
    exit 1
  end
  
  csv_file = ARGV[0]
  
  unless File.exist?(csv_file)
    puts "❌ File not found: #{csv_file}"
    exit 1
  end
  
  puts "🚀 Starting import of simplified items..."
  puts "📁 Source: #{csv_file}"
  puts "🗄️  Target: PostgreSQL database"
  puts ""
  
  importer = SimplifiedItemsImporter.new(csv_file)
  importer.import
end