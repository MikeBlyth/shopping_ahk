# Walmart Grocery Bot - Windows Version

## Project Goal

Automate grocery shopping navigation on Walmart.com using AutoHotkey for browser control and Ruby for data management.

## What This Bot Does

- Reads grocery list from Google Sheets
- For each item:
  - **Known items**: Opens saved Walmart URL, waits for you to add to cart
  - **New items**: Searches Walmart, lets you find the product, saves URL for future
- Tracks purchase history in PostgreSQL database
- **Calculates usage stats**: Tracks units per week and average monthly cost per item
- **Generates reports**: Adds a "Category Breakdown" report to the bottom of your sheet
- Uses AutoHotkey for reliable browser automation (no bot detection)
- You handle login, cart management, and checkout manually

## Technical Architecture

**Windows-native approach:**
- Ruby script for data management (Google Sheets, database, logic)
- AutoHotkey (AHK) script for browser automation
- PostgreSQL database for item URLs and purchase history
- Your regular Windows browser (Chrome, Edge, Firefox)
- Google Sheets API for grocery list management

## Prerequisites

### 1. Ruby for Windows
```powershell
# Download and install Ruby+Devkit from:
# https://rubyinstaller.org/downloads/
# Choose "Ruby+Devkit 3.3.x (x64)" - latest version

# After install, open Command Prompt and verify:
ruby --version
gem --version
```

### 2. PostgreSQL Database
```powershell
# Option A: Install PostgreSQL on Windows
# Download from: https://www.postgresql.org/download/windows/

# Option B: Connect to existing WSL PostgreSQL
# Set environment variables to connect to WSL instance
# HOST: localhost (if WSL port forwarding enabled)
# Or use Docker Desktop PostgreSQL container
```

### 3. AutoHotkey
```powershell
# Download and install AutoHotkey v2:
# https://www.autohotkey.com/download/
```

### 4. Google Sheets Credentials
- Place your `google_credentials.json` file in project root
- Ensure service account has access to your grocery sheet

## File Structure

```
walmart-grocery-windows/
├── README.md                    # This file
├── .env                         # Database and environment config
├── google_credentials.json      # Google Sheets API credentials
├── Gemfile                      # Ruby dependencies
├── grocery_bot.rb              # Main Ruby script
├── grocery_automation.ahk      # AutoHotkey browser automation
├── lib/
│   ├── database.rb             # Database operations
│   ├── google_sheets_integration.rb  # Sheets API
│   └── ahk_bridge.rb           # Ruby-AHK communication
└── db/
    └── schema.sql              # Database setup
```

## Installation

### 1. Ruby Dependencies
```cmd
# In project folder
gem install bundler
bundle install
```

### 2. Database Setup
```cmd
# Create database and tables
ruby setup_database.rb
```

### 3. Environment Configuration
Copy `.env.example` to `.env` and configure:
```env
# Database
POSTGRES_HOST=localhost
POSTGRES_DB=walmart_grocery
POSTGRES_USER=your_username
POSTGRES_PASSWORD=your_password

# Google Sheets
GOOGLE_SHEET_ID=your_sheet_id

# Environment
WALMART_ENVIRONMENT=development
```

### 4. Test Connections
```cmd
# Test database
ruby -r './lib/database.rb' -e 'puts "DB OK" if Database.instance.test_connection'

# Test Google Sheets
ruby -r './lib/google_sheets_integration.rb' -e 'puts "Sheets OK" if GoogleSheetsIntegration.available?'
```

## Usage

### 1. Start Your Browser
- Open Chrome/Edge/Firefox normally
- Navigate to walmart.com/grocery
- Log in completely (handle any bot checks manually)
- Keep browser open

### 2. Run the Grocery Bot
```cmd
ruby grocery_bot.rb
```

### 3. Follow the Interactive Workflow
- Bot loads your grocery list from Google Sheets
- For each item:
  - **Known items**: AHK opens the product URL. Verify price/quantity in dialog, click "Add & Purchase" (or wait for auto-detect).
  - **New items**: AHK searches Walmart. Navigate to product, then press **Ctrl+Shift+A** to add.
  - **Manual Entry**: Press **Ctrl+Shift+A** anytime to add the current product page to the database/shopping list.
  - **Skip**: Click "Skip Item" in any dialog to mark the item as skipped (❌) in the sheet.

