require 'timeout'

class AhkBridge
  COMMAND_FILE = 'ahk_command.txt'
  STATUS_FILE = 'ahk_status.txt'
  RESPONSE_FILE = 'ahk_response.txt'
  
  def initialize
    clear_files
  end
  
  def send_command(command, timeout: 30)
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
    send_command("GET_URL")
    read_response
  end
  
  def wait_for_user
    send_command("WAIT_FOR_USER")
  end
  
  def show_item_prompt(item_name, is_known: false, url: "", description: "")
    params = "#{item_name}|#{is_known}|#{url}|#{description}"
    send_command("SHOW_ITEM_PROMPT|#{params}")
    read_response
  end
  
  def show_progress(current, total, item_name = "")
    params = "#{current}|#{total}|#{item_name}"
    send_command("SHOW_PROGRESS|#{params}")
    read_response
  end
  
  def show_message(message)
    send_command("SHOW_MESSAGE|#{message}")
    read_response
  end
  
  def get_price_input
    send_command("GET_PRICE_INPUT")
    response = read_response
    
    if response.start_with?("price|")
      price_str = response.split("|", 2)[1]
      begin
        return Float(price_str)
      rescue ArgumentError
        return nil
      end
    elsif response == "cancelled"
      return nil
    else
      return nil
    end
  end
  
  def session_complete
    send_command("SESSION_COMPLETE")
    read_response
  end
  
  def check_status
    return 'UNKNOWN' unless File.exist?(STATUS_FILE)
    File.read(STATUS_FILE).strip
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
    puts "  → AHK Command: #{command}".colorize(:light_black)
  end
  
  def wait_for_completion(timeout)
    Timeout.timeout(timeout) do
      loop do
        status = check_status
        puts "  ← AHK Status: #{status}".colorize(:light_black)
        
        case status
        when 'READY'
          return true
        when 'COMPLETED'
          # Reset status to READY for next command
          File.write(STATUS_FILE, 'READY')
          return true
        when 'ERROR'
          response = read_response
          # Reset status to READY even after error
          File.write(STATUS_FILE, 'READY')
          raise "AHK Error: #{response}"
        when 'WAITING_FOR_USER'
          puts "🛑 AHK is waiting for user action...".colorize(:yellow)
          # Don't return - keep waiting until user presses Ctrl+Shift+R
          # The loop will continue and check status again
        end
        
        sleep(0.5)
      end
    end
  rescue Timeout::Error
    # Reset status to READY on timeout
    File.write(STATUS_FILE, 'READY')
    raise "AHK command timed out after #{timeout} seconds"
  end
  
  def read_response
    return '' unless File.exist?(RESPONSE_FILE)
    File.read(RESPONSE_FILE).strip
  end
end