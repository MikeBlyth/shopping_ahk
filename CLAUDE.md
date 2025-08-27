# Walmart Grocery Automation System - Additional Instructions

## Current System State
- ❌ **TEMPORARILY BROKEN**: AutoHotkey script crashes with access violation (fixed corrupted code structure Aug 27, but still has loading issues)
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

### Purchase Detection Implementation ✅
- **Feature**: Detects when user clicks "Add to Cart" button on product pages using image search
- **Visual Feedback**: Purchase dialogs start with red "⚠️ Override" button, change to green "✅ Add & Purchase" when cart click detected
- **Image Search**: Uses `images/add_to_cart_left.png` with tolerance *100, searches 75-90% width, 20-80% height of screen
- **Click Monitoring**: Global `~LButton::` hotkey monitors clicks in detected button region
- **Window Activation Fix**: Image search activates browser window before searching to ensure consistent detection
- **JSON Response Format**: Converted from pipe-delimited to proper JSON for reliable data communication
- **Integration**: Works seamlessly with existing purchase dialogs without disrupting workflow



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
- AHK is always v2

## Current Development

### Purchase Detection - COMPLETED ✅

Purchase detection feature has been successfully implemented and is now fully operational:

- **Image Search**: Uses `images/add_to_cart_left.png` to locate "Add to Cart" buttons on product pages
- **Search Region**: 75-90% width, 20-80% height of screen with *100 tolerance
- **Visual Feedback**: Dialogs start with red "⚠️ Override" button, change to green "✅ Add & Purchase" when cart click detected
- **Click Monitoring**: Global mouse click handler monitors the detected button region
- **Window Activation**: Ensures browser window is active before image search for consistent detection
- **JSON Communication**: Proper JSON formatting for reliable data exchange between AHK and Ruby
- **Integration**: Works seamlessly with both purchase dialogs and add item dialogs

The system now prevents users from marking items as purchased in the app until they actually click the "Add to Cart" button on the website, ensuring synchronization between the automation and actual shopping cart actions.

### Price Detection - COMPLETED ✅

Automatic price detection feature has been successfully implemented and is now fully operational:

- **OCR Integration**: Uses `lib/get_price_function.ahk` with pre-trained character patterns for Walmart's large price font
- **Click-Triggered**: Price detection starts automatically when user clicks "Add to Cart" button on website
- **Search Region**: Right 25% of screen (75-100% width, 25-75% height) for optimal price location
- **4-Second Window**: Searches every 500ms for up to 4 seconds, then stops automatically
- **Smart Stopping**: Stops immediately when price found, user types manually, or dialog closed
- **Performance Logging**: Debug logs show exact OCR timing on successful detection (typically ~600ms per iteration)
- **Error Protection**: Safely handles Add to Cart clicks when no dialog present, prevents crashes
- **Automatic Fill**: Successfully detected prices are automatically filled into price field
- **User Override**: Users can still enter prices manually - detection stops when typing begins

**Technical Implementation:**
- **Character Library**: `LoadPriceCharacters()` loads exact pixel patterns at startup
- **Asynchronous**: Uses `SetTimer()` for non-blocking background detection  
- **FindText OCR**: Searches for "$1234567890." characters with strict matching (0.05 tolerance)
- **Pattern Validation**: Validates extracted text has proper price format (digits.digits)
- **Reference Management**: Each dialog sets its own `CurrentPriceEdit` reference for multi-item support

The system provides seamless price detection that works across all items in the shopping list, significantly reducing manual data entry while maintaining full user control.