## How AutoHotkey Integration Works

The Ruby script communicates with AutoHotkey via temporary files:

**Ruby → AHK:**
- Writes commands to `ahk_command.txt`
- Commands: `OPEN_URL|https://walmart.com/ip/123`, `SEARCH|frozen peas`

**AHK → Ruby:**
- Writes status to `ahk_status.txt` or JSON response to `ahk_response.txt`
- Status: `READY`, `NAVIGATING`, `WAITING_FOR_USER`

**AHK Script Functions:**
- `OpenWalmartURL(url)` - Navigate to product page
- `SearchWalmart(term)` - Search for new items
- `WaitForUserAction()` - Pause for manual cart management
- `GetCurrentURL()` - Return current page URL for saving

## Safety Features

- **No automated purchasing**: You handle all cart and checkout actions
- **Manual cart control**: Bot never clicks "Add to Cart" (it only detects when YOU click it)
- **Human verification**: Bot waits for your confirmation at each step
- **Real browser**: Uses your normal browser (no bot detection)
- **Graceful errors**: Continues if individual items fail
- **Easy to stop**: Ctrl+C stops everything safely

## Google Sheets Format

Your grocery sheet should have these columns:
- **A**: Purchased (status)
- **B**: Item Name
- **C**: Modifier
- **D**: Priority
- **E**: Qty
- **F**: Last Purchased
- **G**: ItemNo
- **H**: URL
- **I**: Subscribable
- **J**: Category
- **K**: Units/Week (Calculated stats)
- **L**: Avg Cost/Month (Calculated stats)

**Note**: The bot will automatically rewrite the sheet structure to match this format, preserving your data.

## Database Schema

**items table:**
- prod_id (VARCHAR) - Walmart product ID
- url (TEXT) - Full Walmart product URL
- description (TEXT) - Item name/description
- modifier (TEXT) - Size/flavor variant
- default_quantity (INTEGER) - Default amount to buy
- priority (INTEGER) - Shopping priority
- subscribable (INTEGER) - 1 if item is subscribed, 0 otherwise
- category (TEXT) - Item category/department
- created_at, updated_at (TIMESTAMP)

**purchases table:**
- prod_id (VARCHAR) - References items.prod_id
- purchase_date (DATE) - When item was bought
- quantity (INTEGER) - Amount purchased
- price_cents (INTEGER) - Price paid in cents
- purchase_timestamp (TIMESTAMP)

## Troubleshooting

### Ruby Issues
```cmd
# Reinstall gems
bundle install --force

# Check Ruby version
ruby --version  # Should be 3.3.x
```

### Database Connection
```cmd
# Test PostgreSQL connection
psql -h localhost -U username -d walmart_grocery

# Check if tables exist
ruby -e "require './lib/database'; puts Database.instance.db.tables"
```

### AutoHotkey Issues
- Ensure AutoHotkey v2 is installed
- Check `grocery_automation.ahk` loads without errors
- Test AHK script independently: double-click the .ahk file

### Google Sheets Access
- Verify service account email has edit access to your sheet
- Check `google_credentials.json` is valid JSON
- Ensure GOOGLE_SHEET_ID in `.env` is correct

## Migration from WSL Version

If you have an existing WSL/Docker version:

1. **Copy Ruby files**: `grocery_bot.rb`, `lib/` folder, and `Gemfile`
2. **Export database**: 
   ```bash
   # From WSL
   docker-compose exec db pg_dump -U mike walmart > walmart_backup.sql
   ```
3. **Import to Windows PostgreSQL**:
   ```cmd
   psql -U username -d walmart_grocery < walmart_backup.sql
   ```
4. **Copy credentials**: Move `google_credentials.json`
5. **Update .env**: Adjust paths and connection strings for Windows

## Development Notes

- **Ruby version**: 3.3.x recommended
- **Database**: PostgreSQL 13+ with Sequel ORM
- **Browser automation**: AutoHotkey v2 for reliability
- **API integration**: Google Sheets API v4
- **Safety first**: Human oversight at every step

This approach eliminates Docker complexity while maintaining all core functionality with better reliability and no bot detection issues.
