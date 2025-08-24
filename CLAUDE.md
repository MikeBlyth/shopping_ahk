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
- Git repository committed and ready (local commits ahead of remote)

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

## Current Usage Instructions
1. **Setup**: Run `ruby grocery_bot.rb` (automatically starts AutoHotkey with persistent status window)
2. **Browser**: Open browser to walmart.com, navigate to any page
3. **Start**: Press Ctrl+Shift+R when ready to begin automation
4. **Shopping List Processing**: System processes items from Google Sheets shopping list section:
   - **Known items**: Navigate directly → Show purchase dialog (price & quantity)
   - **Multiple matches**: Show selection dialog → Navigate to choice → Show purchase dialog  
   - **New items**: Search → Wait for manual navigation → Use Ctrl+Shift+A to add or Ctrl+Shift+R to skip
5. **Purchase Dialogs**: Can be left open indefinitely (no timeouts):
   - Enter price & quantity → Records purchase and marks item complete
   - Leave price blank → Skips purchase but saves item data
   - Cancel → Same as skip
6. **Manual Item Addition**: After shopping list completes, use Ctrl+Shift+A anytime to:
   - Add new products to database (with optional purchase recording)
   - Record purchases for existing products (leave description blank)
7. **Completion**: Press Ctrl+Shift+Q to quit → Final Google Sheets sync → Clean exit

**Key Features**:
- ✅ **No time pressure**: Dialogs wait indefinitely for your input
- ✅ **Persistent status**: Always shows what's available (Ctrl+Shift+A, Ctrl+Shift+Q)
- ✅ **Flexible workflow**: Mix automated shopping with manual additions
- ✅ **Crash safe**: System handles crashes gracefully, no orphaned processes

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

## Enhanced item searching in shopping list cycle ✅

When a shopping list item matches an existing database item, the app opens that URL and shows a purchase dialog. However, the user may want to choose an alternative product (different brand, size, etc.) if the original is out of stock or not preferred.

### Solution - IMPLEMENTED ✅

- **"Search Again" button** added to purchase dialog (replaces Cancel button)
- Clicking returns `choice|999` response, integrating with existing multi-choice search flow
- System searches using original shopping list item description  
- User navigates to preferred alternative and presses **Ctrl+Shift+A** to complete
- **Key improvement**: Updates the original shopping list item as purchased (not a separate item)
- **Simplified workflow**: No new commands needed, uses existing hotkey pattern

## Simplified Hotkey System - IMPLEMENTED ✅

The system now operates with just **two user hotkeys**:

### Core Hotkeys
- **Ctrl+Shift+A**: Add/purchase items after manual navigation (universal hotkey)
- **Ctrl+Shift+Q**: Quit system cleanly

### Eliminated Complexity
- **Removed Ctrl+Shift+R**: No longer needed - system auto-starts and uses consistent Ctrl+Shift+A workflow
- **Unified workflow**: All "navigate then act" scenarios use the same Ctrl+Shift+A pattern:
  - New items: Search → Navigate → Ctrl+Shift+A
  - Search Again: Search → Navigate → Ctrl+Shift+A  
  - Manual additions: Navigate → Ctrl+Shift+A

### Status Display Improvements
- **Clear instructions**: Status window shows "find your item, then press Ctrl+Shift+A"
- **Context-aware**: Different messages during search vs completion phases
- **Always visible**: Persistent status window with current available actions

## Major Technical Fixes (August 2025)

### Ctrl+Shift+A Item Addition - RESOLVED ✅
- **Issue**: Items added via Ctrl+Shift+A dialog weren't being saved to database
- **Root Cause**: Logic flaw where Ruby cleared response files as "old" instead of processing them
- **Solution**: Modified response processing to handle existing files properly; restructured monitoring loop
- **Status**: ✅ FIXED - Items now reliably saved to database

### Quit Signal Handling - RESOLVED ✅
- **Issue**: Ruby would not exit when user pressed Ctrl+Shift+Q, continuing to run with "AHK STATUS UNKNOWN"
- **Root Cause**: Quit signal ("quit") was being passed to item processing instead of exit logic
- **Solution**: Added proper quit signal detection before item processing in `wait_for_ahk_shutdown`
- **Status**: ✅ FIXED - Ruby cleanly exits when user presses Ctrl+Shift+Q

### Persistent Status Display ✅
- **Implementation**: Replaced tooltips with styled GUI window for better visibility
- **Features**: Dark themed, always-on-top, positioned in top-right with proper margins
- **Messages**: Shows current state (ready/processing/complete) with available hotkeys
- **Benefits**: Much more visible than tooltips, truly persistent, professional appearance

### Dialog Timeout Elimination ✅
- **Change**: Removed all timeouts from user dialogs (purchase, add item, etc.)
- **Benefit**: Can leave dialogs open indefinitely - come back tomorrow and continue
- **Implementation**: Modified `send_command` to use `timeout: nil` for dialog commands
- **User Experience**: No rush to enter data, supports leisurely shopping pace

