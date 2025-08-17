# Walmart Grocery Automation System - Additional Instructions

## Current System State
- The Walmart grocery automation system is fully functional and working
- AutoHotkey script captures URLs for new items regardless of purchase status
- Ruby backend automatically starts/manages AutoHotkey lifecycle 
- Purchase tracking is implemented with price/quantity capture
- Git repository is set up but not yet pushed to GitHub (needs repo creation first)

## Key Technical Details
- Uses text file communication between Ruby and AutoHotkey (keep it simple!)
- AutoHotkey handles all user interaction via GUI dialogs
- Database has 22 items, 0 purchase records (system just started recording)
- **Hotkey workflow**: 
  - Ctrl+Shift+R: Start automation and continue between items
  - Ctrl+Shift+A: Add new item dialog (during manual navigation)
- **Item processing**: Known items navigate directly, new items search then wait for manual navigation
- **Single purchase dialog**: Combined price and quantity input with default quantity pre-filled

## Recent Improvements
- Fixed browser window detection issues by using manual hotkey triggering
- Implemented automatic URL capture for new products
- Added proper purchase recording with price and quantity
- Created clean lifecycle management with automatic cleanup
- Simplified user interaction with single combined price/quantity dialog
- Fixed duplicate numbering in multiple choice selection lists
- Streamlined item processing flow with proper wait states

## Usage Instructions
1. Run `ruby grocery_bot.rb` (automatically starts AutoHotkey)
2. Open browser to walmart.com
3. Press Ctrl+Shift+R when ready to start
4. For each item, automation will:
   - **Known items**: Navigate directly → Show purchase dialog (price & quantity)
   - **Multiple matches**: Show selection dialog → Navigate to choice → Show purchase dialog
   - **New items**: Search → Wait for manual navigation → Use Ctrl+Shift+A to add or Ctrl+Shift+R to skip
5. Purchase dialog has three options:
   - Enter price & quantity → Records purchase
   - Leave price blank → Skips purchase (saves URL for new items)
   - Cancel → Same as skip

## Browser Compatibility
- System works with any browser setup (tested with Edge "Baseline" group)
- Designed for human-paced shopping to avoid bot detection
- Uses keyboard automation (Ctrl+L, Ctrl+C) for URL capture

## Database Structure
- PostgreSQL with items and purchases tables
- Bi-directional sync with Google Sheets inventory
- Items have prod_id, URL, description, priority, default_quantity
- Purchases track prod_id, quantity, price_cents, purchase_date

## File Structure
- `grocery_bot.rb` - Main automation orchestrator
- `grocery_automation.ahk` - Browser automation with GUI controls  
- `lib/` - Database, Google Sheets, and AutoHotkey bridge modules
  - `ahk_bridge.rb` - Ruby-AHK communication layer
  - `database.rb` - PostgreSQL database interface
  - `google_sheets_integration.rb` - Bi-directional Google Sheets sync
- `.env` - Database credentials and Google Sheets ID
- `google_credentials.json` - Google API service account key

## Recent Technical Fixes (August 2025)

### Race Condition Fix
- **Issue**: File-based IPC had race condition where Ruby read stale "COMPLETED" status from previous commands
- **Root Cause**: Status and response files weren't deleted after reading, causing timing conflicts
- **Solution**: Immediate file deletion after reading in `check_status()` and `read_response()` with 0.1s delays
- **Status**: ✅ FIXED - All commands now working correctly

### UI/UX Improvements  
- **Duplicate Numbers**: Fixed duplicate numbering in multiple choice dialogs (Ruby was adding numbers, AHK was adding them again)
- **Dialog Simplification**: Combined separate price and quantity dialogs into single purchase dialog
- **Flow Optimization**: Eliminated surprise dialogs appearing after search; proper wait states only when manual navigation needed
- **Response Handling**: Fixed add item dialog responses not being processed; wait states now properly end after dialogs

### File Structure Updates
- **Files Renamed**: `grocery_automation_hotkey.ahk` → `grocery_automation.ahk` 
- **Function Separation**: Added `GetCurrentURLSilent()` to prevent URL capture from interfering with dialog responses

## Next Steps if Continued
- Push git repository to GitHub (need to create `shopping_ahk` repo first)
- Monitor purchase history accumulation over time
- Consider any additional automation features

## Item Matching Rules
- **No 1:1 mapping**: Multiple database items can match a single sheet description
- **Sheet sync behavior**: When reading sheet, add new items (if prod_id present) or update existing items with changed fields (add-or-update pattern)
- **Multiple match handling**: When shopping list has multiple matches, AHK should prompt user to choose (numbered list)
- **Match ranking**: Closer, more exact matches should rank higher in selection list
- **Priority handling**: For exact matches with different priorities, automatically navigate to highest priority item (lower number = higher priority, 1 = highest priority)
- **Priority purpose**: Eventually allows skipping "unavailable" items and using lower priority alternatives

## Important Notes
- All sensitive files (.env, credentials) are properly gitignored
- AutoHotkey lifecycle managed automatically (no manual cleanup needed)
- Text file communication is intentionally simple and reliable
- System builds database of known products over time regardless of purchases

# NEW DATA SHEET FLOW
- The sheet will have two sections: product-list and shopping-list. The sheet begins with the product list.  The beginning of the shopping list will be denoted by "Shopping List" in the first column (Purchased column)
- The product list is unchanged except that the quantity should now be ignored. The list is only used for managing the items table.
- The subsequent Shopping List section will not sync with the database but needs to be remembered for rewriting to the sheet. The app will process the items in the shopping list exactly as it has previously done: find the item, navigate to it, open the AHK dialog etc.
- The existing logic I think is thus unchanged except: when in product list, do not test for purchase using the quantity, so will never navigate to thoses pages; when in shopping list, remember the row contents for rewriting. 
- Sync to Sheet:
  1. Clear the sheet
  2. Rewrite the sorted item (product) table which may now be longer than the original
  3. Write a blank line, then the "Shopping list" delimiter in col 1, then the items in the shopping list, which should now have checkmarks for items purchased.
  4. The overall effect is that the updated sheet contains the new, sorted item list followed by the shopping list with purchased items marked.