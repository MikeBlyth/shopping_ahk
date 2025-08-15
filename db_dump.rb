#!/usr/bin/env ruby

require 'csv'
require 'json'
require 'dotenv/load'
require_relative 'lib/database'

class DatabaseDumper
  def initialize
    @db = Database.instance
  end

  def dump_to_csv(filename = nil)
    filename ||= "walmart_items_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
    
    puts "📄 Exporting database to CSV: #{filename}"
    
    CSV.open(filename, 'w', write_headers: true, headers: ['prod_id', 'description', 'modifier', 'url', 'priority', 'default_quantity', 'original_name', 'created_at', 'updated_at']) do |csv|
      @db.db[:items].order(:description).each do |item|
        csv << [
          item[:prod_id],
          item[:description],
          item[:modifier],
          item[:url],
          item[:priority],
          item[:default_quantity],
          item[:original_name],
          item[:created_at],
          item[:updated_at]
        ]
      end
    end
    
    item_count = @db.db[:items].count
    puts "✅ Exported #{item_count} items to #{filename}"
    filename
  end

  def dump_to_json(filename = nil)
    filename ||= "walmart_items_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
    
    puts "📄 Exporting database to JSON: #{filename}"
    
    items = @db.db[:items].order(:description).all
    purchases = @db.db[:purchases].order(:purchase_date).all
    
    data = {
      exported_at: Time.now.iso8601,
      items: items,
      purchases: purchases,
      stats: {
        item_count: items.length,
        purchase_count: purchases.length
      }
    }
    
    File.write(filename, JSON.pretty_generate(data))
    
    puts "✅ Exported #{items.length} items and #{purchases.length} purchases to #{filename}"
    filename
  end

  def dump_to_sql(filename = nil)
    filename ||= "walmart_db_#{Time.now.strftime('%Y%m%d_%H%M%S')}.sql"
    
    puts "📄 Exporting database to SQL: #{filename}"
    
    File.open(filename, 'w') do |file|
      file.puts "-- Walmart Database Dump"
      file.puts "-- Generated: #{Time.now}"
      file.puts "-- Ruby version: #{RUBY_VERSION}"
      file.puts ""
      
      # Items table data
      file.puts "-- Items table data"
      file.puts "TRUNCATE TABLE items CASCADE;"
      
      @db.db[:items].order(:prod_id).each do |item|
        values = [
          quote_sql_value(item[:prod_id]),
          quote_sql_value(item[:url]),
          quote_sql_value(item[:description]),
          quote_sql_value(item[:modifier]),
          item[:default_quantity] || 1,
          item[:priority] || 0,
          quote_sql_value(item[:original_name]),
          quote_sql_timestamp(item[:created_at]),
          quote_sql_timestamp(item[:updated_at])
        ]
        
        file.puts "INSERT INTO items (prod_id, url, description, modifier, default_quantity, priority, original_name, created_at, updated_at) VALUES (#{values.join(', ')});"
      end
      
      file.puts ""
      
      # Purchases table data
      file.puts "-- Purchases table data"
      file.puts "TRUNCATE TABLE purchases CASCADE;"
      
      @db.db[:purchases].order(:purchase_timestamp).each do |purchase|
        values = [
          quote_sql_value(purchase[:prod_id]),
          purchase[:quantity] || 1,
          purchase[:price_cents],
          quote_sql_date(purchase[:purchase_date]),
          quote_sql_timestamp(purchase[:purchase_timestamp])
        ]
        
        file.puts "INSERT INTO purchases (prod_id, quantity, price_cents, purchase_date, purchase_timestamp) VALUES (#{values.join(', ')});"
      end
      
      file.puts ""
      file.puts "-- End of dump"
    end
    
    items_count = @db.db[:items].count
    purchases_count = @db.db[:purchases].count
    puts "✅ Exported #{items_count} items and #{purchases_count} purchases to #{filename}"
    filename
  end

  def pg_dump(filename = nil)
    filename ||= "walmart_backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}.sql"
    
    puts "📄 Creating PostgreSQL backup: #{filename}"
    
    # Try to find pg_dump executable
    pg_dump_path = find_pg_dump
    unless pg_dump_path
      puts "❌ pg_dump not found. Please ensure PostgreSQL is installed."
      return nil
    end
    
    # Build pg_dump command from environment variables
    cmd_parts = ["\"#{pg_dump_path}\""]
    
    if ENV['DATABASE_URL']
      cmd_parts << ENV['DATABASE_URL']
    else
      cmd_parts << "--host=#{ENV['POSTGRES_HOST'] || 'localhost'}"
      cmd_parts << "--username=#{ENV['POSTGRES_USER'] || 'mike'}"
      cmd_parts << "--dbname=#{ENV['POSTGRES_DB'] || 'walmart'}"
    end
    
    cmd_parts << "--file=#{filename}"
    cmd_parts << "--clean"           # Include DROP statements
    cmd_parts << "--create"          # Include CREATE DATABASE
    cmd_parts << "--if-exists"       # Use IF EXISTS for drops
    cmd_parts << "--verbose"
    
    cmd = cmd_parts.join(' ')
    
    puts "Running: #{cmd}"
    
    # Set PGPASSWORD environment variable for authentication
    env = ENV.to_h
    env['PGPASSWORD'] = ENV['POSTGRES_PASSWORD'] if ENV['POSTGRES_PASSWORD']
    
    if system(env, cmd)
      puts "✅ PostgreSQL backup created: #{filename}"
      puts "💡 Restore with: psql -f #{filename}"
      filename
    else
      puts "❌ pg_dump failed. Check database connection and credentials."
      nil
    end
  end

  def find_pg_dump
    # Try PATH first (preferred), then fallback to common installation paths
    if system('where pg_dump >nul 2>&1')
      return 'pg_dump'
    end
    
    # Fallback paths if not in system PATH
    fallback_paths = [
      'C:/Program Files/PostgreSQL/17/bin/pg_dump.exe',
      'C:/Program Files/PostgreSQL/16/bin/pg_dump.exe',
      'C:/Program Files/PostgreSQL/15/bin/pg_dump.exe',
      'C:/Program Files (x86)/PostgreSQL/17/bin/pg_dump.exe',
      'C:/Program Files (x86)/PostgreSQL/16/bin/pg_dump.exe'
    ]
    
    fallback_paths.each do |path|
      return path if File.exist?(path)
    end
    
    nil
  end

  def show_stats
    items_count = @db.db[:items].count
    purchases_count = @db.db[:purchases].count
    
    puts "📊 Database Statistics"
    puts "=" * 30
    puts "Items: #{items_count}"
    puts "Purchases: #{purchases_count}"
    
    if items_count > 0
      priorities = @db.db[:items].group_and_count(:priority).order(:priority).all
      puts "\nItems by priority:"
      priorities.each do |p|
        puts "  Priority #{p[:priority]}: #{p[:count]} items"
      end
      
      recent_items = @db.db[:items].where { created_at >= Date.today - 7 }.count
      puts "\nItems added in last 7 days: #{recent_items}"
    end
    
    if purchases_count > 0
      recent_purchases = @db.db[:purchases].where { purchase_date >= Date.today - 30 }.count
      puts "Purchases in last 30 days: #{recent_purchases}"
    end
    
    puts "=" * 30
  end

  private

  def quote_sql_value(value)
    return 'NULL' if value.nil?
    "'#{value.to_s.gsub("'", "''")}'"
  end

  def quote_sql_timestamp(timestamp)
    return 'NULL' if timestamp.nil?
    "'#{timestamp.strftime('%Y-%m-%d %H:%M:%S')}'"
  end

  def quote_sql_date(date)
    return 'NULL' if date.nil?
    "'#{date.strftime('%Y-%m-%d')}'"
  end
