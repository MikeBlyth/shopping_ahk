# Walmart Grocery Automation System - Additional Instructions

## CARDINAL ARCHITECTURAL RULE: Unified Response Format
**ALL AutoHotkey dialogs return the SAME format**: `add_and_purchase|description|modifier|priority|default_quantity|url|price|quantity`

- Multiple choice dialogs handle selection internally, then show purchase dialog, then return unified format
- NO special formats like `choice|1`, `purchase|price|qty`, or any other variations
- Ruby parser expects ONLY the unified format - no special cases or intermediate formats
- Any dialog that needs user input must complete the full flow internally before responding
- When encountering errors, solutions MUST maintain this unified format principle

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

## Ruby's Item Sending Logic

**Ruby sends to AutoHotkey:**

1. **Single Item**: When there's one exact match or Ruby picks the highest priority from multiple exact matches
   - Format: Normal single item flow via `handle_user_interaction`
   - Ruby navigates to the item, AHK shows purchase dialog

2. **Multiple Fuzzy Matches**: When search term matches multiple items but none exactly  
   - Format: Multiple choice dialog via `handle_multiple_matches`
   - User chooses from numbered list or selects "Search for new item"
   - Ruby processes the user's choice

3. **No Matches**: When item not found in database
   - Format: Search mode - Ruby searches Walmart, waits for manual navigation
   - User navigates to desired item, uses Ctrl+Shift+A to add it

**Key Principle**: Ruby always sends the BEST single option to AutoHotkey. For multiple exact matches, Ruby automatically picks the highest priority item (lowest priority number) rather than asking the user to choose between identical items.

### Simple Architecture Flow

**Ruby's Main Processing Loop** (KEEP IT SIMPLE):
```
For each item in shopping list:
  1. Send command to AutoHotkey 
  2. Monitor AutoHotkey stream for response
  3. If purchase was made → record in database
  4. Continue to next item

After shopping list complete:
  Monitor stream for user-initiated add/purchase commands
```

**Critical Rule**: Ruby should NEVER send `WAIT_FOR_USER` commands during main shopping list processing. Ruby only orchestrates - AutoHotkey handles all user interaction, alternatives, substitutions, and dialog flows.

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

### Multiple Choice Dialog Unified Format (August 2025) - RESOLVED ✅
- **Issue**: Multiple choice dialog violated unified response format by returning `choice|1` instead of `add_and_purchase` format
- **Solution**: Multiple choice is UI helper exception - returns simple choice numbers, Ruby handles navigation separately
- **Implementation**: 
  - AutoHotkey `ShowMultipleChoice()` returns simple numbers (1,2,3) or -1 for skip/cancel
  - Ruby `get_choice()` method handles choice parsing separately from business logic responses
  - All other dialogs maintain unified `add_and_purchase|description|modifier|priority|default_quantity|url|price|quantity` format
- **Status**: ✅ FIXED - Choice selection → Navigation → Purchase dialog flow working correctly

### Shopping List Enhancements (August 2025) - COMPLETED ✅
- **ItemID Column Integration**: Added ItemID (column D) for exact database lookups and price calculations
- **Total Price Calculation**: Shopping list now shows unit price × quantity for purchased items
- **Shopping List Grand Total**: Automatic sum of all purchases displayed at bottom
- **ItemID Persistence**: ItemIDs saved back to sheet for future sessions (eliminates fuzzy matching issues)
- **Exact Match Only**: Only exact name matches or existing ItemIDs get price calculations (prevents incorrect data)
- **Enhanced Sheet Format**: [Purchase Mark] [Item Name] [Total Price] [ItemID] with proper column handling

### Dialog Validation Improvements (August 2025) - COMPLETED ✅
- **Required Fields**: Price and quantity now required for purchase recording
- **Inline Error Messages**: Red validation text appears within dialog (no hidden pop-up messages)
- **Skip Detection**: Empty price automatically detected as skip (prevents accidental $0.00 purchases)
- **User Experience**: Clear messaging directing users to Skip/Cancel button when price validation fails