### Sheet Sync Timing Fix ✅  
- **Issue**: Google Sheets sync happened immediately after processing, before user finished adding items
- **Solution**: Moved sync to happen only when user quits (after `wait_for_ahk_shutdown`)
- **Benefit**: Can add multiple items via Ctrl+Shift+A before final sync occurs

### Crash Detection & Cleanup ✅
- **Implementation**: Added `TERMINATE` command and comprehensive cleanup handlers
- **Coverage**: Normal exit, Ctrl+C, crashes, exceptions - all scenarios signal AHK to close
- **Mechanism**: Ruby sends `TERMINATE` command, AHK gracefully shuts down
- **Result**: No orphaned AutoHotkey processes after Ruby crashes

### Two-Section Sheet Format ✅
- **Structure**: Product list (database management) + Shopping list (actual ordering)
- **Processing**: Only shopping list items processed for ordering, product list ignored
- **Sync**: Complete sheet rewrite with updated product list + shopping list with purchase marks
- **Quantity Logic**: Blank = 1 (order), explicit 0 = skip, any number = order that amount

### Item Matching Enhancement ✅
- **Improvement**: Search algorithm now includes modifier field in matching
- **Example**: "Chopped walnuts" matches "walnuts" + modifier "chopped"
- **Implementation**: Calculates scores for both description-only and description+modifier
- **Benefit**: Much better matching for natural shopping list entries

### Race Condition Resolution ✅
- **Original Issue**: File-based IPC had timing conflicts with response processing
- **Final Solution**: Proper response file processing instead of clearing, better monitoring loop
- **Status**: All file communication now reliable and race-condition free

### Shopping List Completion Fix ✅
- **Issue**: "Search Again" and new item handling created duplicate items instead of updating original shopping list items
- **Root Cause**: System used general `handle_add_new_item` instead of shopping list-specific completion
- **Solution**: Created `handle_shopping_list_completion` method that updates original shopping list item as purchased
- **Additional Fix**: Added automatic URL capture when dialog URL field is empty/invalid
- **Result**: Shopping list items now properly marked as purchased instead of creating separate database entries

### Hotkey System Simplification ✅
- **Removed**: Ctrl+Shift+R hotkey and all related wait functions (`WaitForUser`, `WaitForContinue`)
- **Unified**: All manual navigation scenarios now use consistent Ctrl+Shift+A pattern
- **Improved**: Status messages clearly show required actions at each step
- **Benefit**: Simpler user experience with just two hotkeys to remember



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

## DATA SHEET FLOW
- The sheet has two sections: product-list and shopping-list. The sheet begins with the product list.  The beginning of the shopping list is denoted by "Shopping List" in the first column (Purchased column)
- The product list is unchanged except that the quantity should now be ignored. The list is only used for managing the items table.
- The subsequent Shopping List section does not sync with the database but needs to be remembered for rewriting to the sheet. The app will process the items in the shopping list exactly as it has previously done: find the item, navigate to it, open the AHK dialog etc.
- Sync to Sheet:
  1. Clear the sheet
  2. Rewrite the sorted item (product) table which may now be longer than the original
  3. Write a blank line, then the "Shopping list" delimiter in col 1, then the items in the shopping list, which should now have checkmarks for items purchased.
  4. The overall effect is that the updated sheet contains the new, sorted item list followed by the shopping list with purchased items marked.

## Important User-generated Notes to Claude: -- Do Not Make Changes Beyond This Point

- The system is working well. Important: Do not make significant changes to structure without asking user. Do not make miscellaneous changes without being instructed to do so, but do suggest them if they seem to be a good idea. 
- ToDO - Log file that can be used to recover from crash
- Be critical and ready to push back on suggestions that may not be optimal. Be critical of yourself as well. Do not praise every idea or change without considering well.
- Ask if I want to stage with "git add ." before making extensive changes

## Current Development

### Purchase detection

I want to add the ability for the app to detect when the user has purchased a product by clicking the add to cart button. Otherwise, I could click the "Add Purchase" button in the app but forget to do so in the online store.

This involves
- Detect the button position by image search. The image to match is ./images/add_to_cart.png
- The search range for that image is 
    x: 75% to 90% of width
    y: 20% to 80% of height
- Color tolerance is 10

Flow

- When navigating to a page, the purchase dialog will be shown as usual, but without the "Add & Purchase" button. A prompt in the dialog will remind the user to click "Add to Cart" or skip.
- AHK will find add_to_cart.png
- The button region will be defined as that point (upper-left) to the (x: right edge of screen, y: upper y + 100 pixels)
- AHK will then monitor for a click in that region/
- When a click is detected, the "Add & Purchase" button will be added to the dialog.

In this way, the user can't "purchase" an item in the app until they click the shop's add_to_cart button.