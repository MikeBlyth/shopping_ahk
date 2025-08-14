#!/usr/bin/env ruby

require_relative 'lib/ahk_bridge'

puts "🧪 Testing AutoHotkey Integration"
puts "================================"

puts "Checking AHK status..."
status_file = 'ahk_status.txt'
if File.exist?(status_file)
  content = File.read(status_file)
  status = content.strip
  puts "  Raw content: #{content.inspect}"
  puts "  Stripped: #{status.inspect}"
else
  status = 'UNKNOWN'
  puts "  File does not exist"
end
puts "  AHK Status: #{status}"

if status == 'READY'
  puts "✅ AutoHotkey is working!"
else
  puts "❌ AutoHotkey is not responding properly"
  puts "  Make sure grocery_automation.ahk is running"
end