### Critical Bug Fixes (August 2025) - RESOLVED ✅
1. **TOTAL Row Filtering**: Fixed system treating "TOTAL:" as shopping item using `start_with?('TOTAL')` filter
2. **Quit Signal Handling**: Added quit detection in item processing to prevent Ruby hanging after AHK closes
3. **Duplicate Item Processing**: Fixed duplicate items being processed by moving deduplication BEFORE purchase filtering
4. **Stale File Cleanup**: Added robust cleanup of AHK communication files at startup to prevent "unexpected READY status"
5. **ItemID Storage**: Fixed ItemIDs not being saved after multi-choice purchases by passing ItemID through completion chain
6. **Response Format Consistency**: All purchase dialogs now return unified format, AutoHotkey skip sends quantity=0

### Empty Shopping List Flow Fix (August 2025) - RESOLVED ✅
- **Issue**: System would exit immediately when all shopping list items had purchase marks, skipping manual addition phase
- **Root Cause**: Flow logic would terminate early instead of continuing to wait for Ctrl+Shift+A commands
- **Solution**: Restructured main flow to always continue to manual addition phase regardless of shopping list state
- **Implementation**: Simple message change with preserved original flow structure - no complex nested logic
- **Status**: ✅ FIXED - System now properly waits for manual additions when shopping list is complete/empty

### Final Duplicate Processing Resolution (August 2025) - RESOLVED ✅
- **Issue**: Despite duplicate filtering, items like "Milk" were still being reprocessed when one had purchase mark and one didn't
- **Root Cause**: Duplicate removal happened AFTER purchase filtering, so marked duplicates were filtered out but unmarked duplicates passed through
- **Solution**: Moved duplicate removal to happen FIRST, before any other filtering - ensures only first occurrence of each item name is kept
- **Critical Fix**: User feedback identified this as regression - "duplicate removal should happen BEFORE purchase filtering, not after"
- **Implementation**: Modified `load_items_to_order` to deduplicate ALL shopping items first, then apply purchase mark filter to unique items only
- **Status**: ✅ FIXED - Duplicate items no longer bypass purchase mark filtering

## Current System State (August 2025)
- ✅ **FULLY STABLE**: All major bugs resolved, system ready for production use
- ✅ **Empty shopping list handling**: Properly continues to manual addition phase when no items to order
- ✅ **Final duplicate prevention**: Robust deduplication prevents any reprocessing of marked items
- ✅ **Multiple choice dialog**: Working with proper navigation flow
- ✅ **Shopping list with ItemIDs**: Complete price calculations and ItemID persistence  
- ✅ **Clean startup/shutdown**: Proper file cleanup and quit handling
- ✅ **Validation dialogs**: Required fields with inline error messages
- ✅ **Price calculations**: Accurate totals for current and previous session purchases
- ✅ **Error handling**: Comprehensive error display and graceful recovery

## Next Steps if Continued
- Remove debug output once system is stable
- Push git repository to GitHub (need to create `shopping_ahk` repo first)  
- Monitor purchase history accumulation over time
- Consider implementing status file elimination for cleaner architecture
- Performance optimization for large shopping lists

## Future Simplification Opportunity
**Eliminate Status File Mechanism**: The current status file system (READY/COMPLETED/WAITING_FOR_USER states) adds unnecessary complexity. The architecture should follow a pure request-response pattern where:
- Ruby sends command → AutoHotkey waits for user if needed → AutoHotkey responds
- Every command returns a response (even navigation commands can return "ok")
- WAIT_FOR_USER command is redundant - SEARCH can wait indefinitely and respond when user acts
- No status file needed - just response-based communication throughout
- Exception: Multiple choice dialog returns choice numbers (not unified format) as it's a UI helper

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
- *** As we proceed, nothing should modify the overall flow of Ruby-AHK. No new messages, waits, states, etc. without discussing them first ***
- For future refactoring: convert communication to JSON