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
    wait_for_completion(timeout)
  end

  def open_url(url)
    puts "🌐 Opening URL via AHK: #{url}".colorize(:blue)
    send_command("OPEN_URL|#{url}", timeout: 30)  # 30 second timeout for navigation
  end

  def search_walmart(search_term)
    puts "🔍 Searching Walmart via AHK: #{search_term}".colorize(:blue)
    send_command("SEARCH|#{search_term}", timeout: 30)  # 30 second timeout for search
  end

  def get_current_url
    send_command('GET_URL')
    read_response
  end

  def wait_for_user
    send_command('WAIT_FOR_USER')
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

  def show_message(message)
    send_command("SHOW_MESSAGE|#{message}")  # No timeout - can wait indefinitely
    read_response
  end

  def get_price_input
    send_command('GET_PRICE_INPUT')
    response = read_response

    if response.is_a?(Hash)
      # JSON response format
      case response[:type]
      when 'price'
        response[:value]
      when 'status'
        response[:value] == 'cancelled' ? nil : nil
      else
        nil
      end
    elsif response.is_a?(String)
      # Legacy pipe-delimited format
      if response.start_with?('price|')
        price_str = response.split('|', 2)[1]
        begin
          Float(price_str)
        rescue ArgumentError
          nil
        end
      elsif response == 'cancelled'
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
    send_command("SHOW_MULTIPLE_CHOICE|#{params.join('|')}")

    response = read_response
    if response.is_a?(Hash)
      # JSON response format
      case response[:type]
      when 'choice'
        response[:value]
      when 'status'
        %w[cancelled skipped].include?(response[:value]) ? nil : nil
      else
        nil
      end
    elsif response.is_a?(String)
      # Legacy pipe-delimited format
      if response.start_with?('choice|')
        choice_str = response.split('|', 2)[1]
        begin
          Integer(choice_str)
        rescue ArgumentError
          nil
        end
      elsif %w[cancelled skipped].include?(response)
        nil
      else
        nil
      end
    else
      nil
    end
  end

  def session_complete
    send_command('SESSION_COMPLETE')
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
    return '' unless File.exist?(RESPONSE_FILE)

    response_text = File.read(RESPONSE_FILE).strip
    # Delete the response file immediately after reading to prevent stale data
    File.delete(RESPONSE_FILE) if File.exist?(RESPONSE_FILE)
    sleep(0.1) # Small delay to ensure file system operations complete
    
    # Try to parse as JSON first
    begin
      parsed = JSON.parse(response_text, symbolize_names: true)
      return parsed
    rescue JSON::ParserError
      # Fallback to original string format for backwards compatibility
      return response_text
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
