require 'sequel'
require 'pg'

class WalmartDatabase
  def initialize
    @db = connect_to_database
    setup_models
  end

  attr_reader :db

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

  def create_item(prod_id:, url:, description:, modifier: nil, default_quantity: 1, priority: 1)
    # Normalize priority: treat nil or empty as 1 (highest priority)
    normalized_priority = (priority.nil? || priority == '') ? 1 : priority
    
    @items.insert(
      prod_id: prod_id,
      url: url,
      description: description,
      modifier: modifier,
      default_quantity: default_quantity,
      priority: normalized_priority
    )
  end

  def update_item(prod_id, updates)
    # Normalize priority if it's being updated
    if updates.key?(:priority)
      priority = updates[:priority]
      updates[:priority] = (priority.nil? || priority == '') ? 1 : priority
    end
    
    @items.where(prod_id: prod_id).update(updates.merge(updated_at: Time.now))
  end

  def update_item_description(prod_id, new_description)
    @items.where(prod_id: prod_id).update(description: new_description)
  end

  def delete_item(prod_id)
    # First delete all purchase records for this item
    @purchases.where(prod_id: prod_id).delete
    # Then delete the item itself
    @items.where(prod_id: prod_id).delete
  end

  def get_all_items_by_priority
    @items.order(:description, :priority).all
  end

  # Purchase management methods
  def record_purchase(prod_id:, quantity: 1, price_cents: nil, purchase_date: Date.today)
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

  # Utility methods
  def extract_prod_id_from_url(url)
    # Walmart URLs have patterns like:
    # https://www.walmart.com/ip/Product-Name/123456789
    # https://www.walmart.com/ip/Product-Name/123456789?param=value
    # Extract at least 4 digits before '?' or end of string
    match = url.match(/\/ip\/[^\/]+\/(\d{4,})(?:\?|$)/)
    match ? match[1] : nil
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
  
  def close
    @db.disconnect if @db
  end
end

# Singleton pattern for global database access
class Database
  @instance = nil

  def self.instance
    @instance ||= WalmartDatabase.new
  end

  def self.method_missing(method, *args, &block)
    instance.send(method, *args, &block)
  end

  def self.respond_to_missing?(method, include_private = false)
    instance.respond_to?(method) || super
  end
end