require 'uri'
require 'csv'
require 'json'
require 'colorize'
require 'dotenv/load'
require_relative 'lib/google_sheets_integration'
require 'debug' # Add the debugger
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
    setup_ahk

    # Sync Google Sheets data to database first
    puts '📊 Syncing data from Google Sheets...'
    sync_database_from_sheets

    # Load items to order (quantity > 0)
    puts '🛒 Loading items to order...'
    grocery_items = load_items_to_order

    if grocery_items.empty?
      puts 'No items found to order.'
    else
      puts "🛍️ Found #{grocery_items.length} items to order"
      puts '🚀 Starting shopping automation...'

      process_grocery_list(grocery_items)

      @ahk.show_message("Shopping complete!\n\nReview your cart and proceed to checkout when ready.")
    end

    # Shopping list processing complete - signal session complete to show persistent tooltip
    if grocery_items.empty?
      puts '✅ No items processed.'
    else
      puts '✅ Shopping list processing complete!'
    end

    # Signal AHK to show completion status and persistent tooltip (don't read response)
    @ahk.send_command('LIST_COMPLETE')

    # Wait for AHK to signal that user wants to end
    puts '⏳ Waiting for user to exit (Ctrl+Shift+Q)...'
    wait_for_ahk_shutdown

    # Sync database items back to Google Sheets when user is done
    puts '💾 Syncing database items to Google Sheets...'
    sync_database_to_sheets
  rescue StandardError => e
    puts "\n❌ An error occurred: #{e.message}"
    puts "📍 Location: #{e.backtrace.first}"

    # Try to show error in AutoHotkey if possible
    begin
      @ahk&.show_message("Error occurred in Ruby script:\n\n#{e.message}\n\nCheck terminal for details.")
    rescue StandardError
      # If AHK communication fails, just continue with cleanup
    end

    # Cleanup will happen automatically via at_exit handler
    raise # Re-raise to maintain normal error behavior
  end

  private

  def setup_cleanup_handlers
    # at_exit handles ALL exit scenarios: normal exit, exceptions, interrupts, crashes, etc.
    at_exit { cleanup_on_exit }
  end

  def cleanup_on_exit
    return if @cleanup_done

    @cleanup_done = true

    begin
      puts "\n🧹 Cleaning up and signaling AutoHotkey to close..."

      # Signal AHK to terminate gracefully
      @ahk.terminate_ahk if @ahk

      puts '✅ Cleanup complete'
    rescue StandardError => e
      puts "⚠️ Cleanup error (non-critical): #{e.message}"
    end
  end

  def setup_ahk
    # Always start fresh - kill any existing AutoHotkey and clean files
    puts '🧹 Cleaning up any existing AutoHotkey processes...'
    cleanup_existing_ahk

    # Start fresh AutoHotkey script
    puts '🚀 Starting fresh AutoHotkey script...'
    start_ahk_script
    sleep(1) # Give it time to start

    # Check if it started successfully
    if ahk_process_running?
      status = @ahk.check_status
      if status == 'WAITING_FOR_HOTKEY'
        puts '✅ AutoHotkey started successfully!'
        wait_for_hotkey_signal
      else
        puts "❌ AutoHotkey started but in unexpected state: #{status}"
        exit
      end
    else
      puts '❌ Failed to start AutoHotkey script. Please check that AutoHotkey is installed.'
      exit
    end
  end

  def cleanup_existing_ahk
    # Kill any existing AutoHotkey processes
    system('taskkill /F /IM AutoHotkey*.exe 2>nul')

    # Clean up communication files
    [@ahk.class::COMMAND_FILE, @ahk.class::STATUS_FILE, @ahk.class::RESPONSE_FILE].each do |file|
      File.delete(file) if File.exist?(file)
    end
  end

  def ahk_process_running?
    # Check if AutoHotkey process is actually running
    result = `tasklist /FI "IMAGENAME eq AutoHotkey*" 2>nul`
    result.include?('AutoHotkey')
  end

  def start_ahk_script
    script_path = File.join(__dir__, 'grocery_automation.ahk')

    unless File.exist?(script_path)
      puts "❌ AutoHotkey script not found: #{script_path}"
      exit
    end

    # Start the AutoHotkey script in the background
    system("start \"\" \"#{script_path}\"")
  end

  def wait_for_hotkey_signal
    puts '🎯 AutoHotkey is ready and waiting for you!'
    puts '📋 Instructions:'
    puts '   1. Open your browser to walmart.com'
    puts "   2. Press Ctrl+Shift+R when you're ready"
    puts ''
    puts '⏳ Waiting for ready signal...'

    # Wait for user to press the hotkey
    loop do
      sleep(1)
      current_status = @ahk.check_status
      break if current_status == 'READY'
    end

    puts '✅ Ready signal received! Starting automation...'
    sleep(1)
  end

  def sync_database_from_sheets
    return unless @sheets_sync

    result = @sheets_sync.sync_to_database(@db)
    # Sync happens silently in background
  end

  def load_items_to_order
    if @sheets_sync
      sheet_data = @sheets_sync.get_grocery_list

      # Process only shopping list items with quantity != 0 AND no purchase mark
      shopping_items = sheet_data[:shopping_list]
      items_to_order = shopping_items.select do |item|
        item[:quantity] != 0 && (item[:purchased].nil? || item[:purchased].strip.empty?)
      end

      # Store shopping list for later rewriting (keep all items, not just ones to order)
      @shopping_list_data = shopping_items

      # Return just the item names for processing
      items_to_order.map { |item| item[:item] }
    else
      # Fallback if sheets not available
      @shopping_list_data = []
      []
    end
  end

  def sync_database_to_sheets
    return unless @sheets_sync

    # Pass shopping list data to preserve it during sheet rewrite
    shopping_data = @shopping_list_data || []
    result = @sheets_sync.sync_from_database(@db, shopping_data)
    # Sync happens silently in background
  end

  def load_grocery_list_from_sheets
    if @sheets_sync
      puts 'Loading grocery list from Google Sheets...'.colorize(:blue)
      sheet_items = @sheets_sync.get_grocery_list

      if sheet_items.empty?
        puts 'No items found in Google Sheets.'.colorize(:yellow)
        return []
      end

      # For now, return all item names. Later this could filter based on some criteria
      items = sheet_items.map { |item| item[:item] }.reject(&:empty?)

      puts "Found #{items.length} items in sheet.".colorize(:green)
      items
    else
      puts 'Google Sheets not available, using fallback list.'.colorize(:yellow)
      ['milk', 'bread', 'eggs', 'bananas', 'chicken breast']
    end
  end

  def normalize_priority(priority)
    # Treat nil or empty priority as 1 (highest priority)
    return 1 if priority.nil? || priority == ''

    priority
  end

  def find_item_in_database(item_name)
    # Get all potential matches and rank them
    matches = find_and_rank_matches(item_name)

    return nil if matches.empty?

    # Check for exact matches with different priorities
    exact_matches = matches.select { |match| match[:match_type] == :exact }

    if exact_matches.length > 1
      # Multiple exact matches - return highest priority (lowest number)
      exact_matches.min_by { |match| normalize_priority(match[:item][:priority]) }[:item]
    elsif exact_matches.length == 1
      # Single exact match
      exact_matches.first[:item]
    elsif matches.length == 1
      # Single fuzzy match
      matches.first[:item]
    else
      # Multiple fuzzy matches - user needs to choose
      result = handle_multiple_matches(item_name, matches)
      result == :search_new_item ? nil : result
    end
  end

  def find_and_rank_matches(item_name)
    matches = []

    # Get all database items
    all_items = @db.get_all_items_by_priority

    all_items.each do |db_item|
      # Calculate match score against description only
      desc_score = calculate_match_score(item_name, db_item[:description])

      # Calculate match score against description + modifier combined
      combined_text = [db_item[:description], db_item[:modifier]].compact.join(' ')
      combined_score = calculate_match_score(item_name, combined_text)

      # Use the higher of the two scores
      match_score = [desc_score, combined_score].max
      next if match_score == 0

      # Check for exact matches (either description alone or with modifier)
      item_lower = item_name.downcase.strip
      desc_lower = db_item[:description].downcase.strip
      combined_lower = combined_text.downcase.strip

      match_type = item_lower == desc_lower || item_lower == combined_lower ? :exact : :fuzzy

      matches << {
        item: db_item,
        score: match_score,
        match_type: match_type
      }
    end

    # Sort by match type (exact first), then by score (higher first), then by priority (lower first)
    matches.sort_by do |match|
      [
        match[:match_type] == :exact ? 0 : 1, # Exact matches first
        -match[:score], # Higher scores first
        normalize_priority(match[:item][:priority]) # Lower priority numbers first
      ]
    end
  end

  def calculate_match_score(item_name, description)
    item_lower = item_name.downcase.strip
    desc_lower = description.downcase.strip

    # Exact match
    return 100 if item_lower == desc_lower

    # One contains the other
    if item_lower.include?(desc_lower) || desc_lower.include?(item_lower)
      # Prefer shorter descriptions (more specific)
      containment_score = 50
      length_bonus = 100 - [(item_lower.length - desc_lower.length).abs, 50].min
      return containment_score + length_bonus
    end

    # Word overlap scoring
    item_words = item_lower.split(/\s+/)
    desc_words = desc_lower.split(/\s+/)
    common_words = item_words & desc_words

    return 0 if common_words.empty?

    # Score based on percentage of words that match
    overlap_ratio = common_words.length.to_f / [item_words.length, desc_words.length].max
    (overlap_ratio * 30).to_i
  end

  def handle_multiple_matches(item_name, matches)
    # Prepare match list for AHK selection (AHK will add numbers automatically)
    match_options = matches.map do |match|
      item = match[:item]
      display_priority = item[:priority].nil? || item[:priority] == '' ? 'blank (=1)' : item[:priority]
      "#{item[:description]} (Priority: #{display_priority}, Score: #{match[:score]})"
    end

    # Add option to search for new item
    search_option_number = match_options.length + 1
    match_options << "Search for new item: '#{item_name}'"

    selection = @ahk.show_multiple_choice(
      title: "Multiple matches for: #{item_name}",
      options: match_options,
      allow_skip: true
    )

    # Check if user selected existing match
    return matches[selection - 1][:item] if selection && selection > 0 && selection <= matches.length

    # Check if user selected "search for new item"
    return :search_new_item if selection == search_option_number

    nil # User skipped or invalid selection
  end

  def process_grocery_list(items)
    puts "🛒 Processing #{items.length} items..."

    items.each_with_index do |item_name, index|
      puts "📦 Processing item #{index + 1}/#{items.length}: #{item_name}"

      # FAILSAFE: 4-second delay between items to prevent runaway behavior
      puts '⏳ Failsafe delay (4 seconds)...'

      # Check if item exists in database
      db_item = find_item_in_database(item_name)

      if db_item && db_item != :search_new_item
        puts "   ✅ Found in database: #{db_item[:prod_id]} - #{db_item[:description]}"
        navigate_to_known_item(db_item)

        puts '   💬 Showing user interaction dialog...'
        sleep(1)
        response = handle_user_interaction(item_name, db_item)
        handle_add_new_item(response) if response
      elsif db_item == :search_new_item
        puts '   🔍 User selected "Search for new item" - searching Walmart...'
        response = search_for_new_item(item_name)
        handle_add_new_item(response) if response
      else
        puts '   🔍 New item - searching Walmart...'
        response = search_for_new_item(item_name)
        handle_add_new_item(response) if response
      end
    end
  end

  def navigate_to_known_item(item)
    @ahk.open_url(item[:url])
    sleep(2)
  end

  def search_for_new_item(item_name)
    # Send search command and wait for user response (Ctrl+Shift+A)
    response = @ahk.search_walmart(item_name)
    return response if response && !response.empty? && response != 'skip'

    nil
  end

  def handle_add_new_item(response_data)
    puts "🔍 DEBUG: Processing add item response: #{response_data}"
    parts = response_data.split('|')
    puts "🔍 DEBUG: Split into #{parts.length} parts: #{parts.inspect}"

    # Check if this is the new combined format
    if parts[0] == 'add_and_purchase' && parts.length >= 8
      puts '🔍 DEBUG: Using add_and_purchase format'
      return handle_add_and_purchase(parts[1..-1])
    end

    # Original format: description|modifier|priority|default_quantity|url
    return nil if parts.length < 5

    description = parts[0].strip
    modifier = parts[1].strip
    priority = parts[2].strip.to_i
    default_quantity = parts[3].strip.to_i
    url = parts[4].strip

    return nil if description.empty? || url.empty?

    # Validate URL format
    unless url.include?('walmart.com') && url.include?('/ip/')
      puts "❌ Invalid URL: #{url}"
      puts "   URL must be a Walmart product page (contain 'walmart.com' and '/ip/')"
      return nil
    end

    # Normalize URL - remove query parameters and fragments
    url = url.split('?').first.split('#').first

    # Extract product ID from URL
    puts "🔍 DEBUG: Extracting product ID from URL: #{url}"
    prod_id = @db.extract_prod_id_from_url(url)
    puts "🔍 DEBUG: Extracted product ID: #{prod_id}"
    return nil unless prod_id

    # Check if item already exists
    existing_item = @db.find_item_by_prod_id(prod_id)
    if existing_item
      puts "🔄 Item already exists - updating: #{existing_item[:description]} → #{description}"
      # Update existing item with new description/modifier (only if provided)
      begin
        updates = {}
        updates[:description] = description unless description.strip.empty?
        updates[:modifier] = modifier unless modifier.strip.empty?
        updates[:priority] = priority if priority > 0 && priority != existing_item[:priority]
        if default_quantity > 0 && default_quantity != existing_item[:default_quantity]
          updates[:default_quantity] =
            default_quantity
        end

        if updates.any?
          @db.update_item(prod_id, updates)
          puts "🔍 DEBUG: Database update successful for add_only - updated: #{updates.keys.join(', ')}"
          puts '✅ Item updated without purchase'
        else
          puts '🔍 DEBUG: No updates needed - all fields same as existing'
          puts '✅ Item processed without changes or purchase'
        end
      rescue StandardError => e
        puts "❌ DEBUG: Database update failed: #{e.message}"
        return nil
      end

      # Return updated item structure
      return {
        prod_id: prod_id,
        url: url,
        description: description,
        modifier: modifier.empty? ? nil : modifier,
        default_quantity: default_quantity,
        priority: priority
      }
    end

    # Create new item in database
    begin
      @db.create_item(
        prod_id: prod_id,
        url: url,
        description: description,
        modifier: modifier.empty? ? nil : modifier,
        default_quantity: default_quantity,
        priority: priority
      )
      puts '🔍 DEBUG: Database insert successful for add_only'
    rescue StandardError => e
      puts "❌ DEBUG: Database insert failed: #{e.message}"
      puts "   Backtrace: #{e.backtrace.first}"
      return nil
    end

    puts "✅ Added new item: #{description}"
    puts "   Modifier: #{modifier.empty? ? '(none)' : modifier}"
    puts "   Priority: #{priority}"
    puts "   Default Qty: #{default_quantity}"
    puts "   Product ID: #{prod_id}"

    # Update Google Sheets
    @sheets_sync.update_item_url(description, url) if @sheets_sync

    # Return the newly created item data
    {
      prod_id: prod_id,
      url: url,
      description: description,
      modifier: modifier.empty? ? nil : modifier,
      default_quantity: default_quantity,
      priority: priority
    }
  end

  def handle_add_and_purchase(parts)
    # Format: description|modifier|priority|default_quantity|url|price|purchase_quantity
    puts "🔍 DEBUG: handle_add_and_purchase called with #{parts.length} parts: #{parts.inspect}"
    return nil if parts.length < 7

    description = parts[0].strip
    modifier = parts[1].strip
    priority = parts[2].strip.to_i
    default_quantity = parts[3].strip.to_i
    url = parts[4].strip
    price_str = parts[5].strip
    purchase_quantity_str = parts[6].strip

    return nil if url.empty?

    # Validate URL format
    unless url.include?('walmart.com') && url.include?('/ip/')
      puts "❌ Invalid URL: #{url}"
      puts "   URL must be a Walmart product page (contain 'walmart.com' and '/ip/')"
      return nil
    end

    # Normalize URL - remove query parameters and fragments
    url = url.split('?').first.split('#').first

    # Extract product ID from URL
    puts "🔍 DEBUG: Extracting product ID from URL: #{url}"
    prod_id = @db.extract_prod_id_from_url(url)
    puts "🔍 DEBUG: Extracted product ID: #{prod_id}"
    return nil unless prod_id

    # Check if item already exists
    existing_item = @db.find_item_by_prod_id(prod_id)
    if existing_item
      # Determine if this is an update or purchase-only operation
      if description.empty? || description.strip.empty?
        puts "💰 Purchase-only mode for existing item: #{existing_item[:description]}"
        item_for_purchase = existing_item
      else
        puts "🔄 Item already exists - updating: #{existing_item[:description]} → #{description}"
        # Update existing item with new description/modifier (only if provided)
        begin
          updates = {}
          updates[:description] = description unless description.strip.empty?
          updates[:modifier] = modifier unless modifier.strip.empty?
          updates[:priority] = priority if priority > 0 && priority != existing_item[:priority]
          if default_quantity > 0 && default_quantity != existing_item[:default_quantity]
            updates[:default_quantity] =
              default_quantity
          end

          if updates.any?
            @db.update_item(prod_id, updates)
            puts "🔍 DEBUG: Database update successful - updated: #{updates.keys.join(', ')}"
          else
            puts '🔍 DEBUG: No updates needed - all fields same as existing'
          end
        rescue StandardError => e
          puts "❌ DEBUG: Database update failed: #{e.message}"
          return nil
        end

        # Use updated info for purchase recording
        item_for_purchase = {
          prod_id: prod_id,
          description: description,
          default_quantity: default_quantity
        }
      end

      # Record purchase if price provided
      if !price_str.empty?
        puts "🔍 DEBUG: Attempting to record purchase - price: #{price_str}, quantity: #{purchase_quantity_str}"
        begin
          price_float = Float(price_str)
          purchase_quantity = Integer(purchase_quantity_str)
          price_cents = (price_float * 100).to_i
          puts "🔍 DEBUG: Parsed values - price_cents: #{price_cents}, quantity: #{purchase_quantity}"
          puts "🔍 DEBUG: Item for purchase: #{item_for_purchase.inspect}"

          record_purchase(item_for_purchase, price_cents: price_cents, quantity: purchase_quantity)
          puts "✅ Recorded purchase: #{purchase_quantity}x #{item_for_purchase[:description]} @ $#{price_str}"

          # Verify the purchase was actually saved
          recent_purchases = @db.get_recent_purchases(days: 1).select { |p| p[:prod_id] == item_for_purchase[:prod_id] }
          if recent_purchases.any?
            puts "🔍 DEBUG: Verified purchase in database: #{recent_purchases.first.inspect}"
          else
            puts '❌ DEBUG: Purchase NOT found in database after recording!'
          end
        rescue ArgumentError => e
          puts "❌ DEBUG: ArgumentError in purchase recording: #{e.message}"
        rescue StandardError => e
          puts "❌ DEBUG: Other error in purchase recording: #{e.message}"
          puts "   Backtrace: #{e.backtrace.first}"
        end
      else
        puts '✅ Item processed without purchase (no price provided)'
      end

      return item_for_purchase
    end

    # For new items, description is required
    if description.empty? || description.strip.empty?
      puts '❌ Cannot create new item without description'
      puts '   (Purchase-only mode only works for existing items)'
      return nil
    end

    # Create new item in database
    begin
      @db.create_item(
        prod_id: prod_id,
        url: url,
        description: description,
        modifier: modifier.empty? ? nil : modifier,
        default_quantity: default_quantity,
        priority: priority
      )
      puts '🔍 DEBUG: Database insert successful for add_and_purchase'
    rescue StandardError => e
      puts "❌ DEBUG: Database insert failed: #{e.message}"
      puts "   Backtrace: #{e.backtrace.first}"
      return nil
    end

    puts "✅ Added new item: #{description}"
    puts "   Modifier: #{modifier.empty? ? '(none)' : modifier}"
    puts "   Priority: #{priority}"
    puts "   Default Qty: #{default_quantity}"
    puts "   Product ID: #{prod_id}"

    # Update Google Sheets
    @sheets_sync.update_item_url(description, url) if @sheets_sync

    # Record purchase if price was provided
    if !price_str.empty?
      begin
        price_float = Float(price_str)
        purchase_quantity = Integer(purchase_quantity_str)
        price_cents = (price_float * 100).to_i

        new_item = {
          prod_id: prod_id,
          description: description,
          default_quantity: default_quantity
        }

        record_purchase(new_item, price_cents: price_cents, quantity: purchase_quantity)
        puts "✅ Recorded purchase: #{purchase_quantity}x #{description} @ $#{price_str}"
      rescue ArgumentError
        puts '⚠️ Invalid price or quantity format, item added but no purchase recorded'
      end
    else
      puts '✅ Item added without purchase (no price provided)'
    end

    # Return the newly created item data (for consistency, though not used in the new flow)
    {
      prod_id: prod_id,
      url: url,
      description: description,
      modifier: modifier.empty? ? nil : modifier,
      default_quantity: default_quantity,
      priority: priority
    }
  end

  def handle_user_interaction(item_name, db_item = nil)
    if db_item
      # Known item
      item_name = db_item[:description]
      url = db_item[:url]
      description = "Priority: #{db_item[:priority]}, Default Qty: #{db_item[:default_quantity]}"

      response = @ahk.show_item_prompt(
        item_name,
        is_known: true,
        url: url,
        description: description,
        item_description: db_item[:description],
        default_quantity: db_item[:default_quantity]
      )
    else
      # New item
      response = @ahk.show_item_prompt(
        item_name,
        is_known: false,
        item_description: item_name,
        default_quantity: 1
      )
    end

    if response&.start_with?('purchase_new|')
      # Parse "purchase_new|price|quantity|url" - new item with URL capture
      parts = response.split('|')
      price_str = parts[1]
      quantity_str = parts[2]
      captured_url = parts[3]

      begin
        price_float = Float(price_str)
        quantity_int = Integer(quantity_str)
        price_cents = (price_float * 100).to_i

        # Create new database item with captured URL
        if captured_url && captured_url.include?('walmart.com') && captured_url.include?('/ip/')
          prod_id = @db.extract_prod_id_from_url(captured_url)

          if prod_id
            # Create the new item
            @db.create_item(
              prod_id: prod_id,
              url: captured_url,
              description: item_name,
              modifier: nil,
              default_quantity: 1,
              priority: 5
            )

            # Record the purchase
            new_item = { prod_id: prod_id, description: item_name }
            record_purchase(new_item, price_cents: price_cents, quantity: quantity_int)

            puts "✅ Saved new item: #{item_name} and recorded purchase"
          else
            puts "❌ Could not extract product ID from URL: #{captured_url}"
          end
        else
          puts "❌ Invalid Walmart product URL captured: #{captured_url}"
        end
      rescue ArgumentError
        puts '❌ Invalid price or quantity format'
      end

    elsif response&.start_with?('purchase|')
      # Parse "purchase|price|quantity" - known item
      parts = response.split('|')
      price_str = parts[1]
      quantity_str = parts[2]

      begin
        price_float = Float(price_str)
        quantity_int = Integer(quantity_str)
        price_cents = (price_float * 100).to_i

        # Record the purchase
        if db_item && db_item[:prod_id]
          record_purchase(db_item, price_cents: price_cents, quantity: quantity_int)
        else
          puts "⚠️ Cannot record purchase for unknown item: #{item_name}"
        end
      rescue ArgumentError
        puts '❌ Invalid price or quantity format'
      end

    elsif response&.start_with?('save_url_only|')
      # Parse "save_url_only|url" - new item, no purchase, but save URL
      parts = response.split('|')
      captured_url = parts[1]

      if captured_url && captured_url.include?('walmart.com') && captured_url.include?('/ip/')
        prod_id = @db.extract_prod_id_from_url(captured_url)

        if prod_id
          # Create the new item without recording a purchase
          @db.create_item(
            prod_id: prod_id,
            url: captured_url,
            description: item_name,
            modifier: nil,
            default_quantity: 1,
            priority: 5
          )

          puts "✅ Saved new item URL: #{item_name} (no purchase recorded)"
        else
          puts "❌ Could not extract product ID from URL: #{captured_url}"
        end
      else
        puts "❌ Invalid Walmart product URL captured: #{captured_url}"
      end

    else
      # Just continue - no purchase to record
    end
  end

  def record_manual_price(item)
    price_float = @ahk.get_price_input

    return nil unless price_float

    price_cents = (price_float * 100).to_i

    # If this is a known item, record the purchase
    record_purchase(item, price_cents: price_cents) if item[:prod_id]

    price_cents
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
        @sheets_sync.update_item_url(item_name, current_url) if @sheets_sync

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

    # Mark item as completed in shopping list data
    mark_shopping_item_completed(item[:description])

    if price_cents
      price_display = "$#{format('%.2f', price_cents / 100.0)}"
      puts "📊 Recorded purchase: #{quantity}x #{item[:description]} @ #{price_display}".colorize(:blue)
    else
      puts "📊 Recorded purchase: #{quantity}x #{item[:description]} (no price)".colorize(:blue)
    end
  end

  def mark_shopping_item_completed(item_description)
    return unless @shopping_list_data

    # Find and mark the shopping list item as completed
    @shopping_list_data.each do |shopping_item|
      next unless shopping_item[:item].downcase == item_description.downcase

      shopping_item[:purchased] = '✓'
      puts "✅ Marked shopping item completed: #{item_description}"
      break
    end
  end

  def wait_for_ahk_shutdown
    puts '🔍 DEBUG: Starting wait_for_ahk_shutdown loop...'

    # Check for any existing response file and process it
    if File.exist?(@ahk.class::RESPONSE_FILE)
      puts '🔍 DEBUG: Found existing response file, processing...'
      response = @ahk.read_response
      puts "🔍 DEBUG: Read response: '#{response}'"

      if %w[quit shutdown].include?(response)
        puts '✅ User requested exit'
        return # Exit the function, which will end wait_for_ahk_shutdown
      elsif response == 'session_reset'
        puts '🔍 DEBUG: Session complete confirmation received'
        puts '⏳ Waiting for user to exit (Ctrl+Shift+Q) or add items (Ctrl+Shift+A)...'
      elsif response && !response.empty? && response != 'cancelled'
        puts '📦 Processing existing item response...'
        handle_add_new_item(response)
      end
    end

    loop do
      sleep(0.5) # Check twice per second

      # Check if AHK wrote a response (happens for session_reset, add item, or quit)
      next unless File.exist?(@ahk.class::RESPONSE_FILE)

      puts '🔍 DEBUG: Found response file, reading...'
      response = @ahk.read_response
      puts "🔍 DEBUG: Read response: '#{response}'"

      if %w[quit shutdown].include?(response)
        puts '✅ User requested exit'
        break
      elsif response == 'session_reset'
        puts '🔍 DEBUG: Session complete confirmation received'
        puts '⏳ Waiting for user to exit (Ctrl+Shift+Q) or add items (Ctrl+Shift+A)...'
        # Continue monitoring
      elsif response && !response.empty? && response != 'cancelled'
        puts '📦 Processing newly added item...'
        handle_add_new_item(response)
      else
        puts '🔍 DEBUG: Response was empty, cancelled, or nil'
      end
    end
  end
end

if __FILE__ == $0
  assistant = WalmartGroceryAssistant.new
  assistant.start
end
