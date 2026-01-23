require 'sinatra'
require 'json'

# Configure Sinatra
set :port, 54567
set :bind, '127.0.0.1'

# Graceful Exit
trap("INT") { 
  puts "Closing IPC sockets..."
  exit 
}

# Global storage
$current_students = []
$current_walmart_product = nil

# CORS Headers to allow browser extension communication
before do
  headers 'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => ['POST', 'GET', 'DELETE', 'OPTIONS'],
          'Access-Control-Allow-Headers' => 'Content-Type'
end

# Handle preflight OPTIONS request
options '/students' do
  200
end

options '/walmart_product' do
  200
end

# POST /walmart_product - Receive data from Chrome Extension
post '/walmart_product' do
  begin
    payload = JSON.parse(request.body.read)
    
    $current_walmart_product = payload
    
    if payload['walmart_product']
      puts "[#{Time.now.strftime('%H:%M:%S')}] Received Walmart product: #{payload['description'].to_s[0..30]}..."
    end
    
    content_type :json
    { status: 'success' }.to_json
  rescue JSON::ParserError
    status 400
    { status: 'error', message: 'Invalid JSON' }.to_json
  end
end

# GET /walmart_product - Check current state
get '/walmart_product' do
  content_type :json
  ($current_walmart_product || {}).to_json
end

# DELETE /walmart_product - Clear current state
delete '/walmart_product' do
  $current_walmart_product = nil
  content_type :json
  { status: 'cleared' }.to_json
end

# POST /students - Receive data from Chrome Extension
post '/students' do
  begin
    payload = JSON.parse(request.body.read)
    
    # Expecting {"students": [...]}
    if payload.key?('students')
      $current_students = payload['students']
      
      puts "[#{Time.now.strftime('%H:%M:%S')}] Received #{$current_students.length} students"
      
      content_type :json
      { status: 'success', count: $current_students.length }.to_json
    else
      status 400
      { status: 'error', message: 'Missing "students" key' }.to_json
    end
  rescue JSON::ParserError
    status 400
    { status: 'error', message: 'Invalid JSON' }.to_json
  end
end

# GET /students - Check current state
get '/students' do
  content_type :json
  { students: $current_students }.to_json
end

# GET /ahk_data - Optimized string format for AutoHotkey
get '/ahk_data' do
  response.headers['Access-Control-Allow-Origin'] = '*'
  content_type :text
  
  ahk_string = "*upchieve"
  $current_students.each do |student|
    minutes = student['minutes'] || 0
    # Clean pipe characters from data to prevent parsing errors
    name = student['name'].to_s.gsub('|', '')
    topic = student['topic'].to_s.gsub('|', '')
    
    ahk_string += "|#{name}|#{topic}|#{minutes}"
  end
  
  ahk_string
end
