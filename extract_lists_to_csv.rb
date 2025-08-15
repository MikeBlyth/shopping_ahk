#!/usr/bin/env ruby

require 'nokogiri'
require 'csv'

class WalmartListsExtractor
  def initialize(html_file_path)
    @html_file_path = html_file_path
    @extracted_items = []
  end

  def extract_and_save_csv
    puts "📄 Reading HTML file: #{@html_file_path}"
    
    html_content = File.read(@html_file_path)
    doc = Nokogiri::HTML(html_content)
    
    puts "🔍 Parsing HTML and extracting product data..."
    
    # Find all product links in the list items
    product_links = doc.css('a[href*="/ip/seot/"]')
    
    puts "📊 Found #{product_links.length} product links"
    
    product_links.each do |link|
      extract_product_data(link)
    end
    
    # Remove duplicates based on product ID
    unique_items = @extracted_items.uniq { |item| item[:prod_id] }
    
    puts "\n📈 Extraction Summary:"
    puts "   Total product links found: #{@extracted_items.length}"
    puts "   Unique items extracted: #{unique_items.length}"
    puts "   Items with missing names: #{@extracted_items.count { |item| item[:name].nil? || item[:name].empty? }}"
    
    # Save to CSV
    csv_file = "extracted_walmart_items.csv"
    save_to_csv(unique_items, csv_file)
    
    puts "\n✅ Data extracted and saved to #{csv_file}"
    puts "📄 Review the CSV file before importing to database"
  end

  private

  def extract_product_data(link)
    href = link['href']
    
    # Extract product ID from URL like "/ip/seot/994998279?..."
    if match = href.match(/\/ip\/seot\/(\d+)/)
      prod_id = match[1]
      
      # Find the item name from the link text or nearby span
      item_name = nil
      
      # Try to get item name from the span with class w_V_DM (product title)
      title_span = link.at_css('span.w_V_DM')
      if title_span
        item_name = title_span.text.strip
      end
      
      # If we didn't find it in the link, look for it in a parent container
      if item_name.nil? || item_name.empty?
        # Look for data-testid attribute that contains the product name
        parent = link.ancestors.find { |ancestor| ancestor['data-testid']&.start_with?('tileImage-') }
        if parent
          item_name = parent['data-testid'].sub('tileImage-', '')
        end
      end
      
      # If still no name found, try to extract from aria-label
      if item_name.nil? || item_name.empty?
        aria_label = link['aria-label']
        if aria_label
          item_name = aria_label
        end
      end
      
      # Construct full URL
      full_url = "https://www.walmart.com#{href.split('?').first}"
      
      item_data = {
        prod_id: prod_id,
        name: item_name || '',
        url: full_url
      }
      
      @extracted_items << item_data
      
      if item_name && !item_name.empty?
        puts "   📦 #{item_name} (ID: #{prod_id})"
      else
        puts "   ⚠️  Missing name for product ID: #{prod_id}"
      end
    end
  end

  def save_to_csv(items, filename)
    puts "\n💾 Saving #{items.length} items to CSV..."
    
    CSV.open(filename, 'w', write_headers: true, headers: ['product_id', 'name', 'url']) do |csv|
      items.each do |item|
        csv << [item[:prod_id], item[:name], item[:url]]
      end
    end
    
    puts "✅ CSV file saved: #{filename}"
  end
end

# Run the extractor if called directly
if __FILE__ == $0
  unless ARGV[0]
    puts "Usage: ruby extract_lists_to_csv.rb <html_file_path>"
    puts "Example: ruby extract_lists_to_csv.rb mylists_html.txt"
    exit 1
  end
  
  html_file = ARGV[0]
  
  unless File.exist?(html_file)
    puts "❌ File not found: #{html_file}"
    exit 1
  end
  
  extractor = WalmartListsExtractor.new(html_file)
  extractor.extract_and_save_csv
end