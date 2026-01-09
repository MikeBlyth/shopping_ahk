require 'minitest/autorun'
require 'sequel'
require_relative '../lib/database'
require_relative '../lib/google_sheets_integration'

# --- MOCKS ---

# Mocking the Sequel Database and Dataset
class MockDataset
  attr_reader :insert_called, :update_called, :delete_called

  def initialize
    @insert_called = false
    @update_called = false
    @delete_called = false
  end

  def insert(*args)
    @insert_called = true
  end

  def update(*args)
    @update_called = true
  end

  def delete
    @delete_called = true
  end

  def where(*args)
    self # Return self for chaining
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
end

# Subclass WalmartDatabase to inject our MockDB
class TestWalmartDatabase < WalmartDatabase
  def connect_to_database
    @mock_db ||= MockDB.new
  end

  # Helper to access the mock for assertions
  def mock_db
    @db
  end
end

# Monkey-patch Google Sheets Service for testing
module Google
  module Apis
    module SheetsV4
      class SheetsService
        # We assume authorization is handled or mocked
        
        def get_spreadsheet_values(*args)
          # Return dummy response object with header and one row
          Struct.new(:values).new([
            ['Item Name', 'URL', 'Purchased'],
            ['Milk', 'http://old', '']
          ])
        end
        
        def update_spreadsheet_value(*args)
          raise "WRITE_OP: update_spreadsheet_value"
        end
        
        def batch_update_spreadsheet(*args)
          raise "WRITE_OP: batch_update_spreadsheet"
        end
        
        def clear_values(*args)
          raise "WRITE_OP: clear_values"
        end
      end
      
      # Stub request classes if they don't exist (mocking the gem structure if not loaded)
      class ValueRange; def initialize(*args); end; end
      class BatchUpdateSpreadsheetRequest; def initialize(*args); end; end
    end
  end
  
  module Auth
    class ServiceAccountCredentials
      def self.make_creds(*args); Object.new; end
    end
  end
end

# --- TESTS ---

class ReadOnlyModeTest < Minitest::Test
  def setup
    # Ensure credentials file exists for SheetsSync initialization
    @creds_file = 'google_credentials.json'
    unless File.exist?(@creds_file)
      File.write(@creds_file, '{}')
      @created_creds = true
    end
  end

  def teardown
    File.delete(@creds_file) if @created_creds
  end

  # --- Database Tests ---

  def test_database_readonly_create_item
    puts "🧪 Testing database read-only mode for creating items..."
    db_wrapper = TestWalmartDatabase.new(readonly: true)
    
    out, _ = capture_io do
      db_wrapper.create_item(
        prod_id: '123', 
        url: 'http://example.com', 
        description: 'Test'
      )
    end
    
    assert_match(/Read-only mode/, out)
    refute db_wrapper.mock_db[:items].insert_called, "Insert should not be called in read-only mode"
  end

  def test_database_readonly_update_item
    puts "🧪 Testing database read-only mode for updating items..."
    db_wrapper = TestWalmartDatabase.new(readonly: true)
    
    out, _ = capture_io do
      db_wrapper.update_item('123', { description: 'Updated' })
    end

    assert_match(/Read-only mode/, out)
    refute db_wrapper.mock_db[:items].update_called, "Update should not be called in read-only mode"
  end

  def test_database_readonly_delete_item
    puts "🧪 Testing database read-only mode for deleting items..."
    db_wrapper = TestWalmartDatabase.new(readonly: true)
    
    out, _ = capture_io do
      db_wrapper.delete_item('123')
    end

    assert_match(/Read-only mode/, out)
    refute db_wrapper.mock_db[:items].delete_called, "Delete (items) should not be called in read-only mode"
    refute db_wrapper.mock_db[:purchases].delete_called, "Delete (purchases) should not be called in read-only mode"
  end

  def test_database_readonly_record_purchase
    puts "🧪 Testing database read-only mode for recording purchases..."
    db_wrapper = TestWalmartDatabase.new(readonly: true)
    
    out, _ = capture_io do
      db_wrapper.record_purchase(prod_id: '123')
    end

    assert_match(/Read-only mode/, out)
    refute db_wrapper.mock_db[:purchases].insert_called, "Insert (purchase) should not be called in read-only mode"
  end

  def test_database_readonly_backup
    puts "🧪 Testing database read-only mode for creating backups..."
    db_wrapper = TestWalmartDatabase.new(readonly: true)
    
    out, _ = capture_io do
      result = db_wrapper.create_rotating_backup
      assert_nil result
    end
    
    assert_match(/Read-only mode: Skipping database backup/, out)
  end
  
  def test_database_write_mode_create_item
    puts "🧪 Testing database write mode for creating items..."
    db_wrapper = TestWalmartDatabase.new(readonly: false)
    
    # In write mode, it connects to our MockDB. 
    db_wrapper.create_item(
      prod_id: '123', 
      url: 'http://example.com', 
      description: 'Test'
    )
    
    assert db_wrapper.mock_db[:items].insert_called, "Insert SHOULD be called in write mode"
  end

  # --- Google Sheets Tests ---

  def test_sheets_readonly_update_url
    puts "🧪 Testing Google Sheets read-only mode for updating URLs..."
    client = GoogleSheetsIntegration::SheetsSync.new(readonly: true)
    
    out, _ = capture_io do
      result = client.update_item_url('Milk', 'http://new-url')
      refute result
    end
    
    assert_match(/Read-only mode/, out)
  end
  
  def test_sheets_readonly_mark_completed
    puts "🧪 Testing Google Sheets read-only mode for marking items completed..."
    client = GoogleSheetsIntegration::SheetsSync.new(readonly: true)
    
    out, _ = capture_io do
      result = client.mark_item_completed('Milk')
      refute result
    end
    
    assert_match(/Read-only mode/, out)
  end
  
  def test_sheets_readonly_sync_from_database
    puts "🧪 Testing Google Sheets read-only mode for syncing from database..."
    client = GoogleSheetsIntegration::SheetsSync.new(readonly: true)
    db_mock = Object.new 
    
    out, _ = capture_io do
      client.sync_from_database(db_mock)
    end
    
    assert_match(/Read-only mode/, out)
  end

  def test_sheets_write_mode_attempts_write
    puts "🧪 Testing Google Sheets write mode for write operations..."
    client = GoogleSheetsIntegration::SheetsSync.new(readonly: false)
    
    # In write mode, calling update_item_url should eventually hit the mocked API which raises an error
    error = assert_raises(RuntimeError) do
      client.update_item_url('Milk', 'http://url')
    end
    
    assert_equal "WRITE_OP: update_spreadsheet_value", error.message
  end
end
