#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'lib/database'
require_relative 'grocery_bot'

class MatchingTestRunner
  def initialize
    @db = Database.instance
    # Create a test assistant instance but without AHK for testing
    @assistant = WalmartGroceryAssistant.new
  end

  def run_all_tests
    puts "🧪 Running Matching Tests"
    puts "=" * 50
    
    test_cases = parse_test_file
    
    test_cases.each do |test_case|
      run_test(test_case)
      puts
    end
    
    puts "✅ All tests completed"
  end

  private

  def parse_test_file
    test_file = 'matching tests.txt'
    
    unless File.exist?(test_file)
      puts "❌ Test file not found: #{test_file}"
      return []
    end

    content = File.read(test_file)
    test_cases = []
    current_test = nil

    content.lines.each do |line|
      line = line.strip
      next if line.empty? || line.start_with?('Matching tests') || line.start_with?('The db search')

      # Test item name (no leading dash)
      if !line.start_with?('-')
        current_test = { item: line, expected: nil, description: "" }
        test_cases << current_test
      # Test expectation (starts with dash)
      elsif current_test && line.start_with?('-')
        expectation = line[1..-1].strip # Remove leading dash
        current_test[:description] = expectation
        
        # Parse expected behavior
        if expectation.include?('Should navigate to')
          # Extract prod_id for automatic navigation
          prod_id_match = expectation.match(/(\d+)/)
          if prod_id_match
            current_test[:expected] = { type: :navigate, prod_id: prod_id_match[1] }
          end
        elsif expectation.include?('Should present') && expectation.include?('ask the user to choose')
          # Extract multiple prod_ids for user choice
          prod_ids = expectation.scan(/(\d+)/)
          if prod_ids.any?
            current_test[:expected] = { 
              type: :user_choice, 
              prod_ids: prod_ids.flatten,
              descriptions: extract_descriptions(expectation)
            }
          end
        end
      end
    end

    test_cases.compact
  end

  def extract_descriptions(expectation)
    # Extract descriptions in parentheses
    descriptions = expectation.scan(/\(([^)]+)\)/).flatten
    descriptions
  end

  def run_test(test_case)
    puts "🔍 Testing: #{test_case[:item]}"
    puts "   Expected: #{test_case[:description]}"
    
    # Get actual matches using the same logic as the main system
    matches = @assistant.send(:find_and_rank_matches, test_case[:item])
    
    puts "   Found #{matches.length} matches:"
    matches.each_with_index do |match, idx|
      item = match[:item]
      display_priority = item[:priority].nil? || item[:priority] == '' ? 'blank (=1)' : item[:priority]
      puts "     #{idx + 1}. #{item[:prod_id]} - #{item[:description]} (Priority: #{display_priority}, Score: #{match[:score]}, Type: #{match[:match_type]})"
    end

    # Simulate the decision logic
    exact_matches = matches.select { |match| match[:match_type] == :exact }
    
    if test_case[:expected][:type] == :navigate
      # Should automatically navigate to specific prod_id
      expected_prod_id = test_case[:expected][:prod_id]
      
      if exact_matches.length > 1
        # Multiple exact matches - should pick highest priority
        selected = exact_matches.min_by { |match| @assistant.send(:normalize_priority, match[:item][:priority]) }
        actual_prod_id = selected[:item][:prod_id]
        
        if actual_prod_id == expected_prod_id
          puts "   ✅ PASS: Automatically selected highest priority exact match (#{actual_prod_id})"
        else
          puts "   ❌ FAIL: Expected #{expected_prod_id}, got #{actual_prod_id}"
        end
        
      elsif exact_matches.length == 1
        # Single exact match
        actual_prod_id = exact_matches.first[:item][:prod_id]
        
        if actual_prod_id == expected_prod_id
          puts "   ✅ PASS: Automatically selected exact match (#{actual_prod_id})"
        else
          puts "   ❌ FAIL: Expected #{expected_prod_id}, got #{actual_prod_id}"
        end
        
      else
        puts "   ❌ FAIL: Expected exact match #{expected_prod_id}, but no exact matches found"
      end
      
    elsif test_case[:expected][:type] == :user_choice
      # Should present choices to user
      expected_prod_ids = test_case[:expected][:prod_ids]
      
      if exact_matches.any?
        puts "   ❌ FAIL: Expected user choice, but found exact matches that would auto-navigate"
      elsif matches.length > 1
        actual_prod_ids = matches.map { |m| m[:item][:prod_id] }
        
        # Check if all expected prod_ids are in the matches
        missing_ids = expected_prod_ids - actual_prod_ids
        extra_ids = actual_prod_ids - expected_prod_ids
        
        if missing_ids.empty? && extra_ids.empty?
          puts "   ✅ PASS: Would present user choice with correct options"
        elsif missing_ids.empty?
          puts "   ⚠️  PARTIAL: Would present user choice, but includes extra options: #{extra_ids.join(', ')}"
        else
          puts "   ❌ FAIL: Missing expected options: #{missing_ids.join(', ')}"
        end
        
      else
        puts "   ❌ FAIL: Expected multiple matches for user choice, but found #{matches.length} matches"
      end
    end
  end
end

# Allow running this file directly or as part of another script
if __FILE__ == $0
  runner = MatchingTestRunner.new
  runner.run_all_tests
end