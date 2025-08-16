#!/usr/bin/env ruby

require 'colorize'
require_relative 'lib/ahk_bridge'

puts "Testing AHK dialog functionality..."

# Start fresh
system("taskkill /F /IM AutoHotkey*.exe 2>nul")

# Start AHK script
script_path = File.join(__dir__, 'grocery_automation_hotkey.ahk')
system("start \"\" \"#{script_path}\"")

puts "Waiting for AHK to start..."
sleep(3)

# Test basic communication
ahk = AhkBridge.new

puts "Testing SHOW_MESSAGE command..."
ahk.show_message("Test message - if you see this, basic AHK dialog works!")

puts "Testing SHOW_ITEM_PROMPT command..."
response = ahk.show_item_prompt("Test Item", is_known: true, description: "Test description")
puts "Response: '#{response}'"

# Check what's actually in the response file
if File.exist?('ahk_response.txt')
  puts "Response file contents: '#{File.read('ahk_response.txt')}'"
end

puts "Test complete!"