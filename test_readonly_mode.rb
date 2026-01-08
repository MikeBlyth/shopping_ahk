require 'minitest/autorun'
require 'stringio'
require_relative 'lib/database'
require_relative 'lib/google_sheets_integration'

class TestReadonlyMode < Minitest::Test
  def setup
    # Initialize DB connection (will use real connection)
    @db = WalmartDatabase.new
    @db.readonly = true
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def test_database_writes_skipped
    puts "\nTesting Database Read-only Mode..."
    
    output = capture_stdout do
      @db.create_item(prod_id: 'TEST_READONLY', url: 'http://test', description: 'Test')
    end
    assert_includes output, "Read-only mode: Skipping create_item"
    
    output = capture_stdout do
      @db.update_item('TEST_READONLY', { description: 'Updated' })
    end
    assert_includes output, "Read-only mode: Skipping update_item"
    
    output = capture_stdout do
      @db.delete_item('TEST_READONLY')
    end
    assert_includes output, "Read-only mode: Skipping delete_item"

    output = capture_stdout do
      @db.record_purchase(prod_id: 'TEST_READONLY')
    end
    assert_includes output, "Read-only mode: Skipping record_purchase"
    
    output = capture_stdout do
      @db.create_rotating_backup
    end
    assert_includes output, "Read-only mode: Skipping create_rotating_backup"
  end

  def test_sheets_writes_skipped
    puts "\nTesting Sheets Read-only Mode..."
    
    if File.exist?('google_credentials.json')
      # We have to be careful with initialization if it does network calls, 
      # but we need an instance to test the method.
      sheets = GoogleSheetsIntegration::SheetsSync.new
      sheets.readonly = true
      
      output = capture_stdout do
        sheets.update_item_url('Test Item', 'http://test')
      end
      assert_includes output, "Read-only mode: Skipping update_item_url"
      
      output = capture_stdout do
        sheets.mark_item_completed('Test Item')
      end
      assert_includes output, "Read-only mode: Skipping mark_item_completed"
      
      output = capture_stdout do
        sheets.sync_from_database(@db)
      end
      assert_includes output, "Read-only mode: Skipping sync_from_database"
      
      # sync_to_database calls DB writes (which are skipped) but also returns stats.
      # It doesn't print "Skipping sync_to_database" itself unless we added that guard.
      # We did add that guard.
      output = capture_stdout do
        sheets.sync_to_database(@db)
      end
      assert_includes output, "Read-only mode: Skipping sync_to_database"
      
    else
      puts "Skipping Sheets test: google_credentials.json not found"
    end
  end
end
