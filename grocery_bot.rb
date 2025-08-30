require 'uri'
require 'csv'
require 'json'
require 'colorize'
require 'dotenv/load'
require 'logger'
require_relative 'lib/google_sheets_integration'
require 'debug' # Add the debugger
require_relative 'lib/database'
require_relative 'lib/ahk_bridge'

class WalmartGroceryAssistant
  def initialize
    @ahk = AhkBridge.new
    @db = Database.instance
    @sheets_sync = GoogleSheetsIntegration.create_sync_client
    @sync_completed = false # Flag to prevent double sync

    # Setup centralized logging
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::DEBUG
    @logger.formatter = proc do |severity, datetime, progname, msg|
      case severity
      when 'DEBUG'
        "🔍 DEBUG: #{msg}\n"
      when 'INFO'
        "ℹ️ #{msg}\n"
      when 'WARN'
        "⚠️ #{msg}\n".colorize(:yellow)
      when 'ERROR'
        "❌ #{msg}\n".colorize(:red)
      else
        "#{msg}\n"
      end
    end

    # Setup cleanup handlers for unexpected exits
    setup_cleanup_handlers
  end

  # Helper method to ensure response is in expected format
  def parse_response(response)
    # All responses should now be JSON hashes from AhkBridge.read_response
    if response.is_a?(Hash)
      response
    else
      # Fallback for any unexpected format
      puts "⚠️ Unexpected response format: #{response.inspect}"
      {
        type: 'error',
        value: response.to_s,
        error: 'unexpected_format'
      }
    end
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

    end

    # Shopping list processing complete - signal session complete to show persistent tooltip
    if grocery_items.empty?
      puts '✅ No items processed.'
    else
      puts '✅ Shopping list processing complete!'
    end

    # Signal AHK to show completion status and persistent tooltip (don't read response)
    @ahk.send_command('SESSION_COMPLETE')

    # Wait for user to add items manually or quit
    puts '✅ Shopping list complete. Ready for manual actions (Ctrl+Shift+A) or quit (Ctrl+Shift+Q).'
    @logger.debug('About to call post_list_actions')
    post_list_actions
    @logger.debug('Returned from post_list_actions')

    # Sync database items back to Google Sheets when user is done
    if @sync_completed
      puts '✅ Sheets already synced - skipping duplicate sync'
    else
      puts '💾 Syncing database items to Google Sheets...'
      sync_database_to_sheets
      @sync_completed = true
    end
    
    # Always create backup at end of session (regardless of changes)
    puts '💾 Creating database backup...'
    @db.create_rotating_backup
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
      puts "\n🧹 Cleaning up and syncing to Google Sheets..."

      # Perform final Google Sheets sync if we have shopping list data and haven't synced yet
      if @shopping_list_data && !@shopping_list_data.empty? && @sheets_sync && !@sync_completed
        puts '📊 Performing sheet sync before exit...'
        begin
          puts "🔍 DEBUG: About to sync @shopping_list_data (#{@shopping_list_data.length} items)"
          puts "🔍 DEBUG: First few items: #{@shopping_list_data.first(2).inspect}"
          result = @sheets_sync.sync_from_database(@db, @shopping_list_data)
          puts "✅ Sync complete: #{result[:products]} products, #{result[:shopping_items]} shopping items"
          @sync_completed = true
          
          # Create rotating database backup after final sync
          puts '💾 Creating database backup...'
          @db.create_rotating_backup
        rescue StandardError => e
          puts "❌ Final sheet sync failed: #{e.message}"
        end
      else
        puts 'ℹ️ Sheet sync skipped (no data or already completed)'
      end

      # Signal AHK to terminate gracefully
      @ahk.terminate_ahk if @ahk

      puts '✅ Cleanup complete'
    rescue StandardError => e
      puts "⚠️ Cleanup error (non-critical): #{e.message}"
    end
  end

  def setup_ahk
    # Clean up any stale communication files
    puts '🧹 Cleaning up communication files...'
    cleanup_existing_ahk

    # Start AutoHotkey script
    puts '🚀 Starting AutoHotkey script...'
    start_ahk_script
    sleep(1) # Give it time to start

    # Wait indefinitely for READY message via JSON response
    puts '⏳ Waiting for AutoHotkey to be ready...'
    loop do
      sleep(1)
      # Check for response file
      next unless File.exist?(@ahk.class::RESPONSE_FILE)

      response = @ahk.read_response
      next if response.nil? || response.empty?

      if response[:type] == 'status' && response[:value] == 'ready'
        puts '✅ AutoHotkey is ready!'
        break
      end
    end
  end

  def cleanup_existing_ahk
    # Clean up communication files
    [@ahk.class::COMMAND_FILE, @ahk.class::RESPONSE_FILE].each do |file|
      File.delete(file) if File.exist?(file)
    end
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

  def sync_database_from_sheets
    return unless @sheets_sync

    result = @sheets_sync.sync_to_database(@db)
    # Sync happens silently in background
  end

  def load_items_to_order
    if @sheets_sync
      sheet_data = @sheets_sync.get_grocery_list

      # Get shopping list items and remove duplicates (case-insensitive)
      shopping_items = sheet_data[:shopping_list]
      unique_shopping_items = []
      seen_items = Set.new

      shopping_items.each do |item|
        normalized_name = item[:item].strip.downcase
        if seen_items.include?(normalized_name)
          puts "⚠️  Skipping duplicate item: #{item[:item]}"
        else
          unique_shopping_items << item
          seen_items << normalized_name
        end
      end

      # Store deduplicated shopping list for later rewriting
      puts "🔍 DEBUG: Setting @shopping_list_data to unique_shopping_items (#{unique_shopping_items.length} items)"
      @shopping_list_data = unique_shopping_items

      # Process only items with quantity != 0 AND empty purchased field
      items_to_order = unique_shopping_items.select do |item|
        item[:quantity] != 0 && 
        (item[:purchased].nil? || item[:purchased].strip.empty?)
      end

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

      # Check if item exists in database
      db_item = find_item_in_database(item_name)

      if db_item && db_item != :search_new_item
        puts "   ✅ Found in database: #{db_item[:prod_id]} - #{db_item[:description]}"
        puts '   🌐💬 Navigating and showing dialog...'
        result = navigate_and_show_dialog_for_known_item(item_name, db_item)
        # NOTE: If user quits, handle_user_interaction will call exit(0) directly

        # Handle "Search Again" request - treat like multi-choice "search for new item"
        if result == :search_new_item
          puts '   🔍 User requested search for alternatives via "Search Again" button'
          search_for_new_item(item_name)
          puts '   📍 Navigate to the product you want, then press Ctrl+Shift+A to add/purchase it'
          wait_for_item_completion(item_name)
        end
      elsif db_item == :search_new_item
        puts '   🔍 User selected "Search for new item" - searching Walmart...'
        search_for_new_item(item_name)
        puts '   📍 Navigate to the product you want, then press Ctrl+Shift+A to add/purchase it'
        wait_for_item_completion(item_name)
      else
        puts '   🔍 New item - searching Walmart...'
        search_for_new_item(item_name)
        puts '   📍 Navigate to the product you want, then press Ctrl+Shift+A to add/purchase it'
        wait_for_item_completion(item_name)
      end
    end
  end

  def navigate_to_known_item(item)
    @ahk.open_url(item[:url])
    # No sleep - let dialog show immediately while page loads
  end

  def search_for_new_item(item_name)
    response = @ahk.search_walmart(item_name)
    puts "🔍 Search completed with response: #{response.inspect}"
    
    # Handle lookup_request response if user immediately lands on a product page
    if response[:type] == 'lookup_request'
      puts "🔍 Search landed on product page - processing lookup request"
      url = response[:url]
      if url
        @logger.debug("Processing immediate lookup for URL: #{url}")
        @ahk.lookup_item_by_url(url, @db)
      end
    end
  end

  def wait_for_item_completion(item_name)
    # Wait for user to press Ctrl+Shift+A to complete the item
    puts '   ⏳ Waiting for item completion via Ctrl+Shift+A...'
    @logger.debug("Entering wait_for_item_completion for item: #{item_name}")

    loop do
      sleep(1)
      @logger.debug("Checking for response file...")

      # Check for response file instead of status
      unless File.exist?(@ahk.class::RESPONSE_FILE)
        @logger.debug("Response file not found.")
        next
      end

      @logger.debug("Response file found!")
      response = @ahk.read_response
      @logger.debug("Response from AHK: #{response.inspect}")
      next if response.nil? || response.empty?

      case response[:type]
      when 'status'
        case response[:value]
        when 'quit', 'shutdown'
          puts '   🛑 User requested shutdown during wait'
          @logger.debug("Shutdown requested, breaking loop.")
          break
        else
          @logger.debug("Ignoring status response: #{response.inspect}")
        end
      when 'lookup_request'
        @logger.debug("Lookup request received during wait, processing...")
        url = response[:url]
        if url
          @logger.debug("Lookup URL: #{url}")
          @ahk.lookup_item_by_url(url, @db)
        else
          @logger.warn('Lookup request received without a URL.')
        end
        # Continue waiting for the actual completion response
      when 'add_and_purchase'
        @logger.debug("add_and_purchase response received, handling completion.")
        handle_shopping_list_completion(item_name, response)
        puts "   ✅ Item '#{item_name}' completed"
        break
      when 'status'
        if response[:value] == 'skipped'
          @logger.debug("Skip response received, handling completion.")
          handle_shopping_list_completion(item_name, response)
          puts "   ✅ Item '#{item_name}' completed"
          break
        end
      else
        # Handle other response types that might complete the item
        if response[:type] != 'status'
          @logger.debug("Other response received, handling completion.")
          handle_shopping_list_completion(item_name, response)
          puts "   ✅ Item '#{item_name}' completed"
          break
        else
          @logger.debug("Ignoring status response: #{response.inspect}")
        end
      end
    end
    @logger.debug("Exiting wait_for_item_completion for item: #{item_name}")
  end

  def handle_shopping_list_completion(original_item_name, response_data)
    # Handle completion of a specific shopping list item via Ctrl+Shift+A
    puts "🔍 DEBUG: Completing shopping list item '#{original_item_name}' with response: #{response_data}"

    parsed_response = parse_response(response_data)
    puts "🔍 DEBUG: Parsed response type: '#{parsed_response[:type]}', value: '#{parsed_response[:value]}'"

    # Check for skip first, before processing purchase data
    if parsed_response[:type] == 'status' && parsed_response[:value] == 'skipped'
      puts '🔍 DEBUG: SKIP DETECTED - handling skip immediately'
      puts "🔍 DEBUG: ❌ SET AT LINE 548 - handle_shopping_list_completion skip detection"
      # User clicked "Skip Item" - mark with red X
      update_shopping_list_item(original_item_name,
                                purchased: '❌', # Red X for skipped items
                                itemno: '',
                                price: 0.0)
      puts "⏭️ Shopping list item '#{original_item_name}' marked as skipped"
      return
    end

    case parsed_response[:type]
    when 'add_and_purchase'
      puts '🔍 DEBUG: Processing shopping list completion with add_and_purchase'

      # Extract data from response
      description = parsed_response[:description]
      modifier = parsed_response[:modifier]
      priority = parsed_response[:priority] || 1
      default_quantity = parsed_response[:default_quantity] || 1
      # Keep subscribable as integer (0/1) for consistency
      subscribable = (parsed_response[:subscribable] || 0).to_i
      url = parsed_response[:url]
      price = parsed_response[:price]
      purchase_quantity = parsed_response[:purchase_quantity] || 1

      # Add item to database if URL is valid (using existing proven pattern)
      db_item = nil
      if url && url.include?('walmart.com') && url.include?('/ip/')
        prod_id = @db.extract_prod_id_from_url(url)
        if prod_id
          # Check if item already exists
          existing_item = @db.find_item_by_prod_id(prod_id)
          if existing_item
            puts "🔄 Item already exists - updating: #{existing_item[:description]} → #{description}"
            # Update existing item
            updates = {}
            updates[:description] = description unless description.empty?
            updates[:modifier] = modifier unless modifier.empty?
            updates[:priority] = priority if priority > 0 && priority != existing_item[:priority]
            if default_quantity > 0 && default_quantity != existing_item[:default_quantity]
              updates[:default_quantity] =
                default_quantity
            end
            updates[:subscribable] = subscribable if subscribable != (existing_item[:subscribable] || 0)

            if updates.any?
              @db.update_item(prod_id, updates)
              puts "✅ Updated existing item: #{updates.keys.join(', ')}"
            end

            db_item = @db.find_item_by_prod_id(prod_id)
          else
            puts "✅ Creating new item: #{prod_id} - #{description}"
            # Create new item
            @db.create_item(
              prod_id: prod_id,
              url: url,
              description: description,
              modifier: modifier.empty? ? nil : modifier,
              default_quantity: default_quantity,
              priority: priority,
              subscribable: subscribable
            )
            db_item = @db.find_item_by_prod_id(prod_id)
          end
        end
      end

      # Record purchase if price provided
      if price && price.to_f > 0 && db_item
        price_cents = (price.to_f * 100).to_i
        @db.record_purchase(
          prod_id: db_item[:prod_id],
          quantity: purchase_quantity,
          price_cents: price_cents
        )
        puts "✅ Recorded purchase: #{purchase_quantity}x #{description} @ $#{price}"
      end

      # Most importantly: Update the ORIGINAL shopping list item as purchased
      total_price = price.to_f * purchase_quantity.to_i
      update_shopping_list_item(original_item_name,
                                purchased: 'purchased',
                                purchased_quantity: purchase_quantity.to_i,
                                itemno: db_item ? db_item[:prod_id] : '',
                                price: total_price)
      puts "✅ Updated shopping list item '#{original_item_name}' as purchased"

    else
      puts "⚠️ Unexpected response type for shopping list completion: #{parsed_response[:type]}"
    end
  end

  def handle_add_new_item(response_data)
    @logger.debug("Processing add item response: #{response_data.inspect}")

    # The response should already be a parsed hash from our new loop
    parsed_response = parse_response(response_data)

    # The main loop now only passes 'add_and_purchase' or unhandled legacy types here.
    # We are simplifying to only handle the modern JSON format.
    if parsed_response[:type]&.to_s == 'add_and_purchase'
      @logger.debug('Calling handle_add_and_purchase_json')
      handle_add_and_purchase_json(parsed_response)
    else
      @logger.error("handle_add_new_item received an unexpected type: '#{parsed_response[:type]}'. This may indicate a legacy message from AHK.")
      nil
    end
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

  def handle_add_and_purchase_json(parsed_response)
    puts "🔍 DEBUG: handle_add_and_purchase_json called with: #{parsed_response.inspect}"

    description = parsed_response[:description]&.strip || ''
    modifier = parsed_response[:modifier]&.strip || ''
    priority = parsed_response[:priority] || 1
    default_quantity = parsed_response[:default_quantity] || 1
    # Keep subscribable as integer (0/1) for consistency
    subscribable = (parsed_response[:subscribable] || 0).to_i
    url = parsed_response[:url]&.strip || ''
    price = parsed_response[:price]
    purchase_quantity = parsed_response[:purchase_quantity] || 1

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
      if description.empty?
        puts "💰 Purchase-only mode for existing item: #{existing_item[:description]}"
        item_for_purchase = existing_item
      else
        puts "🔄 Item already exists - updating: #{existing_item[:description]} → #{description}"
        # Update existing item
        begin
          updates = {}
          updates[:description] = description unless description.empty?
          updates[:modifier] = modifier unless modifier.empty?
          updates[:priority] = priority if priority > 0 && priority != existing_item[:priority]
          if default_quantity > 0 && default_quantity != existing_item[:default_quantity]
            updates[:default_quantity] =
              default_quantity
          end
          updates[:subscribable] = subscribable if subscribable != (existing_item[:subscribable] || 0)

          if updates.any?
            @db.update_item(prod_id, updates)
            puts "🔍 DEBUG: Database update successful for JSON format - updated: #{updates.keys.join(', ')}"
          end

          item_for_purchase = @db.find_item_by_prod_id(prod_id)
        rescue StandardError => e
          puts "❌ DEBUG: Database update failed: #{e.message}"
          return nil
        end
      end

      # Record purchase if price is provided
      if price && price.to_f > 0
        begin
          price_cents = (price.to_f * 100).to_i
          record_purchase(item_for_purchase, price_cents: price_cents, quantity: purchase_quantity)
          puts "✅ Recorded purchase: #{purchase_quantity}x #{item_for_purchase[:description]} @ $#{price}"

        rescue StandardError => e
          puts "❌ DEBUG: Purchase recording failed: #{e.message}"
        end
      else
        puts '✅ Item processed without purchase (no price provided)'
        # Do NOT add to shopping list data - manual items without purchase shouldn't appear on list
      end

      return item_for_purchase
    end

    # For new items, description is required
    if description.empty?
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
        priority: priority,
        subscribable: subscribable
      )
      puts "✅ New item added: #{description}"

      # Record purchase if price is provided
      if price && price.to_f > 0
        price_cents = (price.to_f * 100).to_i

        new_item = {
          prod_id: prod_id,
          description: description,
          default_quantity: default_quantity
        }

        record_purchase(new_item, price_cents: price_cents, quantity: purchase_quantity)
        puts "✅ Recorded purchase: #{purchase_quantity}x #{description} @ $#{price}"

      else
        puts '✅ Item added without purchase (no price provided)'
        # Do NOT add to shopping list data - manual items without purchase shouldn't appear on list
      end

      {
        prod_id: prod_id,
        url: url,
        description: description,
        modifier: modifier.empty? ? nil : modifier,
        default_quantity: default_quantity,
        priority: priority
      }
    rescue StandardError => e
      puts "❌ Failed to create new item: #{e.message}"
      nil
    end
  end

  def navigate_and_show_dialog_for_known_item(item_name, db_item)
    # Use combined command that navigates and shows dialog in one step
    display_name = db_item[:description]
    url = db_item[:url]
    description = "Priority: #{db_item[:priority]}, Default Qty: #{db_item[:default_quantity]}"

    response = @ahk.navigate_and_show_dialog(
      url,
      display_name,
      is_known: true,
      description: description,
      item_description: display_name,
      default_quantity: db_item[:default_quantity] || 1
    )

    # Process the response the same way as handle_user_interaction
    parsed_response = parse_response(response)
    
    # Check for quit signal first
    if parsed_response[:type] == 'status' && %w[quit shutdown].include?(parsed_response[:value])
      puts '✅ User requested exit - terminating Ruby'
      exit(0)
    end

    # Process purchase response
    case parsed_response[:type]
    when 'purchase'
      # Mark as purchased and update shopping list with itemid and total price
      total_price = parsed_response[:price].to_f * parsed_response[:quantity].to_i
      update_shopping_list_item(item_name,
                                purchased: 'purchased',
                                purchased_quantity: parsed_response[:quantity].to_i,
                                itemno: db_item[:prod_id],
                                price: total_price)

      # Record purchase in database  
      if db_item[:prod_id]
        # Update subscribable field if provided and different
        unless parsed_response[:subscribable].nil?
          subscribable_int = (parsed_response[:subscribable] || 0).to_i
          if subscribable_int != (db_item[:subscribable] || 0)
            @db.update_item(db_item[:prod_id], { subscribable: subscribable_int })
            puts "📦 Updated subscribable status: #{db_item[:description]} → #{subscribable_int == 1 ? 'Yes' : 'No'}"
          end
        end

        price_cents = (parsed_response[:price] * 100).to_i
        @db.record_purchase(
          prod_id: db_item[:prod_id],
          quantity: parsed_response[:quantity],
          price_cents: price_cents
        )
        puts "✅ Recorded purchase in database: #{parsed_response[:quantity]}x #{db_item[:description]} @ $#{parsed_response[:price]}"
      end
      
    when 'choice'
      # Handle "Search Again" button (choice 999) like "search for new item" in multi-choice
      if parsed_response[:value] == 999
        puts "🔍 User requested search for alternatives: #{item_name}"
        return :search_new_item
      end
      
    when 'status'
      # Handle status responses like 'skipped' from skip button
      if parsed_response[:value] == 'skipped'
        puts "🔍 DEBUG: ❌ SET AT LINE 1025 - navigate_and_show_dialog_for_known_item skip handling"
        # User clicked "Skip Item" - mark with red X
        update_shopping_list_item(item_name,
                                  purchased: '❌',
                                  itemno: db_item[:prod_id],
                                  price: 0.0)
        puts "⏭️ Item '#{item_name}' marked as skipped"
      end
    end
    
    return parsed_response
  end

  def handle_user_interaction(item_name, db_item = nil)
    # Preserve original shopping list item name for shopping list updates
    original_shopping_item_name = item_name

    if db_item
      # Known item - use db_item description for display, but keep original name for shopping list
      display_name = db_item[:description]
      url = db_item[:url]
      description = "Priority: #{db_item[:priority]}, Default Qty: #{db_item[:default_quantity]}"

      response = @ahk.show_item_prompt(
        display_name,
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

    parsed_response = parse_response(response)

    # Check for quit signal first
    if parsed_response[:type] == 'status' && %w[quit shutdown].include?(parsed_response[:value])
      puts '✅ User requested exit - terminating Ruby'
      exit(0)
    end

    # Update shopping list item immediately with purchase info
    case parsed_response[:type]
    when 'purchase_new'
      # Mark as purchased and update shopping list with itemid and total price
      total_price = parsed_response[:price].to_f * parsed_response[:quantity].to_i
      update_shopping_list_item(original_shopping_item_name,
                                purchased: 'purchased',
                                purchased_quantity: parsed_response[:quantity].to_i,
                                itemno: db_item ? db_item[:prod_id] : '',
                                price: total_price)
    when 'purchase'
      # Mark as purchased and update shopping list with itemid and total price
      total_price = parsed_response[:price].to_f * parsed_response[:quantity].to_i
      update_shopping_list_item(original_shopping_item_name,
                                purchased: 'purchased',
                                purchased_quantity: parsed_response[:quantity].to_i,
                                itemno: db_item ? db_item[:prod_id] : '',
                                price: total_price)

      # Still record in database
      if db_item && db_item[:prod_id]
        # Update subscribable field if provided and different
        unless parsed_response[:subscribable].nil?
          subscribable_int = (parsed_response[:subscribable] || 0).to_i
          if subscribable_int != (db_item[:subscribable] || 0)
            @db.update_item(db_item[:prod_id], { subscribable: subscribable_int })
            puts "📦 Updated subscribable status: #{db_item[:description]} → #{subscribable_int == 1 ? 'Yes' : 'No'}"
          end
        end

        price_cents = (parsed_response[:price] * 100).to_i
        @db.record_purchase(
          prod_id: db_item[:prod_id],
          quantity: parsed_response[:quantity],
          price_cents: price_cents
        )
        puts "✅ Recorded purchase in database: #{parsed_response[:quantity]}x #{db_item[:description]} @ $#{parsed_response[:price]}"
      else
        puts "⚠️ Cannot record purchase for unknown item: #{original_shopping_item_name}"
      end

    when 'save_url_only'
      # Save URL without purchase
      captured_url = parsed_response[:url]

      if captured_url && captured_url.include?('walmart.com') && captured_url.include?('/ip/')
        prod_id = @db.extract_prod_id_from_url(captured_url)

        if prod_id
          # Create the new item without recording a purchase
          subscribable = (parsed_response[:subscribable] || 0).to_i
          @db.create_item(
            prod_id: prod_id,
            url: captured_url,
            description: original_shopping_item_name,
            modifier: nil,
            default_quantity: 1,
            priority: 5,
            subscribable: subscribable
          )

          puts "✅ Saved new item URL: #{original_shopping_item_name} (no purchase recorded)"
        else
          puts "❌ Could not extract product ID from URL: #{captured_url}"
        end
      else
        puts "❌ Invalid Walmart product URL captured: #{captured_url}"
      end

    when 'choice'
      # Handle "Search Again" button (choice 999) like "search for new item" in multi-choice
      if parsed_response[:value] == 999
        puts "🔍 User requested search for alternatives: #{original_shopping_item_name}"

        # Trigger the same search flow as multi-choice "search for new item"
        # This will be handled by returning :search_new_item and going back to main process loop
        :search_new_item
      else
        # Handle other choice responses if any
        puts "⚠️ Unexpected choice response: #{parsed_response[:value]}"
      end

    when 'status'
      # Handle status responses like 'skipped' from skip button
      if parsed_response[:value] == 'skipped'
        puts "🔍 DEBUG: ❌ SET AT LINE 1158 - handle_user_interaction skip handling"
        # User clicked "Skip Item" - mark with red X
        update_shopping_list_item(original_shopping_item_name,
                                  purchased: '❌', # Red X for skipped items
                                  itemno: db_item ? db_item[:prod_id] : '',
                                  price: 0.0)
        puts "⏭️ Item '#{original_shopping_item_name}' marked as skipped"
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

  def record_purchase(item, price_cents: nil, quantity: nil, shopping_list_name: nil)
    quantity ||= item[:default_quantity]

    @db.record_purchase(
      prod_id: item[:prod_id],
      quantity: quantity,
      price_cents: price_cents
    )

    # Update shopping list with itemid, quantity, and price
    completion_name = shopping_list_name || item[:description]
    price_paid = price_cents ? (price_cents / 100.0) : nil

    total_price = price_paid ? price_paid * quantity : 0.0
    update_shopping_list_item(completion_name,
                              purchased: '✓',
                              purchased_quantity: quantity,
                              itemno: item[:prod_id],
                              price: total_price)

    if price_cents
      price_display = "$#{format('%.2f', price_cents / 100.0)}"
      puts "📊 Recorded purchase: #{quantity}x #{item[:description]} @ #{price_display}".colorize(:blue)
    else
      puts "📊 Recorded purchase: #{quantity}x #{item[:description]} (no price)".colorize(:blue)
    end
  end

  def update_shopping_list_item(item_name, updates = {})
    puts "🔍 DEBUG: update_shopping_list_item called for '#{item_name}' with updates: #{updates.inspect}"
    puts "🔍 DEBUG: Caller: #{caller[0]}"

    # Initialize @shopping_list_data if it doesn't exist
    @shopping_list_data ||= []

    # Find existing shopping list item
    shopping_item = @shopping_list_data.find { |item| item[:item].downcase == item_name.downcase }

    if shopping_item
      # Update existing item
      updates.each do |key, value|
        shopping_item[key] = value
      end
      puts "✅ Updated shopping item: #{item_name} with #{updates.keys.join(', ')}"
      puts "🔍 DEBUG: After update, shopping_item[:purchased] = '#{shopping_item[:purchased]}'"
    else
      # Create new blank shopping list item, then update it
      new_shopping_item = {
        purchased: '',
        item: item_name,
        modifier: '',
        priority: 1,
        quantity: 1,
        last_purchased: '',
        itemno: '',
        url: '',
        price: '',
        purchased_quantity: 0
      }

      # Apply updates to the new item
      updates.each do |key, value|
        new_shopping_item[key] = value
      end

      @shopping_list_data << new_shopping_item
      puts "✅ Created new shopping item: #{item_name} with #{updates.keys.join(', ')}"
    end
  end

  def post_list_actions
    @logger.debug('Starting post-list action loop...')
    @logger.debug("Monitoring response file: #{File.absolute_path(@ahk.class::RESPONSE_FILE)}")

    loop do
      # Wait for a response file to appear, checking every 200ms
      sleep(0.2) until File.exist?(@ahk.class::RESPONSE_FILE)

      # File exists, read and delete it
      response = @ahk.read_response
      next if response.nil? || (response.is_a?(Hash) && response.empty?) || (response.is_a?(String) && response.empty?)

      # Process the response
      parsed_response = parse_response(response)
      @logger.debug("Processing response: #{parsed_response.inspect}")

      # Use a case statement for clarity and to prevent fall-through errors
      case parsed_response[:type]&.to_s
      when 'status'
        case parsed_response[:value]
        when 'quit', 'shutdown'
          puts '✅ User requested exit'
          return # Exit the method
        when 'continue'
          @logger.info('End of shopping list message received. Waiting for user actions.')
        when 'skipped'
          puts '⏭️ Manual item addition skipped'
          # Do nothing - don't add skipped manual items to shopping list
        end
      when 'lookup_request'
        @logger.info('Processing item lookup request...')
        url = parsed_response[:url]
        if url
          @logger.debug("Lookup URL: #{url}")
          @ahk.lookup_item_by_url(url, @db)
        else
          @logger.warn('Lookup request received without a URL.')
        end
      when 'add_and_purchase'
        @logger.info("Processing 'add_and_purchase' request...")
        handle_add_new_item(response)
      else
        @logger.warn("Unrecognized response type '#{parsed_response[:type]}', attempting to process with legacy handler.")
        handle_add_new_item(response)
      end
    end
  end
end

if __FILE__ == $0
  assistant = WalmartGroceryAssistant.new
  assistant.start
end
