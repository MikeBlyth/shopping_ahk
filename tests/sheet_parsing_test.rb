require 'minitest/autorun'
require_relative '../lib/google_sheets_integration'

# Mocking Google Sheets Service
module Google
  module Apis
    module SheetsV4
      class SheetsService
        attr_accessor :authorization
        
        def get_spreadsheet_values(*args)
          # This will be overridden in the test
          Struct.new(:values).new([])
        end
      end
      
      class ValueRange; end
      class BatchUpdateSpreadsheetRequest; end
    end
  end
  
  module Auth
    class ServiceAccountCredentials
      def self.make_creds(*args); Object.new; end
    end
  end
end

class SheetParsingTest < Minitest::Test
  def setup
    # Create a dummy credentials file if it doesn't exist
    @creds_file = 'google_credentials.json'
    unless File.exist?(@creds_file)
      File.write(@creds_file, '{}')
      @created_creds = true
    end
    
    @syncer = GoogleSheetsIntegration::SheetsSync.new(readonly: true)
  end

  def teardown
    File.delete(@creds_file) if @created_creds
  end

  def test_parsing_stops_at_total
    puts "🧪 Testing that parsing stops when it encounters 'TOTAL' in column 1..."
    # Mock data with a TOTAL row
    rows = [
      ['Purchased', 'Item', 'Price'], # Header
      ['Shopping List', '', ''],      # Delimiter
      ['', 'Milk', '$3.00'],          # Valid Item
      ['TOTAL', '', '$3.00'],         # Total row - Should stop here
      ['', 'Bread', '$2.00']          # Item after total - Should be ignored
    ]
    
    mock_response(rows)
    
    result = @syncer.get_grocery_list
    shopping_list = result[:shopping_list]
    
    assert_equal 1, shopping_list.length
    assert_equal 'Milk', shopping_list.first[:item]
  end

  def test_parsing_stops_at_category
    puts "🧪 Testing that parsing stops when it encounters 'CATEGORY BREAKDOWN'..."
    # Mock data with a CATEGORY row
    rows = [
      ['Purchased', 'Item', 'Price'], # Header
      ['Shopping List', '', ''],      # Delimiter
      ['', 'Eggs', '$4.00'],          # Valid Item
      ['CATEGORY BREAKDOWN', '', ''], # Category header - Should stop here
      ['Dairy', '$10.00', '']         # Category data - Should be ignored
    ]
    
    mock_response(rows)
    
    result = @syncer.get_grocery_list
    shopping_list = result[:shopping_list]
    
    assert_equal 1, shopping_list.length
    assert_equal 'Eggs', shopping_list.first[:item]
  end

  def test_ignores_price_in_description
    puts "🧪 Testing that rows with prices in the description column are ignored..."
    # Mock data with a misplaced price in description column
    rows = [
      ['Purchased', 'Item', 'Price'], # Header
      ['Shopping List', '', ''],      # Delimiter
      ['', 'Cheese', '$5.00'],        # Valid Item
      ['', '$5.00', ''],              # Invalid Item (Price in desc) - Should be ignored
      ['', 'Butter', '$6.00']         # Valid Item
    ]
    
    mock_response(rows)
    
    result = @syncer.get_grocery_list
    shopping_list = result[:shopping_list]
    
    assert_equal 2, shopping_list.length
    assert_equal 'Cheese', shopping_list[0][:item]
    assert_equal 'Butter', shopping_list[1][:item]
  end

  private

  def mock_response(rows)
    # Inject the mock response into the service
    @syncer.instance_variable_get(:@service).define_singleton_method(:get_spreadsheet_values) do |*args|
      Struct.new(:values).new(rows)
    end
  end
end
