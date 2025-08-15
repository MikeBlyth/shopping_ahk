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
    
    # Find all product links in the list items - let's be more specific
    # Look for links that contain both the product URL and are within list item containers
    product_links = doc.css('li.list-tile a[href*="/ip/seot/"]')
    
    puts "📊 Found #{product_links.length} product links in list items"
    
    if product_links.empty?
      # Fallback: try broader search
      puts "🔄 Trying broader search..."
      product_links = doc.css('a[href*="/ip/seot/"]')
      puts "📊 Found #{product_links.length} total product links"
    end
    
    product_links.each_with_index do |link, index|
      if index < 10  # Debug first 10 items
        puts "\n🔍 Debug item #{index + 1}:"
        puts "   Link href: #{link['href']}"
        puts "   Link text: '#{link.text.strip}'"
        puts "   Link inner HTML: #{link.inner_html[0..200]}..."
      end
      
      extract_product_data(link, index < 10)
    end
    
    # Remove duplicates based on product ID
    unique_items = @extracted_items.uniq { |item| item[:prod_id] }
    
    puts "\n📈 Extraction Summary:"
    puts "   Total product links found: #{@extracted_items.length}"
    puts "   Unique items extracted: #{unique_items.length}"
    puts "   Items with names: #{unique_items.count { |item| item[:name] && !item[:name].empty? }}"
    puts "   Items with missing names: #{unique_items.count { |item| item[:name].nil? || item[:name].empty? }}"
    
    # Save to CSV
    csv_file = "extracted_walmart_items_fixed.csv"
    save_to_csv(unique_items, csv_file)
    
    puts "\n✅ Data extracted and saved to #{csv_file}"
    puts "📄 Review the CSV file before importing to database"
    
    # Show first few items with names for verification
    puts "\n📦 Sample items with names:"
    unique_items.select { |item| item[:name] && !item[:name].empty? }.first(5).each do |item|
      puts "   #{item[:prod_id]}: #{item[:name]}"
    end
  end

  private

  def extract_product_data(link, debug = false)
    href = link['href']
    
    # Extract product ID from URL like "/ip/seot/994998279?..."
    if match = href.match(/\/ip\/seot\/(\d+)/)
      prod_id = match[1]
      
      # Try multiple strategies to find the item name
      item_name = nil
      extraction_method = nil
      
      # Strategy 1: Direct text content of the link
      if link.text && !link.text.strip.empty?
        item_name = link.text.strip
        extraction_method = "direct_link_text" if debug
      end
      
      # Strategy 2: Look for span with product title class
      if !item_name || item_name.empty?
        title_span = link.at_css('span.w_V_DM')
        if title_span && title_span.text
          item_name = title_span.text.strip
          extraction_method = "w_V_DM_span" if debug
        end
      end
      
      # Strategy 3: Look in parent container for data-testid
      if !item_name || item_name.empty?
        # Search in parent elements for data-testid
        parent = link
        5.times do
          parent = parent.parent
          break unless parent
          
          if parent['data-testid']&.start_with?('tileImage-')
            item_name = parent['data-testid'].sub('tileImage-', '')
            extraction_method = "parent_data_testid" if debug
            break
          end
        end
      end
      
      # Strategy 4: Look for aria-label
      if !item_name || item_name.empty?
        if link['aria-label'] && !link['aria-label'].empty?
          item_name = link['aria-label']
          extraction_method = "aria_label" if debug
        end
      end
      
      # Strategy 5: Look in siblings or nearby elements
      if !item_name || item_name.empty?
        # Look for spans with product names in the same list item
        li_parent = link.ancestors('li').first
        if li_parent
          product_spans = li_parent.css('span.w_V_DM')
          if product_spans.any?
            item_name = product_spans.first.text.strip
            extraction_method = "li_parent_span" if debug
          end
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
      
      if debug
        puts "   Product ID: #{prod_id}"
        puts "   Extracted name: '#{item_name}'"
        puts "   Extraction method: #{extraction_method}"
        puts "   Final item: #{item_data}"
      end
      
      if item_name && !item_name.empty?
        puts "   ✅ #{item_name} (ID: #{prod_id})"
      else
        puts "   ❌ Missing name for product ID: #{prod_id}"
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
    puts "Usage: ruby extract_lists_fixed.rb <html_file_path>"
    puts "Example: ruby extract_lists_fixed.rb mylists_html.txt"
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