require 'timeout'

class AhkBridge
  COMMAND_FILE = 'ahk_command.txt'
  STATUS_FILE = 'ahk_status.txt'
  RESPONSE_FILE = 'ahk_response.txt'

  def initialize
    clear_files
  end

  def send_command(command, timeout: nil)
    write_command(command)
    wait_for_completion(timeout)
  end

  def send_command_and_wait(command, timeout: nil)
    send_command(command, timeout: timeout)
    read_response
  end

  def open_url(url)
    puts "🌐 Opening URL via AHK: #{url}".colorize(:blue)
    send_command("OPEN_URL|#{url}", timeout: 30) # 30 second timeout for navigation
  end

  def search_walmart(search_term)
    puts "🔍 Searching Walmart via AHK: #{search_term}".colorize(:blue)
    send_command_and_wait("SEARCH|#{search_term}", timeout: nil) # No timeout for user interaction
  end

  def get_current_url
    send_command_and_wait('GET_URL')
  end

  def wait_for_user
    send_command('WAIT_FOR_USER')
  end

  def show_add_item_dialog(suggested_name = '')
    send_command_and_wait("ADD_ITEM_DIALOG|#{suggested_name}")
  end

  def show_item_prompt(item_name, is_known: false, url: '', description: '', item_description: '', default_quantity: 1)
    params = "#{item_name}|#{is_known}|#{url}|#{description}|#{item_description}|#{default_quantity}"
    puts '🎭 About to send SHOW_ITEM_PROMPT command...'.colorize(:yellow)

    begin
      response = send_command_and_wait("SHOW_ITEM_PROMPT|#{params}")
      puts "🎭 SHOW_ITEM_PROMPT response: '#{response}'".colorize(:yellow)
      response
    rescue StandardError => e
      puts "🎭 SHOW_ITEM_PROMPT failed: #{e.message}".colorize(:red)
      ''
    end
  end

  def show_message(message)
    send_command_and_wait("SHOW_MESSAGE|#{message}") # No timeout - can wait indefinitely
  end

  def get_price_input
    response = send_command_and_wait('GET_PRICE_INPUT')

    # Handle parsed response hash
    if response[:raw_response]
      raw = response[:raw_response]
      if raw.start_with?('price|')
        price_str = raw.split('|', 2)[1]
        begin
          Float(price_str)
        rescue ArgumentError
          nil
        end
      elsif raw == 'cancelled'
        nil
      else
        nil
      end
    else
      nil
    end
  end

  def show_multiple_choice(title:, options:, allow_skip: true)
    # Format: SHOW_MULTIPLE_CHOICE|title|allow_skip|option1|option2|...
    params = [title, allow_skip.to_s] + options
    send_command("SHOW_MULTIPLE_CHOICE|#{params.join('|')}", timeout: nil)
    get_choice
  end

  def get_choice
    # Get choice response from multiple choice dialog
    return nil unless File.exist?(RESPONSE_FILE)

    response = File.read(RESPONSE_FILE).strip
    File.delete(RESPONSE_FILE) if File.exist?(RESPONSE_FILE)
    sleep(0.1)
    
    puts "🔍 DEBUG: Raw choice response: '#{response}'"
    
    choice_num = response.to_i
    puts "🔍 DEBUG: Parsed choice number: #{choice_num}"
    
    # Return nil for skip/cancel (-1), otherwise return the choice number
    choice_num == -1 ? nil : choice_num
  end


  def LIST_COMPLETE
    send_command_and_wait('LIST_COMPLETE')
  end

  def cleanup
    # Gentle cleanup - just reset session but don't terminate AHK
    send_command('LIST_COMPLETE') if File.exist?(COMMAND_FILE)

    # Clean up communication files but leave AHK running
    [COMMAND_FILE, RESPONSE_FILE].each do |file|
      File.delete(file) if File.exist?(file)
    end
  end

  def terminate_ahk
    # Signal AHK to terminate gracefully
    begin
      File.write(COMMAND_FILE, 'TERMINATE')
      puts '📤 Sent termination signal to AutoHotkey'
      sleep(1) # Give AHK time to process the command
    rescue StandardError => e
      puts "⚠️ Failed to send termination signal: #{e.message}"
    end

    # Clean up files
    [COMMAND_FILE, STATUS_FILE, RESPONSE_FILE].each do |file|
      File.delete(file) if File.exist?(file)
    end
  end

  def check_status
    return 'UNKNOWN' unless File.exist?(STATUS_FILE)

    status = File.read(STATUS_FILE).strip
    # Delete the status file immediately after reading to prevent stale data
    File.delete(STATUS_FILE) if File.exist?(STATUS_FILE)
    sleep(0.1) # Small delay to ensure file system operations complete
    status
  end

  def read_response
    return { skip: true } unless File.exist?(RESPONSE_FILE)

    response = File.read(RESPONSE_FILE).strip
    # Delete the response file immediately after reading to prevent stale data
    File.delete(RESPONSE_FILE) if File.exist?(RESPONSE_FILE)
    sleep(0.1) # Small delay to ensure file system operations complete
    
    parse_response(response)
  end

  def parse_response(response_data)
    # Parse AHK response into structured hash, return skip flag if needed
    puts "🔍 DEBUG: Raw response_data: '#{response_data}'"
    return { skip: true } if response_data.nil? || response_data.strip.empty? || response_data == 'skip'
    
    parts = response_data.split('|')
    puts "🔍 DEBUG: Parsing response: #{parts.inspect}"
    puts "🔍 DEBUG: parts.length = #{parts.length}"

    case parts[0]
    when 'add_and_purchase'
      # Standard purchase format: add_and_purchase|description|modifier|priority|default_quantity|url|price|quantity
      if parts.length >= 8
        {
          skip: false,
          description: parts[1].strip,
          modifier: parts[2].strip,
          priority: parts[3].strip.to_i,
          default_quantity: parts[4].strip.to_i,
          url: parts[5].strip,
          price: parts[6].strip,
          quantity: parts[7].strip.to_i
        }
      else
        puts "❌ Invalid add_and_purchase format: #{response_data}"
        { skip: true }
      end
    else
      # Other responses (like session_reset, quit, etc.) - pass through as raw string
      { raw_response: response_data }
    end
  end

  private

  def clear_files
    [COMMAND_FILE, RESPONSE_FILE].each do |file|
      File.delete(file) if File.exist?(file)
    end
    # Don't delete STATUS_FILE - let AHK manage it
  end

  def write_command(command)
    File.write(COMMAND_FILE, command)
    puts "  → AHK Command: #{command.split('|').first}".colorize(:light_black)
  end

  def wait_for_completion(timeout)
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
      status = check_status

      case status
      when 'READY'
        return true
      when 'COMPLETED'
        # Wait a moment to ensure AHK has finished writing response
        sleep(0.1)
        return true
      when 'ERROR'
        response = read_response
        raise "AHK Error: #{response}"
      when 'SHUTDOWN'
        puts '  ℹ️ AutoHotkey script shutting down (user-initiated via Ctrl+Shift+Q)'
        return true
      when 'WAITING_FOR_USER'
        puts '🛑 AHK is waiting for user action...'.colorize(:yellow)
        # Don't return - keep waiting until user presses Ctrl+Shift+R
        # The loop will continue and check status again
      end

      sleep(0.5)
    end
  end
rescue Timeout::Error
  raise "AHK command timed out after #{timeout} seconds"
end