end

# CLI interface
if __FILE__ == $0
  dumper = DatabaseDumper.new
  
  case ARGV[0]
  when 'csv'
    dumper.dump_to_csv(ARGV[1])
  when 'json'
    dumper.dump_to_json(ARGV[1])
  when 'sql'
    dumper.dump_to_sql(ARGV[1])
  when 'backup', 'pg_dump'
    dumper.pg_dump(ARGV[1])
  when 'stats'
    dumper.show_stats
  else
    puts "Usage:"
    puts "  ruby db_dump.rb backup [filename]  - Full PostgreSQL backup (RECOMMENDED)"
    puts "  ruby db_dump.rb csv [filename]     - Export to CSV"
    puts "  ruby db_dump.rb json [filename]    - Export to JSON"
    puts "  ruby db_dump.rb sql [filename]     - Export to SQL INSERT statements"
    puts "  ruby db_dump.rb stats              - Show database statistics"
    puts ""
    puts "Examples:"
    puts "  ruby db_dump.rb backup             - Creates full backup with pg_dump"
    puts "  ruby db_dump.rb csv my_items.csv"
    puts "  ruby db_dump.rb json export.json"
    puts "  ruby db_dump.rb stats"
    puts ""
    puts "For full restoration, use 'backup' - it includes schema, data, indexes, and constraints."
  end
end