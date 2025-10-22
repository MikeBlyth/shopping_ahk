require 'timeout'
require 'json'

class AhkBridge
  COMMAND_FILE = 'ahk_command.txt'
  STATUS_FILE = 'ahk_status.txt'
  RESPONSE_FILE = 'ahk_response.txt'

  def initialize
    clear_files
  end

  def send_command(command, timeout: nil, params: nil)
    if params
      # Send as JSON command
      json_command = {
        action: command,
        param: params
      }.to_json
      write_command(json_command)
    else
      # Send as legacy pipe-delimited command
      write_command(command)
    end
    # No longer wait for completion - let callers use read_response() when needed
  end

  def open_url(url)
    puts "🌐 Opening URL via AHK: #{url}".colorize(:blue)
    send_command("OPEN_URL|#{url}", timeout: 30)  # 30 second timeout for navigation
  end

  def search_walmart(search_term)
    puts "🔍 Searching Walmart via AHK: #{search_term}".colorize(:blue)
    send_command("SEARCH|#{search_term}", timeout: 30)  # 30 second timeout for search
    response = read_response
    puts "🔍 SEARCH response: '#{response}'".colorize(:blue)
    response
  end

  def get_current_url
    send_command('GET_URL')
    read_response
  end

  def show_add_item_dialog(suggested_name = '')
    send_command("ADD_ITEM_DIALOG|#{suggested_name}")
    read_response
  end

  def show_item_prompt(item_name, is_known: false, url: '', description: '', item_description: '', default_quantity: 1)
    params = "#{item_name}|#{is_known}|#{url}|#{description}|#{item_description}|#{default_quantity}"
    puts '🎭 About to send SHOW_ITEM_PROMPT command...'.colorize(:yellow)

    begin
      send_command("SHOW_ITEM_PROMPT|#{params}")
      response = read_response
      puts "🎭 SHOW_ITEM_PROMPT response: '#{response}'".colorize(:yellow)
      response
    rescue StandardError => e
      puts "🎭 SHOW_ITEM_PROMPT failed: #{e.message}".colorize(:red)
      ''
    end
  end

  def navigate_and_show_dialog(url, item_name, is_known: false, description: '', item_description: '', default_quantity: 1)
    params = "#{url}|#{item_name}|#{is_known}|#{description}|#{item_description}|#{default_quantity}"
    puts "🌐🎭 About to send NAVIGATE_AND_SHOW_DIALOG command for #{item_name}...".colorize(:blue)

    begin
      send_command("NAVIGATE_AND_SHOW_DIALOG|#{params}")
      response = read_response
      puts "🌐🎭 NAVIGATE_AND_SHOW_DIALOG response: '#{response}'".colorize(:blue)
      response
    rescue StandardError => e
      puts "🌐🎭 NAVIGATE_AND_SHOW_DIALOG failed: #{e.message}".colorize(:red)
      ''
    end
  end

  def show_message(message)
    send_command("SHOW_MESSAGE|#{message}")  # No timeout - can wait indefinitely
    read_response
  end

  def get_price_input
    send_command('GET_PRICE_INPUT')
    response = read_response

    # All responses should now be JSON format
    case response[:type]
    when 'price'
      response[:value]
    when 'status'
      response[:value] == 'cancelled' ? nil : nil
    else
      nil
    end
  end

  def show_multiple_choice(title:, options:, allow_skip: true)
    # Format: SHOW_MULTIPLE_CHOICE|title|allow_skip|option1|option2|...
    params = [title, allow_skip.to_s] + options
    send_command("SHOW_MULTIPLE_CHOICE|#{params.join('|')}")

    response = read_response
    # All responses should now be JSON format
    case response[:type]
    when 'choice'
      response[:value]
    when 'status'
      %w[cancelled skipped].include?(response[:value]) ? nil : nil
    else
      nil
    end
  end

  def lookup_item_by_url(url, database)
    puts "🔍 Looking up item by URL: #{url}".colorize(:blue)
    
    # Extract product ID and find item
    prod_id = database.extract_prod_id_from_url(url)
    
    if prod_id && (item = database.find_item_by_prod_id(prod_id))
      # Return existing item data
      response = {
        type: 'lookup_result',
        found: true,
        description: item[:description] || '',
        modifier: item[:modifier] || '',
        priority: item[:priority] || 1,
        default_quantity: item[:default_quantity] || 1,
        subscribable: item[:subscribable] || 0
      }
      puts "✅ Found existing item: #{item[:description]}".colorize(:green)
    else
      # Item not found
      response = {
        type: 'lookup_result',
        found: false
      }
      puts "ℹ️ Item not found in database".colorize(:yellow)
    end
    
    # Send lookup result as a command to AHK
    send_command("LOOKUP_RESULT|#{response.to_json}")
    response
  end

  def session_complete
    send_command('SESSION_COMPLETE')
    read_response
  end

  def edit_purchase_workflow
    send_command('EDIT_PURCHASE_WORKFLOW')
    read_response # AHK will send back the edited/new purchase data or a status
  end

  def show_purchase_search_dialog
    send_command('SHOW_PURCHASE_SEARCH_DIALOG')
    read_response
  end

  def show_purchase_selection_dialog(purchases)
    # Purchases will be an array of hashes. Convert to JSON string.
    json_purchases = JSON.generate(purchases)
    send_command('SHOW_PURCHASE_SELECTION_DIALOG', params: json_purchases)
    read_response
  end

  def show_editable_purchase_dialog(purchase_data = nil)
    json_purchase_data = purchase_data ? JSON.generate(purchase_data) : "{}"
    send_command('SHOW_EDITABLE_PURCHASE_DIALOG', params: json_purchase_data)
    read_response
  end


  def cleanup
    # Gentle cleanup - just reset session but don't terminate AHK
    send_command('SESSION_COMPLETE') if File.exist?(COMMAND_FILE)
    
    # Clean up communication files but leave AHK running
    [COMMAND_FILE, RESPONSE_FILE].each do |file|
      File.delete(file) if File.exist?(file)
    end
  end

  def terminate_ahk
    # Signal AHK to terminate gracefully
    begin
      File.write(COMMAND_FILE, 'TERMINATE')
      puts "📤 Sent termination signal to AutoHotkey"
      sleep(1) # Give AHK time to process the command
    rescue => e
      puts "⚠️ Failed to send termination signal: #{e.message}"
    end
    
    # Clean up files
    [COMMAND_FILE, RESPONSE_FILE].each do |file|
      File.delete(file) if File.exist?(file)
    end
  end

  def check_status
    # DEPRECATED: Status is now communicated through JSON responses only
    # This method is kept for backward compatibility but should not be used
    # Use read_response and check response[:type] == 'status' instead
    return 'UNKNOWN'
  end

  def read_response
    # Wait for response file to appear (no timeout - matches dialog design)
    until File.exist?(RESPONSE_FILE)
      sleep(0.1)
    end

    response_text = File.read(RESPONSE_FILE).strip
    # Delete the response file immediately after reading to prevent stale data
    File.delete(RESPONSE_FILE) if File.exist?(RESPONSE_FILE)
    sleep(0.1) # Small delay to ensure file system operations complete
    
    # All responses should now be JSON format
    begin
      parsed = JSON.parse(response_text, symbolize_names: true)

      # Normalize status values to lowercase at the lowest level, per user design
      if parsed[:type]&.to_s == 'status' && parsed[:value].is_a?(String)
        parsed[:value].downcase!
      end

      return parsed
    rescue JSON::ParserError => e
      puts "⚠️ Failed to parse JSON response: #{response_text}"
      puts "   Error: #{e.message}"
      # Return a fallback structure
      return { type: 'error', value: response_text, error: 'json_parse_failed' }
    end
  end

  private

  def clear_files
    [COMMAND_FILE, RESPONSE_FILE].each do |file|
      File.delete(file) if File.exist?(file)
    end
  end

  def write_command(command)
    # Wait for any existing command to be processed first
    while File.exist?(COMMAND_FILE)
      sleep(0.1)
    end
    
    File.write(COMMAND_FILE, command)
    puts "  → AHK Command: #{command.split('|').first}".colorize(:light_black)
  end

  def write_response(response)
    File.write(RESPONSE_FILE, response)
    puts "  ← Ruby Response: #{response}".colorize(:light_black)
  end

  def wait_for_completion(timeout)
    puts "  ⏳ Waiting for AHK completion... (timeout: #{timeout || 'none'})"
    # Clear any stale response file before starting
    File.delete(RESPONSE_FILE) if File.exist?(RESPONSE_FILE)

    if timeout
      Timeout.timeout(timeout) do
        wait_loop
      end
    else
      wait_loop
    end
  end

  def wait_loop
    loop do
        next unless File.exist?(RESPONSE_FILE)
        response = read_response
        next if response.nil? || response.empty?

        # Only process status responses, ignore other types
        if response[:type] == 'status'
          status_value = response[:value]
          puts "  ⏳ wait_loop received status: '#{status_value}'"
          
          case status_value.downcase
          when 'ready'
            puts "  ✅ wait_loop returning on READY"
            return true
          when 'error'
            raise "AHK Error: #{response[:error] || 'Unknown error'}"
          when 'shutdown'
            puts "  🛑 wait_loop returning on SHUTDOWN"
            return true
          end
        end

        sleep(0.5)
      end
  end
  rescue Timeout::Error
    raise "AHK command timed out after #{timeout} seconds"
  end
