require 'timeout'

class AhkBridge
  COMMAND_FILE = 'ahk_command.txt'
  STATUS_FILE = 'ahk_status.txt'
  RESPONSE_FILE = 'ahk_response.txt'

  def initialize
    clear_files
  end

  def send_command(command, timeout: 300)
    write_command(command)
    wait_for_completion(timeout)
  end

  def open_url(url)
    puts "🌐 Opening URL via AHK: #{url}".colorize(:blue)
    send_command("OPEN_URL|#{url}")
  end

  def search_walmart(search_term)
    puts "🔍 Searching Walmart via AHK: #{search_term}".colorize(:blue)
    send_command("SEARCH|#{search_term}")
  end

  def get_current_url
    send_command('GET_URL')
    read_response
  end

  def wait_for_user
    send_command('WAIT_FOR_USER')
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
    send_command("SHOW_MESSAGE|#{message}")
    read_response
  end

  def get_price_input
    send_command('GET_PRICE_INPUT')
    response = read_response

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
  end

  def show_multiple_choice(title:, options:, allow_skip: true)
    # Format: SHOW_MULTIPLE_CHOICE|title|allow_skip|option1|option2|...
    params = [title, allow_skip.to_s] + options
    send_command("SHOW_MULTIPLE_CHOICE|#{params.join('|')}")

    response = read_response
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
  end

  def session_complete
    send_command('SESSION_COMPLETE')
    read_response
  end

  def cleanup
    # Clean shutdown without waiting for response
    send_command('SESSION_COMPLETE') if File.exist?(COMMAND_FILE)
    
    # Give AHK a moment to process the command
    sleep(1)
    
    # Clean up any leftover files
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

    Timeout.timeout(timeout) do
      loop do
        status = check_status
        puts "  ← AHK Status: #{status}".colorize(:light_black)

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
          raise 'AHK script was shut down by user'
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

  def read_response
    return '' unless File.exist?(RESPONSE_FILE)

    response = File.read(RESPONSE_FILE).strip
    # Delete the response file immediately after reading to prevent stale data
    File.delete(RESPONSE_FILE) if File.exist?(RESPONSE_FILE)
    sleep(0.1) # Small delay to ensure file system operations complete
    response
  end
end
