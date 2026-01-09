require 'minitest/autorun'
require 'sequel'
require_relative '../lib/database'
require_relative '../lib/google_sheets_integration'

# --- MOCKS ---

class MockDataset
  attr_reader :updates, :inserts, :data
  attr_accessor :filters

  def initialize
    @data = [] # Store "rows" here
    @updates = []
    @inserts = []
    @filters = {}
  end

  def insert(row)
    @inserts << row
    @data << row
  end

  def update(values)
    @updates << values
    # In a real DB, this would update matched rows. 
    # For this mock, we just record the update call.
    # However, if we need logic (like updating status), we can try to apply it to @data
    # based on @filters.
    if @filters[:prod_id]
      target_ids = Array(@filters[:prod_id])
      @data.each do |row|
        if target_ids.include?(row[:prod_id])
          row.merge!(values)
        end
      end
    end
  end

  def where(conditions)
    # Store conditions for later assertions or logic
    @filters = @filters.merge(conditions)
    self
  end
  
  def select_map(column)
    # Simple implementation for get_all_active_prod_ids
    filtered_data = @data
    if @filters[:status]
      filtered_data = filtered_data.select { |row| row[:status] == @filters[:status] }
    end
    filtered_data.map { |row| row[column] }
  end

  def first
    # Simple implementation to find item
    filtered_data = @data
    if @filters[:prod_id]
      filtered_data = filtered_data.select { |row| row[:prod_id] == @filters[:prod_id] }
    end
    filtered_data.first
  end
  
  # Reset filters for chaining (simplified)
  def reset_filters
    @filters = {}
  end
end

class MockDB
  attr_reader :datasets

  def initialize
    @datasets = Hash.new { |h, k| h[k] = MockDataset.new }
  end

  def [](table_name)
    @datasets[table_name]
  end
  
  def disconnect; end
  
  def transaction
    yield
  end
end

class TestWalmartDatabase < WalmartDatabase
  def connect_to_database
    @mock_db ||= MockDB.new
  end

  def mock_db
    @db
  end
  
  # Helper to seed data
  def seed_item(prod_id, status)
    @db[:items].data << { prod_id: prod_id, status: status, description: "Item #{prod_id}", url: "http://#{prod_id}" }
  end
end

# Override SheetsSync to allow injecting mock sheet data
class TestSheetsSync < GoogleSheetsIntegration::SheetsSync
  attr_accessor :mock_sheet_data

  def initialize(readonly: false)
    # Skip standard init to avoid auth
    @readonly = readonly
    @mock_sheet_data = { product_list: [], shopping_list: [] }
  end

  def get_grocery_list
    @mock_sheet_data
  end
  
  def authorize
    nil
  end
end


# --- TESTS ---

class SyncStatusTest < Minitest::Test

  def setup
    @db = TestWalmartDatabase.new(readonly: false)
    @syncer = TestSheetsSync.new(readonly: false)
  end

  def test_new_item_marked_active
    # Sheet has one item
    @syncer.mock_sheet_data = {
      product_list: [{ 
        item: 'New Item', 
        url: 'http://walmart.com/ip/100', 
        itemno: '100',
        priority: 1, quantity: 1, subscribable: 0, category: 'Food', modifier: '' 
      }], 
      shopping_list: [] 
    }

    # Run sync
    @syncer.sync_to_database(@db)

    # Assertions
    items_table = @db.mock_db[:items]
    assert_equal 1, items_table.inserts.length
    assert_equal 'active', items_table.inserts.first[:status]
    assert_equal '100', items_table.inserts.first[:prod_id]
  end

  def test_existing_inactive_item_reactivated
    # Seed DB with inactive item
    @db.seed_item('200', 'inactive')
    
    # Sheet has that item
    @syncer.mock_sheet_data = {
      product_list: [{ 
        item: 'Existing Item', 
        url: 'http://walmart.com/ip/200', 
        itemno: '200',
        priority: 1, quantity: 1, subscribable: 0, category: 'Food', modifier: '' 
      }], 
      shopping_list: [] 
    }

    # Run sync
    @syncer.sync_to_database(@db)
    
    # Assertions
    # Check if update was called with status: 'active'
    items_table = @db.mock_db[:items]
    # We check the actual data in our simplified mock
    item = items_table.data.find { |row| row[:prod_id] == '200' }
    assert_equal 'active', item[:status], "Item 200 should be reactivated"
  end

  def test_missing_item_deactivated
    # Seed DB with active item that is NOT in the sheet
    @db.seed_item('300', 'active')
    # And one that IS in the sheet
    @db.seed_item('400', 'active')
    
    # Sheet has only item 400
    @syncer.mock_sheet_data = {
      product_list: [{ 
        item: 'Item 400', 
        url: 'http://walmart.com/ip/400', 
        itemno: '400',
        priority: 1, quantity: 1, subscribable: 0, category: 'Food', modifier: '' 
      }], 
      shopping_list: [] 
    }

    # Run sync
    capture_io do
      @syncer.sync_to_database(@db)
    end
    
    # Assertions
    items_table = @db.mock_db[:items]
    
    item_300 = items_table.data.find { |row| row[:prod_id] == '300' }
    assert_equal 'inactive', item_300[:status], "Item 300 should be deactivated because it was missing from sheet"
    
    item_400 = items_table.data.find { |row| row[:prod_id] == '400' }
    assert_equal 'active', item_400[:status], "Item 400 should remain active"
  end
  
  def test_bulk_deactivate_items_logic
    # Test the database helper directly
    @db.seed_item('A', 'active')
    @db.seed_item('B', 'active')
    
    @db.bulk_deactivate_items(['A'])
    
    items_table = @db.mock_db[:items]
    item_a = items_table.data.find { |row| row[:prod_id] == 'A' }
    item_b = items_table.data.find { |row| row[:prod_id] == 'B' }
    
    assert_equal 'inactive', item_a[:status]
    assert_equal 'active', item_b[:status]
  end
  
  def test_get_all_active_prod_ids
    @db.seed_item('X', 'active')
    @db.seed_item('Y', 'inactive')
    
    active_ids = @db.get_all_active_prod_ids
    assert_includes active_ids, 'X'
    refute_includes active_ids, 'Y'
  end
end
