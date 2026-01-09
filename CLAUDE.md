# Walmart Grocery Automation System - Additional Instructions

## Current System State
- ✅ **FULLY WORKING**: Walmart grocery automation system is stable and production-ready
- ✅ **Ctrl+Shift+A item addition**: Works reliably, items properly saved to database
- ✅ **Persistent status window**: Visible, styled status display with proper positioning
- ✅ **No premature syncing**: Google Sheets sync only happens after user finishes session
- ✅ **Infinite dialog timeouts**: Can leave purchase dialogs open indefinitely
- ✅ **Crash detection**: Ruby automatically signals AHK to close on any exit scenario
- ✅ **Two-section sheet format**: Product list + Shopping list with proper handling
- ✅ **Quit signal handling**: Ruby properly exits when user presses Ctrl+Shift+Q
- ✅ **Purchase detection**: Detects "Add to Cart" clicks with visual feedback in dialogs
- ✅ **Price detection**: Automatic OCR price detection after "Add to Cart" clicks
- ✅ **Skip Button**: Added to "Add Item" dialog, works correctly
- ✅ **Category Support**: Database and Sheet now track item categories
- ✅ **Reporting**: Sheet now includes usage stats (Units/Week, Cost/Month) and a Category Breakdown report
- Git repository committed and ready (local commits ahead of remote)

## Key Technical Details
- Uses text file communication between Ruby and AutoHotkey (keep it simple!)
- AutoHotkey handles all user interaction via GUI dialogs
- **Hotkey workflow**: 
  - Ctrl+Shift+Q: Quit system
  - Ctrl+Shift+A: Add new item dialog (during manual navigation)
- **Item processing**: Known items navigate directly, new items search then wait for manual navigation
- **Single purchase dialog**: Combined price and quantity input with default quantity pre-filled

## Recent Improvements
- **Category Support**: Added `category` column to database and sync logic.
- **Reporting**: Added calculated columns for "Units/Week" and "Avg Cost/Month" based on global database start date. Added a "Category Breakdown" mini-report.
- **Improved URL Sync**: Auto-generates URLs from Item IDs if missing; handles simplified Walmart URL formats.
- **Dialog Stability**: Fixed crash when cancelling "Add Item" dialog ("Control is destroyed" error).
- **Skip Functionality**: Added "Skip Item" button to manual entry dialog with proper Ruby handling.
- **Enhanced Sheet Parsing**: 
  - Stops processing shopping list when "TOTAL" or "CATEGORY" is encountered.
  - Ignores rows where the item description contains a `$` sign (misplaced prices).
- **Sync Logic**: Prevents blank sheet entries from overwriting existing database values; ensures URLs are captured even if missing in sheet.
- **Active/Inactive Status**: Added `status` column to items. Items removed from the sheet are now marked as `inactive` (archived) in the database instead of being deleted. They can be reactivated by adding them back to the sheet.
- **Testing Structure**: Moved tests to `tests/` directory. Added `sync_logic_test.rb` to verify status transitions. Run tests with `ruby tests/test_file.rb`.

## Current Usage Instructions
1. **Setup**: Run `ruby grocery_bot.rb` (automatically starts AutoHotkey with persistent status window)
2. **Browser**: Open browser to walmart.com, navigate to any page
3. **Start**: Press Ctrl+Shift+R when ready to begin automation (or wait for auto-start)
4. **Shopping List Processing**: System processes items from Google Sheets shopping list section:
   - **Known items**: Navigate directly → Show purchase dialog (price & quantity)
   - **Multiple matches**: Show selection dialog → Navigate to choice → Show purchase dialog  
   - **New items**: Search → Wait for manual navigation → Use Ctrl+Shift+A to add or Skip
5. **Purchase Dialogs**: Can be left open indefinitely (no timeouts):
   - Enter price & quantity → Records purchase and marks item complete
   - Leave price blank → Skips purchase but saves item data
   - **Skip Item** → Marks item as skipped (❌) in sheet
6. **Manual Item Addition**: After shopping list completes, use Ctrl+Shift+A anytime to:
   - Add new products to database (with optional purchase recording)
   - Record purchases for existing products (leave description blank)
7. **Completion**: Press Ctrl+Shift+Q to quit → Final Google Sheets sync → Clean exit

**Key Features**:
- ✅ **No time pressure**: Dialogs wait indefinitely for your input
- ✅ **Persistent status**: Always shows what's available (Ctrl+Shift+A, Ctrl+Shift+Q)
- ✅ **Flexible workflow**: Mix automated shopping with manual additions
- ✅ **Crash safe**: System handles crashes gracefully, no orphaned processes
- ✅ **Insightful Reports**: Automatic calculation of weekly usage and monthly costs

## Database Structure
- PostgreSQL with items and purchases tables
- Bi-directional sync with Google Sheets inventory
- Items have prod_id, URL, description, modifier, priority, default_quantity, subscribable, category
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

## Sync from Database to Sheet

At the end of any run, even in case of a crash, the sheet must be sync'd with the database.

### Iterating Through The shopping list
- The shopping list @shopping_list_data contains the current state of all the items in the list. 
- When an item is purchased, add the itemid, quantity, and price to the @shopping_list_data record.
- Items that already have checkmark from the initial load (i.e. already purchased) should be kept unchanged. Do not mark them as skipped (red x) since they're already purchased. 
- After traversing the shopping list, the user may add other items to purchase. These must be added to the @shopping_list_data and display on sync_from_database
### Shopping List Display
- The format of the display for each item should be

{✅{qty} | ❌ } | {description} | {total_price = qty*price} | itemid 

- The last line should be the TOTAL cost of all the items.
- Previously purchased items (see above) should display just the same as new ones.

## Enhanced Reporting ✅

The Google Sheet sync now includes valuable consumption metrics:

1.  **Item Stats**:
    *   **Units/Week**: Average units consumed per week over the database's lifetime.
    *   **Avg Cost/Month**: Average monthly spending on this item.
    *   *Calculation base*: Uses the date the first item was created in the database as the start date for all calculations.

2.  **Category Report**:
    *   Located at the bottom of the sheet (after Shopping List).
    *   Lists all categories sorted by monthly spend (descending).
    *   Helps identify where the budget is going (e.g., "Dairy", "Produce", "Snacks").

## Important User-generated Notes to Claude: -- Do Not Make Changes Beyond This Point

- The system is working well. Important: Do not make significant changes to structure without asking user. Do not make miscellaneous changes without being instructed to do so, but do suggest them if they seem to be a good idea. 
- ToDO - Log file that can be used to recover from crash
- Be critical and ready to push back on suggestions that may not be optimal. Be critical of yourself as well. Do not praise every idea or change without considering well.
- Ask if I want to stage with "git add ." before making extensive changes
- AHK is always v2
