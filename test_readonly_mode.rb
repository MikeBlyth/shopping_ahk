require 'minitest/autorun'
require 'dotenv/load'
require 'stringio'
require_relative 'lib/database'
require_relative 'lib/google_sheets_integration'

class TestReadonlyMode < Minitest::Test
  def setup
    # Initialize DB connection in readonly mode via constructor
    @db = WalmartDatabase.new(readonly: true)
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
      # Note: 'url' parameter is no longer used in create_item
      @db.create_item(prod_id: 'TEST_READONLY', description: 'Test')
    end
    assert_includes output, "Read-only mode: Skipping creation of item"

    output = capture_stdout do
      @db.update_item('TEST_READONLY', { description: 'Updated' })
    end
    assert_includes output, "Read-only mode: Skipping update of item"

    output = capture_stdout do
      @db.delete_item('TEST_READONLY')
    end
    assert_includes output, "Read-only mode: Skipping deletion of item"

    output = capture_stdout do
      @db.record_purchase(prod_id: 'TEST_READONLY')
    end
    assert_includes output, "Read-only mode: Skipping purchase recording"

    output = capture_stdout do
      @db.create_rotating_backup
    end
    assert_includes output, "Read-only mode: Skipping database backup"
  end

  def test_sheets_writes_skipped
    puts "\nTesting Sheets Read-only Mode..."

    if File.exist?('google_credentials.json')
      # Initialize Sheets in readonly mode via constructor
      sheets = GoogleSheetsIntegration::SheetsSync.new(readonly: true)

      output = capture_stdout do
        sheets.update_item_url('Test Item', 'http://test')
      end
      assert_includes output, "Read-only mode: Skipping Google Sheets URL update"

      output = capture_stdout do
        sheets.mark_item_completed('Test Item')
      end
      assert_includes output, "Read-only mode: Skipping marking item"

      output = capture_stdout do
        sheets.sync_from_database(@db)
      end
      assert_includes output, "Read-only mode: Skipping sync from Database to Sheets"

      output = capture_stdout do
        sheets.sync_to_database(@db)
      end
      assert_includes output, "Read-only mode: Skipping sync from Sheets to Database"

    else
      puts "Skipping Sheets test: google_credentials.json not found"
    end
  end
end