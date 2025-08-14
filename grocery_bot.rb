require 'uri'
require 'csv'
require 'json'
require 'colorize'
require 'dotenv/load'
require_relative 'lib/google_sheets_integration'
require_relative 'lib/database'
require_relative 'lib/ahk_bridge'

class WalmartGroceryAssistant
  def initialize
    @ahk = AhkBridge.new
    @db = Database.instance
    @sheets_sync = GoogleSheetsIntegration.create_sync_client
    
    # Setup cleanup handlers for unexpected exits
    setup_cleanup_handlers
  end

  def start
    begin
      setup_ahk
      
      # Sync Google Sheets data to database first
      puts "📊 Syncing data from Google Sheets..."
      sync_database_from_sheets
      
      # Load items to order (quantity > 0)
      puts "🛒 Loading items to order..."
      grocery_items = load_items_to_order
      
      if grocery_items.empty?
        @ahk.show_message("No items found to order.\n\nPlease set quantity > 0 for items in your Google Sheet.")
        return
      end
      
      puts "🛍️ Found #{grocery_items.length} items to order"
      puts "🚀 Starting shopping automation..."
      
      process_grocery_list(grocery_items)
      
      # Sync any new items back to Google Sheets
      puts "💾 Syncing new items back to Google Sheets..."
      sync_database_to_sheets
      
      @ahk.show_message("Shopping complete!\n\nReview your cart and proceed to checkout when ready.")
      
      # Reset AutoHotkey for next session
      puts "🔄 Resetting for next session..."
      @ahk.session_complete
      puts "✅ Ready for next shopping session!"
      
    rescue => e
      puts "\n❌ An error occurred: #{e.message}"
      puts "📍 Location: #{e.backtrace.first}"
      
      # Try to show error in AutoHotkey if possible
      begin
        @ahk&.show_message("Error occurred in Ruby script:\n\n#{e.message}\n\nCheck terminal for details.")
      rescue
        # If AHK communication fails, just continue with cleanup
      end
      
      # Cleanup will happen automatically via at_exit handler
      raise # Re-raise to maintain normal error behavior
    end
  end

  private

  def setup_cleanup_handlers
    # Cleanup on normal exit
    at_exit { cleanup_on_exit }
    
    # Cleanup on interrupt (Ctrl+C)
    Signal.trap('INT') { cleanup_and_exit('Interrupted by user') }
    Signal.trap('TERM') { cleanup_and_exit('Process terminated') }
    
    # Cleanup on uncaught exceptions
    Thread.abort_on_exception = false
  end
  
  def cleanup_on_exit
    return if @cleanup_done
    @cleanup_done = true
    
    begin
      puts "\n🧹 Cleaning up..."
      
      # Reset AutoHotkey to ready state for next session
      if @ahk
        status = @ahk.check_status
        unless status == 'WAITING_FOR_HOTKEY' || status == 'UNKNOWN'
          puts "🔄 Resetting AutoHotkey for next session..."
          @ahk.session_complete
        end
      end
      
      puts "✅ Cleanup complete"
    rescue => e
      puts "⚠️ Cleanup error (non-critical): #{e.message}"
    end
  end
  
  def cleanup_and_exit(reason)
    puts "\n⚠️ #{reason}"
    cleanup_on_exit
    exit(1)
  end

  def setup_ahk
    # Always start fresh - kill any existing AutoHotkey and clean files
    puts "🧹 Cleaning up any existing AutoHotkey processes..."
    cleanup_existing_ahk
    
    # Start fresh AutoHotkey script
    puts "🚀 Starting fresh AutoHotkey script..."
    start_ahk_script
    sleep(3)  # Give it time to start
    
    # Check if it started successfully
    if ahk_process_running?
      status = @ahk.check_status
      if status == 'WAITING_FOR_HOTKEY'
        puts "✅ AutoHotkey started successfully!"
        wait_for_hotkey_signal
      else
        puts "❌ AutoHotkey started but in unexpected state: #{status}"
        exit
      end
    else
      puts "❌ Failed to start AutoHotkey script. Please check that AutoHotkey is installed."
      exit
    end
  end
  
  def cleanup_existing_ahk
    # Kill any existing AutoHotkey processes
    system("taskkill /F /IM AutoHotkey*.exe 2>nul")
    
    # Clean up communication files
    [@ahk.class::COMMAND_FILE, @ahk.class::STATUS_FILE, @ahk.class::RESPONSE_FILE].each do |file|
      File.delete(file) if File.exist?(file)
    end
  end
  
  def ahk_process_running?
    # Check if AutoHotkey process is actually running
    result = `tasklist /FI "IMAGENAME eq AutoHotkey*" 2>nul`
    result.include?("AutoHotkey")
  end
  
  def start_ahk_script
    script_path = File.join(__dir__, 'grocery_automation_hotkey.ahk')
    
    unless File.exist?(script_path)
      puts "❌ AutoHotkey script not found: #{script_path}"
      exit
    end
    
    # Start the AutoHotkey script in the background
    system("start \"\" \"#{script_path}\"")
  end
  
  def wait_for_hotkey_signal
    puts "🎯 AutoHotkey is ready and waiting for you!"
    puts "📋 Instructions:"
    puts "   1. Open your browser to walmart.com"
    puts "   2. Press Ctrl+Shift+R when you're ready"
    puts ""
    puts "⏳ Waiting for ready signal..."
    
    # Wait for user to press the hotkey
    loop do
      sleep(1)
      current_status = @ahk.check_status
      break if current_status == 'READY'
    end
    
    puts "✅ Ready signal received! Starting automation..."
    sleep(1)
  end


  def sync_database_from_sheets
    if @sheets_sync
      result = @sheets_sync.sync_to_database(@db)
      # Sync happens silently in background
    end
  end

  def load_items_to_order
    if @sheets_sync
      all_items = @sheets_sync.get_grocery_list
      
      # Filter for items with quantity > 0
      items_to_order = all_items.select { |item| item[:quantity] > 0 }
      
      # Return just the item names for processing
      items_to_order.map { |item| item[:item] }
    else
      # Fallback if sheets not available
      []
    end
  end

  def sync_database_to_sheets
    if @sheets_sync
      result = @sheets_sync.sync_from_database(@db)
      # Sync happens silently in background
    end
  end


  def load_grocery_list_from_sheets
    if @sheets_sync
      puts "Loading grocery list from Google Sheets...".colorize(:blue)
      sheet_items = @sheets_sync.get_grocery_list
      
      if sheet_items.empty?
        puts "No items found in Google Sheets.".colorize(:yellow)
        return []
      end
      
      # For now, return all item names. Later this could filter based on some criteria
      items = sheet_items.map { |item| item[:item] }.reject(&:empty?)
      
      puts "Found #{items.length} items in sheet.".colorize(:green)
      items
    else
      puts "Google Sheets not available, using fallback list.".colorize(:yellow)
      ['milk', 'bread', 'eggs', 'bananas', 'chicken breast']
    end
  end

  def find_item_in_database(item_name)
    # First try exact description match
    item = @db.find_item_by_description(item_name)
    return item if item
    
    # If not found, try fuzzy matching on description
    items = @db.get_all_items_by_priority
    items.find { |db_item| 
      item_name.downcase.include?(db_item[:description].downcase) ||
      db_item[:description].downcase.include?(item_name.downcase)
    }
  end

  def process_grocery_list(items)
    items.each_with_index do |item_name, index|
      # Show progress
      @ahk.show_progress(index + 1, items.length, item_name)
      
      # Check if item exists in database
      db_item = find_item_in_database(item_name)
      
      if db_item
        navigate_to_known_item(db_item)
      else
        search_for_new_item(item_name)
      end
      
      handle_user_interaction(item_name, db_item)
      sleep(1)
    end
  end

  def navigate_to_known_item(item)
    @ahk.open_url(item[:url])
    sleep(2)
  end

  def search_for_new_item(item_name)
    @ahk.search_walmart(item_name)
    sleep(2)
  end

  def handle_user_interaction(item_name, db_item = nil)
    if db_item
      # Known item
      item_name = db_item[:description]
      url = db_item[:url]
      description = "Priority: #{db_item[:priority]}, Default Qty: #{db_item[:default_quantity]}"
      
      response = @ahk.show_item_prompt(item_name, is_known: true, url: url, description: description)
    else
      # New item
      response = @ahk.show_item_prompt(item_name, is_known: false)
    end
    
    case response
    when 'save_url'
      save_new_item(item_name)
    when 'record_price'
      record_manual_price(db_item || { description: item_name })
    else
      # continue - do nothing
    end
  end

  

  def record_manual_price(item)
    price_float = @ahk.get_price_input
    
    if price_float
      price_cents = (price_float * 100).to_i
      
      # If this is a known item, record the purchase
      if item[:prod_id]
        record_purchase(item, price_cents: price_cents)
      end
      
      return price_cents
    else
      return nil
    end
  end

  def save_new_item(item_name)
    current_url = @ahk.get_current_url
    
    if current_url && current_url.include?('walmart.com') && current_url.include?('/ip/')
      prod_id = @db.extract_prod_id_from_url(current_url)
      
      if prod_id
        @db.create_item(
          prod_id: prod_id,
          url: current_url,
          description: item_name,
          modifier: nil,
          default_quantity: 1,
          priority: 5
        )
        
        # Update Google Sheets with URL
        if @sheets_sync
          @sheets_sync.update_item_url(item_name, current_url)
        end
        
        @ahk.show_message("✅ Saved item: #{item_name}\n\nURL: #{current_url}")
      else
        @ahk.show_message("❌ Could not extract product ID from URL\n\nURL: #{current_url}")
      end
    else
      @ahk.show_message("⚠️ This doesn't look like a Walmart product page.\n\nCurrent URL: #{current_url}")
    end
  end

  def record_purchase(item, price_cents: nil, quantity: nil)
    quantity ||= item[:default_quantity]
    
    @db.record_purchase(
      prod_id: item[:prod_id],
      quantity: quantity,
      price_cents: price_cents
    )
    
    # Mark item as completed in Google Sheets
    if @sheets_sync
      @sheets_sync.mark_item_completed(item[:description])
    end
    
    if price_cents
      price_display = "$#{sprintf('%.2f', price_cents / 100.0)}"
      puts "📊 Recorded purchase: #{quantity}x #{item[:description]} @ #{price_display}".colorize(:blue)
    else
      puts "📊 Recorded purchase: #{quantity}x #{item[:description]} (no price)".colorize(:blue)
    end
  end
end

if __FILE__ == $0
  assistant = WalmartGroceryAssistant.new
  assistant.start
end