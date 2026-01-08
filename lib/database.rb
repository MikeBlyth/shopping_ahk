require 'sequel'
require 'pg'

class WalmartDatabase
  def initialize(readonly: false)
    @readonly = readonly
    @db = connect_to_database
    setup_models
  end

  attr_reader :db

  def readonly?
    @readonly
  end

  def connect_to_database
    database_url = ENV['DATABASE_URL']
    
    if database_url
      Sequel.connect(database_url)
    else
      # Fallback for local development
      Sequel.connect(
        adapter: 'postgres',
        host: ENV['POSTGRES_HOST'] || 'localhost',
        database: ENV['POSTGRES_DB'] || 'walmart',
        user: ENV['POSTGRES_USER'] || 'mike',
        password: ENV['POSTGRES_PASSWORD']
      )
    end
  end

  def setup_models
    @items = @db[:items]
    @purchases = @db[:purchases]
  end

  # Item management methods
  def find_item_by_prod_id(prod_id)
    @items.where(prod_id: prod_id).first
  end

  def find_item_by_description(description)
    @items.where(Sequel.ilike(:description, "%#{description}%")).first
  end

  def find_all_items_by_description(description)
    @items.where(Sequel.ilike(:description, "%#{description}%")).order(:priority, :description).all
  end

  def create_item(prod_id:, description:, modifier: nil, default_quantity: 1, priority: 1, subscribable: 0, category: nil, status: 'active')
    if readonly?
      puts "🔒 Read-only mode: Skipping creation of item #{prod_id} (#{description})"
      return
    end

    # Normalize priority: treat nil or empty as 1 (highest priority)
    normalized_priority = (priority.nil? || priority == '') ? 1 : priority
    
    @items.insert(
      prod_id: prod_id,
      description: description,
      modifier: modifier,
      default_quantity: default_quantity,
      priority: normalized_priority,
      subscribable: subscribable,
      category: category,
      status: status
    )
  end

  def update_item(prod_id, updates)
    if readonly?
      puts "🔒 Read-only mode: Skipping update of item #{prod_id}"
      return
    end

    # Normalize priority if it's being updated
    if updates.key?(:priority)
      priority = updates[:priority]
      updates[:priority] = (priority.nil? || priority == '') ? 1 : priority
    end
    
    @items.where(prod_id: prod_id).update(updates.merge(updated_at: Time.now))
  end

  def update_item_description(prod_id, new_description)
    if readonly?
      puts "🔒 Read-only mode: Skipping description update for item #{prod_id}"
      return
    end

    @items.where(prod_id: prod_id).update(description: new_description)
  end

  def delete_item(prod_id)
    if readonly?
      puts "🔒 Read-only mode: Skipping deletion of item #{prod_id}"
      return
    end

    # First delete all purchase records for this item
    @purchases.where(prod_id: prod_id).delete
    # Then delete the item itself
    @items.where(prod_id: prod_id).delete
  end

  def get_all_items_by_priority
    @items.order(:description, :priority).all
  end

  def get_all_active_items_by_priority
    @items.where(status: 'active').order(:description, :priority).all
  end

  def deactivate_missing_items(sheet_prod_ids)
    if readonly?
      puts "🔒 Read-only mode: Skipping deactivation of missing items"
      return 0
    end

    # Find all active items in the database
    active_db_items = @items.where(status: 'active').select_map(:prod_id)
    
    # Determine which items are in the DB but not on the sheet
    items_to_deactivate = active_db_items - sheet_prod_ids
    
    return 0 if items_to_deactivate.empty?
    
    # Update the status of these items to 'inactive'
    @items.where(prod_id: items_to_deactivate).update(status: 'inactive', updated_at: Time.now)
    
    items_to_deactivate.count
  end

  # Purchase management methods
  def record_purchase(prod_id:, quantity: 1, price_cents: nil, purchase_date: Date.today)
    if readonly?
      puts "🔒 Read-only mode: Skipping purchase recording for item #{prod_id}"
      return
    end

    @purchases.insert(
      prod_id: prod_id,
      quantity: quantity,
      price_cents: price_cents,
      purchase_date: purchase_date
    )
  end

  def get_purchase_history(prod_id, limit: 10)
    @purchases
      .where(prod_id: prod_id)
      .order(Sequel.desc(:purchase_timestamp))
      .limit(limit)
      .all
  end

  def get_recent_purchases(days: 30)
    cutoff_date = Date.today - days
    @purchases
      .where { purchase_date >= cutoff_date }
      .order(Sequel.desc(:purchase_timestamp))
      .all
  end

  def find_purchase_by_id(purchase_id)
    @purchases
      .join(:items, prod_id: :prod_id)
      .where(Sequel[:purchases][:id] => purchase_id)
      .select(Sequel[:purchases].*, Sequel[:items][:description].as(:item_description))
      .first
  end

  def update_purchase(purchase_id, updates)
    if readonly?
      puts "🔒 Read-only mode: Skipping update of purchase #{purchase_id}"
      return
    end

    @purchases.where(id: purchase_id).update(updates.merge(purchase_timestamp: Time.now))
  end

  def delete_purchase(purchase_id)
    if readonly?
      puts "🔒 Read-only mode: Skipping deletion of purchase #{purchase_id}"
      return
    end

    @purchases.where(id: purchase_id).delete
  end

  def find_purchases(search_term: nil, start_date: nil, end_date: nil, limit: 20)
    query = @purchases.join(:items, prod_id: :prod_id)

    if search_term && !search_term.empty?
      # Search by prod_id or item description
      query = query.where(
        Sequel.|(
          {Sequel[:purchases][:prod_id] => search_term},
          Sequel.ilike(Sequel[:items][:description], "%#{search_term}%")
        )
      )
    end

    if start_date
      query = query.where(Sequel[:purchases][:purchase_date] >= start_date)
    end

    if end_date
      query = query.where(Sequel[:purchases][:purchase_date] <= end_date)
    end

    query.order(Sequel.desc(Sequel[:purchases][:purchase_date]))
         .limit(limit)
         .select(Sequel[:purchases].*,
                 Sequel[:items][:description].as(:item_description),
                 Sequel[:items][:modifier].as(:item_modifier))
         .all
  end

  # Utility methods
  def extract_prod_id_from_url(url)
    # Walmart URLs have patterns like:
    # https://www.walmart.com/ip/Product-Name/123456789
    # https://www.walmart.com/ip/Product-Name/123456789?param=value
    # Extract at least 4 digits before '?' or end of string
    match = url.match(/\/ip\/[^\/]+\/(\d{4,})(?:\?|$)/)
    match ? match[1] : nil
  end

  def construct_url_from_prod_id(prod_id)
    "https://www.walmart.com/ip/#{prod_id}"
  end

  def get_item_with_purchase_stats(prod_id)
    item = find_item_by_prod_id(prod_id)
    return nil unless item

    # Add purchase statistics
    purchase_count = @purchases.where(prod_id: prod_id).count
    last_purchase = @purchases
      .where(prod_id: prod_id)
      .order(Sequel.desc(:purchase_timestamp))
      .first

    item.merge(
      purchase_count: purchase_count,
      last_purchased: last_purchase ? last_purchase[:purchase_date] : nil,
      days_since_purchase: last_purchase ? (Date.today - last_purchase[:purchase_date]).to_i : nil
    )
  end

  def units_ordered_per_week(prod_id)
    # Get all purchases for the item
    purchases = @purchases.where(prod_id: prod_id).all
    return 0 if purchases.empty?

    # Get the earliest purchase date from the entire database
    earliest_db_purchase_date = get_earliest_purchase_date
    return 0 if earliest_db_purchase_date.nil?

    # Calculate the total number of weeks since the start of the database
    weeks_since_db_start = (Date.today - earliest_db_purchase_date).to_f / 7
    weeks_since_db_start = 1 if weeks_since_db_start < 1 # Avoid division by zero and ensure at least 1 week

    # Calculate the total quantity ordered for this item
    total_quantity = purchases.sum { |p| p[:quantity] }

    # Calculate the average units per week based on weeks since database start
    (total_quantity / weeks_since_db_start).round(2)
  end

  def average_cost_per_month(prod_id)
    # Get all purchases for the item
    purchases = @purchases.where(prod_id: prod_id).all
    return 0 if purchases.empty?

    # Get the earliest purchase date from the entire database
    earliest_db_purchase_date = get_earliest_purchase_date
    return 0 if earliest_db_purchase_date.nil?

    # Calculate the total number of days since the start of the database
    days_since_db_start = (Date.today - earliest_db_purchase_date).to_i
    
    # Convert days to months (approximately)
    # Using 30.44 as the average number of days in a month (365.25 / 12)
    months_since_db_start = days_since_db_start.to_f / 30.44
    months_since_db_start = 1 if months_since_db_start < 1 # Avoid division by zero and ensure at least 1 month

    # Calculate total cost for this item
    total_cost_cents = purchases.sum { |p| (p[:price_cents] || 0) * p[:quantity] }

    # Calculate the average cost per month
    (total_cost_cents / (100.0 * months_since_db_start)).round(2)
  end

  def test_connection
    begin
      @db.test_connection
      puts "✅ Database connection successful"
      return true
    rescue => e
      puts "❌ Database connection failed: #{e.message}"
      return false
    end
  end
  
  def test_backup
    puts "🧪 Testing backup functionality..."
    result = create_rotating_backup
    if result
      puts "✅ Test backup successful: #{result}"
    else
      puts "❌ Test backup failed"
    end
    result
  end
  
  def create_rotating_backup(max_backups: 7)
    if readonly?
      puts "🔒 Read-only mode: Skipping database backup"
      return nil
    end

    require 'fileutils'
    
    backup_dir = File.join(Dir.pwd, 'backups')
    FileUtils.mkdir_p(backup_dir)
    
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    backup_file = File.join(backup_dir, "walmart_backup_#{timestamp}.sql")
    
    begin
      # Get database connection info
      db_config = get_db_config
      
      # Build command parts directly
      cmd_parts = ['pg_dump']
      cmd_parts << "--host=#{db_config[:host]}"
      cmd_parts << "--port=#{db_config[:port]}"
      cmd_parts << "--username=#{db_config[:user]}"
      cmd_parts << "--no-password"
      cmd_parts << "--verbose"
      cmd_parts << "--clean"
      cmd_parts << "--if-exists"
      cmd_parts << "--create"
      cmd_parts << "--file=\"#{backup_file}\""
      cmd_parts << db_config[:database]
      
      puts "Creating database backup: #{File.basename(backup_file)}"
      
      # Set environment variable in Ruby process
      old_pgpassword = ENV['PGPASSWORD']
      ENV['PGPASSWORD'] = db_config[:password] if db_config[:password]
      
      # Use backticks to capture output and check exit status
      output = `#{cmd_parts.join(' ')} 2>&1`
      exit_status = $?.exitstatus
      
      # Restore original environment variable
      if old_pgpassword
        ENV['PGPASSWORD'] = old_pgpassword
      else
        ENV.delete('PGPASSWORD')
      end
      
      if exit_status == 0 && File.exist?(backup_file)
        puts "✅ Backup created successfully: #{backup_file}"
        cleanup_old_backups(backup_dir, max_backups)
        return backup_file
      else
        puts "❌ Backup failed"
        return nil
      end
      
    rescue => e
      puts "❌ Backup error: #{e.message}"
      return nil
    end
  end

  def close
    @db.disconnect if @db
  end

  private
  
  # Helper to get the earliest purchase date from the entire database
  def get_earliest_purchase_date
    # Find the minimum purchase_date across all purchases
    min_date = @purchases.min(:purchase_date)
    min_date
  end
  
  def get_db_config
    database_url = ENV['DATABASE_URL']
    
    if database_url
      # Parse DATABASE_URL format: postgres://user:password@host:port/database
      uri = URI.parse(database_url)
      {
        host: uri.host,
        port: uri.port || 5432,
        database: uri.path[1..-1], # Remove leading slash
        user: uri.user,
        password: uri.password
      }
    else
      # Use individual environment variables
      {
        host: ENV['POSTGRES_HOST'] || 'localhost',
        port: ENV['POSTGRES_PORT'] || 5432,
        database: ENV['POSTGRES_DB'] || 'walmart',
        user: ENV['POSTGRES_USER'] || 'mike',
        password: ENV['POSTGRES_PASSWORD']
      }
    end
  end
  
  
  def cleanup_old_backups(backup_dir, max_backups)
    return unless max_backups > 0
    
    backup_files = Dir.glob(File.join(backup_dir, 'walmart_backup_*.sql'))
                     .sort_by { |f| File.mtime(f) }
                     .reverse # Newest first
    
    if backup_files.length > max_backups
      files_to_delete = backup_files[max_backups..-1]
      files_to_delete.each do |file|
        begin
          File.delete(file)
          puts "🗑️  Deleted old backup: #{File.basename(file)}"
        rescue => e
          puts "⚠️  Could not delete old backup #{File.basename(file)}: #{e.message}"
        end
      end
    end
  end
end

# Singleton pattern for global database access
class Database
  @instance = nil

  def self.instance(readonly: false)
    @instance ||= WalmartDatabase.new(readonly: readonly)
  end

  def self.method_missing(method, *args, &block)
    instance.send(method, *args, &block)
  end

  def self.respond_to_missing?(method, include_private = false)
    instance.respond_to?(method) || super
  end
end