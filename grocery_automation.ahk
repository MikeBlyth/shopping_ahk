; Walmart Grocery Automation
; Uses Ctrl+Shift+A to add items and Ctrl+Shift+Q to quit

; Include JSON library and image search function
#Include lib/jsongo.v2.ahk
#Include lib/image_search_function.ahk
#Include lib/get_price_function.ahk

; Use fast typing of URL 
SendMode "Input"

; Hotkeys
^+q::{
    ; Clean exit - signal Ruby and shutdown
    PerformQuit()
}

^+a::{
    ; Add new item hotkey
    WriteDebug("Ctrl+Shift+A pressed - calling ShowAddItemDialogHotkey")
    ShowAddItemDialogHotkey()
}

^+e::{
    ; Edit purchase hotkey
    WriteDebug("Ctrl+Shift+E pressed - calling EditPurchaseHotkey")
    EditPurchaseHotkey()
}


^+s::{  ; Ctrl+Shift+S to show status
    status := FileExist(StatusFile) ? FileRead(StatusFile) : "No status file"
    MsgBox("Current Status: " . status . "`n`nActive hotkeys: Ctrl+Shift+A (add item), Ctrl+Shift+Q (quit)")
}


; File paths for communication
ScriptDir := A_ScriptDir
CommandFile := ScriptDir . "\ahk_command.txt"
StatusFile := ScriptDir . "\ahk_status.txt"
ResponseFile := ScriptDir . "\ahk_response.txt"

; Centralized logging function
WriteDebug(message) {
    FileAppend(message . "`n", "command_debug.txt")
}


; Global variables
UserReady := false
StatusGui := ""
; Purchase detection variables
ButtonRegion := {left: 0, top: 0, right: 0, bottom: 0}
ButtonFound := false
CurrentPurchaseButton := ""
; Price detection variables
PriceDetectionTimer := ""
PriceDetectionActive := false
CurrentPriceEdit := ""
PriceDetectionStartTime := 0

; Initialize - clear any leftover files from previous session
try {
    FileDelete(CommandFile)
    FileDelete(ResponseFile) 
    FileDelete(StatusFile)  ; Clear old status file too
} catch {
    ; Ignore errors if files don't exist
}

; WriteStatus("WAITING_FOR_HOTKEY")

; Clear debug log at startup
try {
    FileDelete("command_debug.txt")
    FileAppend("=== AutoHotkey started at " . A_Now . " ===`n", "command_debug.txt")
} catch {
    ; Ignore errors if file doesn't exist
}

; Load price character library for OCR price detection
LoadPriceCharacters()

; Load subscribe pattern for auto-detection
LoadSubscribePattern()

; Automatically find and select Walmart window
TargetWindowHandle := WinExist("Walmart")
if !TargetWindowHandle {
    ; No Walmart window found - find any browser and open new tab
    TargetWindowHandle := FindAndOpenWalmart()
    if !TargetWindowHandle {
        MsgBox("Could not find a browser window or open Walmart. Please open a browser first.")
        ExitApp
    }
}
WinActivate(TargetWindowHandle)

; Auto-start after window selection
UserReady := true
SendStatus("ready")

; Update status for shopping mode
ShowPersistentStatus("Processing shopping list")


; Main loop - check for commands every 500ms
Loop {
    if FileExist(CommandFile) {
        command := FileRead(CommandFile, "UTF-8")
        ProcessCommand(command)
        if FileExist(CommandFile)
            FileDelete(CommandFile)
    }
    Sleep(500)
}

ProcessCommand(command) {
    ; Debug: Log all commands received
    FileAppend("Received command: '" . command . "'`n", "command_debug.txt")
    
    ; Try to parse as JSON first, fallback to pipe-delimited
    try {
        cmd_obj := jsongo.Parse(command)
        action := cmd_obj["action"]
        param := cmd_obj.Has("param") ? cmd_obj["param"] : ""
        FileAppend("Parsed JSON - action: '" . action . "', param: '" . param . "'`n", "command_debug.txt")
    } catch {
        ; Fallback to pipe-delimited parsing for backwards compatibility
        pipe_pos := InStr(command, "|")
        if (pipe_pos > 0) {
            action := SubStr(command, 1, pipe_pos - 1)
            param := SubStr(command, pipe_pos + 1)
        } else {
            action := command
            param := ""
        }
        FileAppend("Parsed pipe-delimited - action: '" . action . "', param: '" . param . "'`n", "command_debug.txt")
    }
    
    switch action {
        case "OPEN_URL":
            FileAppend("MATCHED OPEN_URL`n", "command_debug.txt")
            OpenURL(param)
        case "SEARCH":
            FileAppend("MATCHED SEARCH`n", "command_debug.txt")
            SearchWalmart(param)
        case "GET_URL":
            FileAppend("MATCHED GET_URL`n", "command_debug.txt")
            GetCurrentURL()
        case "ACTIVATE_BROWSER":
            FileAppend("MATCHED ACTIVATE_BROWSER`n", "command_debug.txt")
            ActivateBrowserCommand()
        case "SHOW_MESSAGE":
            FileAppend("MATCHED SHOW_MESSAGE`n", "command_debug.txt")
            ShowMessage(param)
        case "SHOW_ITEM_PROMPT":
            FileAppend("MATCHED SHOW_ITEM_PROMPT`n", "command_debug.txt")
            ShowItemPrompt(param)
        case "NAVIGATE_AND_SHOW_DIALOG":
            FileAppend("MATCHED NAVIGATE_AND_SHOW_DIALOG`n", "command_debug.txt")
            NavigateAndShowDialog(param)
        case "SHOW_MULTIPLE_CHOICE":
            FileAppend("MATCHED SHOW_MULTIPLE_CHOICE`n", "command_debug.txt")
            ShowMultipleChoice(param)
        case "GET_PRICE_INPUT":
            FileAppend("MATCHED GET_PRICE_INPUT`n", "command_debug.txt")
            GetPriceInput()
        case "SESSION_COMPLETE":
            FileAppend("MATCHED SESSION_COMPLETE`n", "command_debug.txt")
            ProcessSessionComplete()
        case "LOOKUP_RESULT":
            FileAppend("MATCHED LOOKUP_RESULT`n", "command_debug.txt")
            FileAppend("LOOKUP_RESULT param: " . param . "`n", "command_debug.txt")
            ProcessLookupResult(param)
        case "ADD_ITEM_DIALOG":
            FileAppend("MATCHED ADD_ITEM_DIALOG`n", "command_debug.txt")
            ShowAddItemDialog(param)
        case "SHOW_PURCHASE_SEARCH_DIALOG":
            FileAppend("MATCHED SHOW_PURCHASE_SEARCH_DIALOG`n", "command_debug.txt")
            ShowPurchaseSearchDialogAHK()
        case "SHOW_PURCHASE_SELECTION_DIALOG":
            FileAppend("MATCHED SHOW_PURCHASE_SELECTION_DIALOG`n", "command_debug.txt")
            ShowPurchaseSelectionDialogAHK(param)
        case "SHOW_EDITABLE_PURCHASE_DIALOG":
            FileAppend("MATCHED SHOW_EDITABLE_PURCHASE_DIALOG`n", "command_debug.txt")
            ShowEditablePurchaseDialogAHK(param)
        case "TERMINATE":
            FileAppend("MATCHED TERMINATE - shutting down`n", "command_debug.txt")
            
            ; Silently close all dialogs
            CloseAllDialogs()
            
            ; Silent shutdown - no MsgBox
            ExitApp()
        default:
            FileAppend("UNKNOWN COMMAND - action: '" . action . "', original: '" . command . "'`n", "command_debug.txt")
            SendError("Unknown command: " . action)
    }
}

OpenURL(url) {
    ; Go to address bar and navigate
    WinActivate(TargetWindowHandle)
    WinWaitActive(TargetWindowHandle)
    WriteDebug("DEBUG: OpenURL called for: " . url)

    try {
        PasteURL(url)
        WriteDebug("DEBUG: OpenURL sending ready status")
        SendStatus("ready")
        return true
    } catch as e {
        WriteDebug("ERROR: OpenURL failed: " . e.message)
        SendError("Failed to navigate to: " . url)
        return false
    }
}

PasteURL(url) {
    WriteDebug("DEBUG: PasteURL called for: " . url)
    ; Paste URL into address bar without navigating
    Send("^l")  ; Ctrl+L to focus address bar
    Sleep(100)
    Send("^a")  ; Select all
    Sleep(100)
    ; Save the current clipboard content to a variable
    currentClipboard := A_Clipboard
    ; Put your URL into the clipboard
    A_Clipboard := url
    ; Send the paste command (Ctrl+V)
    Send "^v"
    Send("{Enter}")
    ; Optional: Restore the original clipboard content after a brief delay
    Sleep 50
    A_Clipboard := currentClipboard
    Sleep(100)
    WriteDebug("DEBUG: PasteURL completed, no status sent")
}

SearchWalmart(searchTerm) {
    ; Update status to show what user should do with urgent styling
    ShowPersistentStatus("Search results shown - find your item, then press Ctrl+Shift+A", true)
    
    ; Build search URL
    searchURL := "https://www.walmart.com/search?q=" . UriEncode(searchTerm)
    
    ; Go to address bar and search
    PasteURL(searchURL)
    ; Wait for search results
    Sleep(2000)
    
    ; Don't wait for user here - let the next command (SHOW_ITEM_PROMPT) handle user interaction
    ; No response needed - this is fire-and-forget
}

GetCurrentURL() {
    ; Select address bar content to get URL
    Send("^l")  ; Focus address bar
    Sleep(100)
    Send("^c")  ; Copy URL
    Sleep(100)
    
    ; Get URL from clipboard
    currentURL := A_Clipboard
    
    ; Clear clipboard
    A_Clipboard := ""
    
    SendURL(currentURL)
}

GetCurrentURLSilent() {
    ; Get current URL without writing to response file
    Send("^l")  ; Focus address bar
    Sleep(100)
    Send("^c")  ; Copy URL
    Sleep(100)
    
    ; Get URL from clipboard
    currentURL := A_Clipboard
    
    ; Clear clipboard
    A_Clipboard := ""
    
    return currentURL
}

ActivateBrowserCommand() {
    ; Since user manually switched to browser, just confirm it's active
    SendStatus("browser_active")
}

ShowMessage(param) {
    MsgBox(param, "Walmart Shopping Assistant", "OK")
    SendStatus("ok")
}

ShowItemPrompt(param) {
    ; Parse param: "item_name|is_known_item|url|description|item_description|default_quantity"
    parts := StrSplit(param, "|")
    item_name := parts[1]
    is_known := parts[2] = "true"
    url := parts.Length >= 3 ? parts[3] : ""
    description := parts.Length >= 4 ? parts[4] : ""
    item_description := parts.Length >= 5 ? parts[5] : item_name
    default_quantity := parts.Length >= 6 ? parts[6] : "1"
    
    ; Show the purchase dialog
    ShowPurchaseDialog(item_name, is_known, item_description, default_quantity)
}

NavigateAndShowDialog(param) {
    ; Parse param: "url|item_name|is_known_item|description|item_description|default_quantity|expected_product_id"
    parts := StrSplit(param, "|")
    url := parts[1]
    item_name := parts[2]
    is_known := parts[3] = "true"
    description := parts.Length >= 4 ? parts[4] : ""
    item_description := parts.Length >= 5 ? parts[5] : item_name
    default_quantity := parts.Length >= 6 ? parts[6] : "1"
    expected_product_id := parts.Length >= 7 ? parts[7] : "" ; New parameter
    
    FileAppend("NavigateAndShowDialog: Navigating to " . url . "`n", "command_debug.txt")
    
    ; Navigate to URL (background loading)
    WinActivate(TargetWindowHandle)
    WinWaitActive(TargetWindowHandle)
    A_Clipboard := "" ; Clear clipboard before navigation
    PasteURL(url)
    
    ; Wait for product data from browser extension via clipboard
    walmartProductData := WaitForClipboardJSON(20) ; Increased timeout for page load and script execution
    
    prefill_price := ""
    prefill_description := item_description ; Default to original item description
    prefill_out_of_stock := false
    
    if (walmartProductData) {
        FileAppend("NavigateAndShowDialog: Received product data from clipboard.`n", "command_debug.txt")
        
        extracted_product_id := walmartProductData.Has("productId") ? walmartProductData["productId"] : ""
        
        ; --- Product ID Validation ---
        if (expected_product_id != "" && extracted_product_id != "" && expected_product_id != extracted_product_id) {
            MsgBox("Warning: Product ID mismatch!" . "`nExpected: " . expected_product_id . "`nFound: " . extracted_product_id, "Product Mismatch", "IconExclamation")
            FileAppend("NavigateAndShowDialog: Product ID mismatch! Expected: " . expected_product_id . ", Found: " . extracted_product_id . "`n", "command_debug.txt")
        } else if (expected_product_id != "" && extracted_product_id == "") {
            MsgBox("Warning: Expected Product ID '" . expected_product_id . "' not found on page.", "Product ID Missing", "IconExclamation")
            FileAppend("NavigateAndShowDialog: Expected Product ID '" . expected_product_id . "' not found on page.`n", "command_debug.txt")
        }
        
        prefill_price := walmartProductData.Has("price") ? walmartProductData["price"] : ""
        prefill_out_of_stock := walmartProductData.Has("outOfStock") ? walmartProductData["outOfStock"] : false

        if (prefill_out_of_stock) {
            WriteDebug("Item is out of stock. Requesting alternatives from Ruby for item: " . item_name)
            
            response_obj := Map()
            response_obj["type"] := "out_of_stock_alternatives"
            response_obj["item_name"] := item_name
            WriteResponseJSON(response_obj)
            
            return ; Stop processing and do not show a dialog
        }
        
    } else {
        FileAppend("NavigateAndShowDialog: No valid Walmart product data received from clipboard within timeout. Showing dialog with default values.`n", "command_debug.txt")
        MsgBox("Could not retrieve product data from page. Please ensure browser extension is running.", "Data Retrieval Failed", "IconExclamation")
    }
    
    ; Show dialog with pre-filled data (or defaults if clipboard data failed)
    FileAppend("NavigateAndShowDialog: Showing dialog for " . item_name . " (known=" . is_known . ")`n", "command_debug.txt")
    ; The ShowPurchaseDialog signature needs to be updated to accept prefill_price, prefill_description, prefill_out_of_stock
    ShowPurchaseDialog(item_name, is_known, prefill_description, default_quantity, prefill_price, prefill_out_of_stock)
}

ShowPurchaseDialog(item_name, is_known, item_description, default_quantity, prefill_price := "", prefill_out_of_stock := false) {
    ; Create dialog
    purchaseGui := Gui("+AlwaysOnTop", "Item: " . item_name)
    purchaseGui.SetFont("s10")
    
    ; Item info
    if is_known {
        purchaseGui.Add("Text", "w400", "✅ Found saved item: " . item_name)
        purchaseGui.Add("Text", "w400", "Page should be loaded. Add to cart if desired.")
    } else {
        purchaseGui.Add("Text", "w400", "🔍 New item: " . item_name)
        purchaseGui.Add("Text", "w400", "Search results displayed. Navigate to correct product.")
    }
    
    purchaseGui.Add("Text", "xm y+15 w400", "Item: " . item_description)
    
    ; Price field
    if (prefill_price != "") {
        try {
            prefill_price := Format("{:.2f}", prefill_price)
        }
    }
    purchaseGui.Add("Text", "xm y+15", "Price (leave blank to skip):")
    priceEdit := purchaseGui.Add("Edit", "w150 r1", prefill_price) ; Use prefill_price
    purchaseGui.Add("Text", "x+5 yp+3", "$")
    
    ; Quantity field
    purchaseGui.Add("Text", "xm y+10", "Quantity:")
    quantityEdit := purchaseGui.Add("Edit", "w150 r1", default_quantity)
    
    ; New logic for Out of Stock
    if (prefill_out_of_stock) {
        purchaseGui.Add("Text", "xm y+5 w400 cRed", "⚠️ Item is Out of Stock!")
    }
    
    ; Buttons - Override button starts as warning state
    addButton := purchaseGui.Add("Button", "xm y+20 w120 h30 BackgroundRed cWhite", "⚠️ Override")
    skipButton := purchaseGui.Add("Button", "x+10 w100 h30", "Skip Item")
    searchButton := purchaseGui.Add("Button", "x+10 w100 h30", "Search Again")
    
    ; Store references for event handlers
    purchaseGui.priceEdit := priceEdit
    purchaseGui.quantityEdit := quantityEdit
    purchaseGui.is_known := is_known
    purchaseGui.item_description := item_description
    
    ; Button event handlers
    addButton.OnEvent("Click", (*) => PurchaseClickHandler(purchaseGui))
    skipButton.OnEvent("Click", (*) => SkipClickHandler(purchaseGui))
    searchButton.OnEvent("Click", (*) => SearchAgainClickHandler(purchaseGui))
    
    ; Store purchase button and price edit references globally for click detection
    global CurrentPurchaseButton := addButton
    global CurrentPriceEdit := priceEdit
    FileAppend("ShowPurchaseDialog: Set CurrentPriceEdit reference`n", "command_debug.txt")
    
    ; Clear any dialog references that might interfere with lookup
    global CurrentAddItemDialog := ""
    global CurrentDialogControls := ""
    
    ; Show dialog immediately 
    purchaseGui.Show("x100")

    ; Start purchase detection and price detection immediately
    ; Only start price detection if not pre-filled and not out of stock
    if (prefill_price == "" && !prefill_out_of_stock) {
        SetTimer(StartDetectionForPurchaseDialog.Bind(priceEdit), -100)  ; Run once after 100ms delay
    } else if (prefill_out_of_stock) {
        ; If out of stock, disable the Add/Override button visually
        addButton.Enabled := false
    }
}

; Event handler functions for Purchase dialog
PurchaseClickHandler(gui) {
    price := Trim(gui.priceEdit.Text)
    quantity := Trim(gui.quantityEdit.Text)
    
    ; Validate quantity
    if quantity = "" || !IsNumber(quantity) || Integer(quantity) < 1 {
        quantity := "1"
    }
    
    ; Check if price is valid
    if price = "" || price = "0" || price = "0.00" {
        ; No purchase, but for new items, still capture URL
        if !gui.is_known {
            current_url := GetCurrentURLSilent()
            response_obj := Map()
            response_obj["type"] := "save_url_only"
            response_obj["url"] := current_url
            WriteResponseJSON(response_obj)
        } else {
           SendStatus("skipped")
        }
    } else {
        ; Valid price entered - record purchase
        if !IsNumber(price) {
            MsgBox("Please enter a valid price (numbers only)", "Invalid Price")
            return
        }
        
        ; Create JSON response for purchase
        response_obj := Map()
        if !gui.is_known {
            ; For new items, also capture the URL
            current_url := GetCurrentURLSilent()
            response_obj["type"] := "purchase_new"
            response_obj["price"] := Float(price)
            response_obj["quantity"] := Integer(quantity)
            response_obj["url"] := current_url
        } else {
            response_obj["type"] := "purchase"
            response_obj["price"] := Float(price)
            response_obj["quantity"] := Integer(quantity)
        }
        WriteResponseJSON(response_obj)
    }
    
    StopPriceDetection()
    gui.Destroy()
}

SkipClickHandler(gui) {
    ; Skip purchase, but for new items, still capture URL
    if !gui.is_known {
        response_obj := Map()
        current_url := GetCurrentURLSilent()
        response_obj["type"] := "save_url_only"
        response_obj["url"] := current_url
        WriteResponseJSON(response_obj)
    } else {
        SendStatus("skipped")
    }
    
    StopPriceDetection()
    gui.Destroy()
}

SearchAgainClickHandler(gui) {
    ; User wants to search for alternatives - return like selecting "search for new item" in multi-choice
    response_obj := Map()
    response_obj["type"] := "choice"
    response_obj["value"] := 999  ; Use high number to indicate "search for new item" option
    WriteResponseJSON(response_obj)
    StopPriceDetection()
    gui.Destroy()
}

GetCurrentURLAndRespond(responsePrefix) {
    ; DEPRECATED: This function should not be used anymore - all responses should be JSON
    ; Get current URL from browser (silent)
    current_url := GetCurrentURLSilent()
    
    ; Convert to JSON format
    response_obj := Map()
    if responsePrefix = "save_url_only" {
        response_obj["type"] := "save_url_only"
        response_obj["url"] := current_url
    } else {
        response_obj["type"] := responsePrefix
        response_obj["url"] := current_url
    }
    WriteResponseJSON(response_obj)
}

ShowMultipleChoice(param) {
    ; Parse param: "title|allow_skip|option1|option2|..."
    parts := StrSplit(param, "|")
    title := parts[1]
    allow_skip := parts[2] = "true"
    
    ; Build option list
    options := []
    loop parts.Length - 2 {
        options.Push(parts[A_Index + 2])
    }
    
    ; Build message text
    message := title . "`n`nPlease select an option:`n`n"
    loop options.Length {
        message .= A_Index . ". " . options[A_Index] . "`n"
    }
    
    if allow_skip {
        message .= "`nEnter the number (1-" . options.Length . ") or leave blank to skip:"
    } else {
        message .= "`nEnter the number (1-" . options.Length . "):"
    }
    
    ; Show input dialog
    result := InputBox(message, "Multiple Matches", "w600 h400")
    
    if result.Result = "OK" {
        choice_text := Trim(result.Value)
        
        if choice_text = "" && allow_skip {
            SendStatus("skipped")
        } else {
            ; Validate numeric choice
            try {
                choice_num := Integer(choice_text)
                if choice_num >= 1 && choice_num <= options.Length {
                    SendChoice(choice_num)
                } else {
                    SendStatus("cancelled")
                }
            } catch {
                SendStatus("cancelled")
            }
        }
    } else {
        SendStatus("cancelled")
    }
}

GetPriceInput() {
    result := InputBox("Enter the current price (e.g., 3.45):", "Record Price", "w300 h150")
    
    if result.Result = "OK" && result.Value != "" {
        response_obj := Map()
        response_obj["type"] := "price"
        response_obj["value"] := Float(result.Value)
        WriteResponseJSON(response_obj)
    } else {
        SendStatus("cancelled")
    }
}

UriEncode(str) {
    str := StrReplace(str, " ", "%20")
    str := StrReplace(str, "&", "%26")
    str := StrReplace(str, "?", "%3F")
    str := StrReplace(str, "#", "%23")
    return str
}

WriteStatus(status) {
    try {
        if FileExist(StatusFile)
            FileDelete(StatusFile)
        FileAppend(status, StatusFile)
    } catch as e {
        MsgBox("WriteStatus Error: " . e.Message)
    }
}

WriteResponseJSON(response_obj) {
    try {
        ; Try jsongo first
        json_response := jsongo.Stringify(response_obj)
    } catch {
        ; Manual JSON fallback
        json_parts := []
        for key, value in response_obj {
            if (IsNumber(value)) {
                json_parts.Push('"' . key . '": ' . value)
            } else {
                ; Escape quotes and backslashes in string values
                escaped_value := StrReplace(StrReplace(String(value), '\', '\\'), '"', '\"')
                json_parts.Push('"' . key . '": "' . escaped_value . '"')
            }
        }
        json_response := '{' . json_parts.Join(', ') . '}'
    }
    
    ; Write to response file
    try {
        if FileExist(ResponseFile)
            FileDelete(ResponseFile)
        FileAppend(json_response, ResponseFile, "UTF-8-RAW")
    } catch as e {
        ; Fallback error handling
        if FileExist(ResponseFile)
            FileDelete(ResponseFile)
        FileAppend("ERROR: " . e.message, ResponseFile)
    }
}

; Helper function for status responses
SendStatus(statusValue) {
    response_obj := Map()
    response_obj["type"] := "status"
    response_obj["value"] := statusValue
    WriteResponseJSON(response_obj)
}

; Helper function for choice responses
SendChoice(choiceValue) {
    response_obj := Map()
    response_obj["type"] := "choice"
    response_obj["value"] := choiceValue
    WriteResponseJSON(response_obj)
}

; Helper function for URL responses
SendURL(urlValue) {
    response_obj := Map()
    response_obj["type"] := "url"
    response_obj["value"] := urlValue
    WriteResponseJSON(response_obj)
}

; Helper function for error responses
SendError(errorValue) {
    response_obj := Map()
    response_obj["type"] := "error"
    response_obj["value"] := errorValue
    WriteResponseJSON(response_obj)
}

; --- Clipboard Data Handling Functions ---
WaitForClipboardJSON(timeoutSeconds := 10) {
    startTime := A_TickCount
    clipboardData := ""
    
    Loop {
        clipboardData := A_Clipboard
        ; Check if clipboard is not empty and starts with JSON marker
        if (clipboardData != "" && SubStr(clipboardData, 1, 1) = "{" && InStr(clipboardData, "`"walmart_product`":true")) {
            try {
                parsedData := jsongo.Parse(clipboardData)
                ; Double check the marker
                if (parsedData.Has("walmart_product") && parsedData["walmart_product"] = true) {
                    WriteDebug("WaitForClipboardJSON: Successfully parsed Walmart product data from clipboard.")
                    return parsedData
                }
            } catch as e {
                ; Not valid JSON or not our expected format yet, continue waiting
                WriteDebug("WaitForClipboardJSON: Clipboard contains non-walmart JSON or malformed JSON: " . e.message)
            }
        }
        
        Sleep(500) ; Wait 500ms before checking again
        
        if ((A_TickCount - startTime) / 1000 > timeoutSeconds) {
            WriteDebug("WaitForClipboardJSON: Timeout waiting for valid Walmart product data in clipboard.")
            return false
        }
    }
}

WriteResponse(response) {
    try {
        ; Delete existing response file
        if FileExist(ResponseFile)
            FileDelete(ResponseFile)
        ; Write response as plain text
        FileAppend(response, ResponseFile, "UTF-8-RAW")
    } catch as e {
        ; If file operations fail, try one more time
        try {
            if FileExist(ResponseFile)
                FileDelete(ResponseFile)
            FileAppend("ERROR: " . e.message, ResponseFile)
        } catch {
            ; Silent failure - don't crash the script
        }
    }
}

; Reset state after shopping list completion
ResetForNextSession() {
    global UserReady
    UserReady := false
    ; Tooltip is already set by ProcessSessionComplete, don't override it
}


; Shopping list processing complete
ProcessSessionComplete() {
    FileAppend("ProcessSessionComplete called - setting completion tooltip`n", "command_debug.txt")
    WriteDebug("DEBUG: ProcessSessionComplete sending ready status")
    ShowPersistentStatus("Shopping list complete! Press Ctrl+Shift+A to add items or Ctrl+Shift+Q to quit")
    ResetForNextSession()
    SendStatus("ready")
}



; Add Item Dialog Functions
ShowAddItemDialog(suggestedName) {
    ; Get current URL
    currentUrl := GetCurrentURL()
    
    ; Show the add item dialog
    ShowAddItemDialogWithDefaults(suggestedName, currentUrl)
}

ShowAddItemDialogHotkey() {
    WriteDebug("ShowAddItemDialogHotkey called")
    
    ; Get current URL (silent - doesn't write to response file)
    currentUrl := GetCurrentURLSilent()
    WriteDebug("Current URL captured: " . currentUrl)
    
    ; Try to get data from browser extension first
    A_Clipboard := "" ; Clear clipboard before checking
    walmartProductData := WaitForClipboardJSON(5) ; Wait 5s for extension data

    if (walmartProductData) {
        WriteDebug("ShowAddItemDialogHotkey: Received product data from clipboard.")
        prefill_price := walmartProductData.Has("price") ? walmartProductData["price"] : ""
        prefill_description := walmartProductData.Has("description") ? walmartProductData["description"] : ""
        
        ; Show dialog with pre-filled values from clipboard
        ShowAddItemDialogWithDefaults(prefill_description, currentUrl, prefill_price)
    } else {
        WriteDebug("ShowAddItemDialogHotkey: No clipboard data. Falling back to Ruby lookup.")
        ; Original fallback logic: Show dialog and ask Ruby for info
        ShowAddItemDialogWithDefaults("< Looking up... >", currentUrl)
        SendLookupRequest(currentUrl)
    }
}

EditPurchaseHotkey() {
    WriteDebug("EditPurchaseHotkey called - sending EDIT_PURCHASE_WORKFLOW to Ruby")
    response_obj := Map()
    response_obj["type"] := "edit_purchase_workflow"
    response_obj["value"] := "initiated"
    WriteResponseJSON(response_obj)
}

ShowAddItemDialogWithDefaults(suggestedName, currentUrl, prefill_price := "") {
    ; Create dialog
    addItemGui := Gui("+AlwaysOnTop", "Add Item & Purchase")
    addItemGui.SetFont("s10")
    
    ; Store reference to dialog globally IMMEDIATELY
    global CurrentAddItemDialog := addItemGui
    global CurrentDialogControls := ""  ; Initialize to prevent race condition
    
    ; Description field
    addItemGui.Add("Text", , "Item Description (leave blank for purchase-only):")
    descriptionEdit := addItemGui.Add("Edit", "w400 r1", suggestedName)
    
    ; Modifier field  
    addItemGui.Add("Text", "xm y+10", "Modifier (optional):")
    modifierEdit := addItemGui.Add("Edit", "w400 r1", "")
    
    ; Priority field
    addItemGui.Add("Text", "xm y+10", "Priority (1=highest):")
    priorityEdit := addItemGui.Add("Edit", "w100 r1", "1")
    
    ; Default quantity field
    addItemGui.Add("Text", "xm y+10", "Default Quantity:")
    defaultQuantityEdit := addItemGui.Add("Edit", "w100 r1", "1")
    
    ; Separator
    addItemGui.Add("Text", "xm y+15 w400", "────────────── Purchase Info ──────────────")
    
    ; Price field for this purchase
    addItemGui.Add("Text", "xm y+10", "Purchase Price (leave blank to skip purchase):")
    
    if (prefill_price != "") {
        try {
            prefill_price := Format("{:.2f}", prefill_price)
        }
    }
    priceEdit := addItemGui.Add("Edit", "w150 r1", prefill_price)
    addItemGui.Add("Text", "x+5 yp+3", "$")
    
    ; Purchase quantity field
    addItemGui.Add("Text", "xm y+10", "Purchase Quantity:")
    purchaseQuantityEdit := addItemGui.Add("Edit", "w100 r1", "1")
    
    ; URL display (read-only)
    addItemGui.Add("Text", "xm y+15", "URL (auto-captured):")
    urlEdit := addItemGui.Add("Edit", "w400 r2 ReadOnly", currentUrl)
    
    ; Buttons - Override button starts as warning state
    addButton := addItemGui.Add("Button", "xm y+15 w120 h30 BackgroundRed cWhite", "⚠️ Override")
    addOnlyButton := addItemGui.Add("Button", "x+10 w100 h30", "Add Only")
    skipButton := addItemGui.Add("Button", "x+10 w100 h30", "Skip Item")
    cancelButton := addItemGui.Add("Button", "x+10 w100 h30", "Cancel")
    
    ; Make variables accessible to event handlers
    addItemGui.descriptionEdit := descriptionEdit
    addItemGui.modifierEdit := modifierEdit
    addItemGui.priorityEdit := priorityEdit
    addItemGui.defaultQuantityEdit := defaultQuantityEdit
    addItemGui.priceEdit := priceEdit
    addItemGui.purchaseQuantityEdit := purchaseQuantityEdit
    addItemGui.currentUrl := currentUrl
    
    ; Store control references globally for lookup updates IMMEDIATELY
    global CurrentDialogControls := {
        descriptionEdit: descriptionEdit,
        modifierEdit: modifierEdit,
        priorityEdit: priorityEdit,
        defaultQuantityEdit: defaultQuantityEdit,
        quantityEdit: purchaseQuantityEdit
    }
    
    ; Button event handlers
    addButton.OnEvent("Click", (*) => AddAndPurchaseClickHandler(addItemGui))
    addOnlyButton.OnEvent("Click", (*) => AddOnlyClickHandler(addItemGui))
    skipButton.OnEvent("Click", (*) => SkipItemClickHandler(addItemGui))
    cancelButton.OnEvent("Click", (*) => CancelItemClickHandler(addItemGui))
    
    ; Store purchase button and price edit references globally for click detection
    global CurrentPurchaseButton := addButton
    global CurrentPriceEdit := priceEdit
    WriteDebug("ShowAddItemDialog: Set CurrentPriceEdit reference")
    
    ; Add cleanup handler when dialog is closed
    addItemGui.OnEvent("Close", (*) => CleanupDialogReferences())
    
    ; Show dialog immediately (positioned 400px left of center)
    dialogX := 100 
    addItemGui.Show("x" . dialogX)

    ; Start purchase detection and price detection immediately
    SetTimer(StartDetectionForAddItemDialog.Bind(priceEdit), -100)  ; Run once after 100ms delay
}

; Event handler functions for Add Item dialog
AddAndPurchaseClickHandler(gui) {
    description := Trim(gui.descriptionEdit.Text)
    modifier := Trim(gui.modifierEdit.Text)
    priority := Trim(gui.priorityEdit.Text)
    defaultQuantity := Trim(gui.defaultQuantityEdit.Text)
    price := Trim(gui.priceEdit.Text)
    purchaseQuantity := Trim(gui.purchaseQuantityEdit.Text)
    
    ; Validate description (allow empty for purchase-only mode)
    if StrLen(description) > 255 {
        MsgBox("Description too long (max 255 characters)", "Error")
        return
    }
    
    ; If description is empty, this is purchase-only mode - require price
    if description = "" && price = "" {
        MsgBox("For purchase-only mode (empty description), you must enter a price!", "Price Required")
        return
    }
    
    ; Validate modifier
    if StrLen(modifier) > 100 {
        MsgBox("Modifier too long (max 100 characters)", "Error")
        return
    }
    
    ; Validate priority (1-10 range)
    if priority = "" || !IsNumber(priority) || Integer(priority) < 1 || Integer(priority) > 10 {
        priority := "1"
    }
    
    ; Validate default quantity (1-999 range)
    if defaultQuantity = "" || !IsNumber(defaultQuantity) || Integer(defaultQuantity) < 1 || Integer(defaultQuantity) > 999 {
        defaultQuantity := "1"
    }
    
    ; Validate purchase quantity (1-999 range)
    if purchaseQuantity = "" || !IsNumber(purchaseQuantity) || Integer(purchaseQuantity) < 1 || Integer(purchaseQuantity) > 999 {
        purchaseQuantity := "1"
    }
    
    ; Validate price if provided (max $9999.99)
    if price != "" {
        if !IsNumber(price) || Float(price) < 0 || Float(price) > 9999.99 {
            MsgBox("Please enter a valid price between $0.00 and $9999.99", "Invalid Price")
            return
        }
    }
    
    ; Ensure we have a valid URL - capture current if empty or invalid
    currentUrl := gui.currentUrl
    if (currentUrl = "" || !InStr(currentUrl, "walmart.com")) {
        currentUrl := GetCurrentURLSilent()
        FileAppend("Captured fresh URL: " . currentUrl . "`n", "command_debug.txt")
    }
    
    ; Create JSON response with purchase info
    response_obj := Map()
    response_obj["type"] := "add_and_purchase"
    response_obj["description"] := description
    response_obj["modifier"] := modifier
    response_obj["priority"] := Integer(priority)
    response_obj["default_quantity"] := Integer(defaultQuantity)
    response_obj["url"] := currentUrl
    response_obj["price"] := price != "" ? Float(price) : ""
    response_obj["purchase_quantity"] := Integer(purchaseQuantity)
    
    WriteResponseJSON(response_obj)
    StopPriceDetection()
    CleanupDialogReferences()
    gui.Destroy()
    
    ; Show confirmation
    MsgBox("Item '" . description . "' has been sent to Ruby for processing!", "Item Added", "OK")
}

AddOnlyClickHandler(gui) {
    description := Trim(gui.descriptionEdit.Text)
    modifier := Trim(gui.modifierEdit.Text)
    priority := Trim(gui.priorityEdit.Text)
    defaultQuantity := Trim(gui.defaultQuantityEdit.Text)
    
    ; Validate description (required for Add Only)
    if description = "" {
        MsgBox("Description is required for Add Only mode!", "Error")
        return
    }
    if StrLen(description) > 255 {
        MsgBox("Description too long (max 255 characters)", "Error")
        return
    }
    
    ; Validate modifier
    if StrLen(modifier) > 100 {
        MsgBox("Modifier too long (max 100 characters)", "Error")
        return
    }
    
    ; Validate priority (1-10 range)
    if priority = "" || !IsNumber(priority) || Integer(priority) < 1 || Integer(priority) > 10 {
        priority := "1"
    }
    
    ; Validate default quantity (1-999 range)
    if defaultQuantity = "" || !IsNumber(defaultQuantity) || Integer(defaultQuantity) < 1 || Integer(defaultQuantity) > 999 {
        defaultQuantity := "1"
    }
    
    ; Ensure we have a valid URL - capture current if empty or invalid
    currentUrl := gui.currentUrl
    if (currentUrl = "" || !InStr(currentUrl, "walmart.com")) {
        currentUrl := GetCurrentURLSilent()
        FileAppend("Captured fresh URL: " . currentUrl . "`n", "command_debug.txt")
    }
    
    ; Create JSON response
    response_obj := Map()
    response_obj["type"] := "add_and_purchase" ; Use same type as add_and_purchase
    response_obj["description"] := description
    response_obj["modifier"] := modifier
    response_obj["priority"] := Integer(priority)
    response_obj["default_quantity"] := Integer(defaultQuantity)
    response_obj["url"] := currentUrl
    response_obj["price"] := "" ; Empty price indicates "add only"
    response_obj["purchase_quantity"] := 0

    WriteResponseJSON(response_obj)
    StopPriceDetection()
    CleanupDialogReferences()
    gui.Destroy()
    
    ; Show confirmation
    MsgBox("Item '" . description . "' has been sent to Ruby for processing!", "Item Added", "OK")
}

SkipItemClickHandler(gui) {
    SendStatus("skipped")
    StopPriceDetection()
    CleanupDialogReferences()
    gui.Destroy()
}

CancelItemClickHandler(gui) {
    SendStatus("cancelled")
    StopPriceDetection()
    CleanupDialogReferences()
    ; Silent close - no messages
    gui.Destroy()
}

; Create a persistent status window
ShowPersistentStatus(message, isUrgent := false) {
    global StatusGui
    
    ; Close existing status window if any
    if StatusGui != "" {
        try {
            StatusGui.Destroy()
        }
    }
    
    ; Create a new status GUI with styling based on urgency
    StatusGui := Gui("+AlwaysOnTop", "Assistant Status")
    StatusGui.SetFont("s10")
    
    ; Set background color based on urgency
    if isUrgent {
        ; Urgent: Orange/amber background for "pay attention"
        StatusGui.BackColor := 0xFFA500  ; Orange
        textColor := 0x000000  ; Black text for contrast
    } else {
        ; Normal: Default system colors (no custom background)
        ; StatusGui will use default window background
        textColor := 0x000000  ; Black text (default)
    }
    
    ; Add status text (taller to accommodate more text)
    statusText := StatusGui.Add("Text", "x20 y15 w400 h140 Center", message)
    statusText.Opt("+c" . Format("{:06x}", textColor))  ; Set text color
    
    ; Add Quit button
    quitButton := StatusGui.Add("Button", "x180 y60 w80 h30", "Quit")
    quitButton.OnEvent("Click", (*) => PerformQuit())
    
    ; Position in top-right corner with more margin (100px taller)
    StatusGui.Show("x" . (A_ScreenWidth - 900) . " y80 w440 h120 NoActivate")
    
    ; Make it stay on top but not steal focus
    WinSetAlwaysOnTop(1, StatusGui.Hwnd)
}

; Function to silently close all dialogs
CloseAllDialogs() {
    global StatusGui
    
    ; Close all open GUIs by enumerating them
    try {
        ; Get all top-level windows belonging to this process
        WinGetList("", , , "ahk_pid " . ProcessExist())
        Loop {
            try {
                ; Try to find and close any remaining GUI windows
                if WinExist("Add Item & Purchase ahk_pid " . ProcessExist()) {
                    WinClose("Add Item & Purchase ahk_pid " . ProcessExist())
                }
                if WinExist("Purchase Item ahk_pid " . ProcessExist()) {
                    WinClose("Purchase Item ahk_pid " . ProcessExist())
                }
                if WinExist("Select Item ahk_pid " . ProcessExist()) {
                    WinClose("Select Item ahk_pid " . ProcessExist())
                }
                break
            } catch {
                break
            }
        }
    } catch {
        ; Ignore errors during cleanup
    }
    
    ; Close status window
    if StatusGui != "" {
        try {
            StatusGui.Destroy()
        } catch {
            ; Ignore errors
        }
    }
}

; Shared quit functionality
PerformQuit() {
    ; Silently close all dialogs
    CloseAllDialogs()
    
    ; Tell Ruby we're quitting using JSON format
    SendStatus("quit")
    ; Remove MsgBox - silent shutdown
    ExitApp()
}

; Purchase Detection Functions
StartPurchaseDetection() {
    global ButtonRegion, ButtonFound
    
    FileAppend("StartPurchaseDetection called`n", "command_debug.txt")
    
    ; Reset for new page
    ButtonFound := false
    
    ; Small delay for page loading before searching
    FileAppend("About to call FindAddToCartButton`n", "command_debug.txt")
    ; Search for Add to Cart button on page  
    result := FindAddToCartButton(5000, TargetWindowHandle)  ; 5 second search
    
    FileAppend("FindAddToCartButton returned: found=" . result.found . "`n", "command_debug.txt")
    
    if (result.found) {
        ButtonRegion := result.clickRegion
        ButtonFound := true
        FileAppend("Button found! Region set to: " . ButtonRegion.left . "," . ButtonRegion.top . " to " . ButtonRegion.right . "," . ButtonRegion.bottom . "`n", "command_debug.txt")
        FileAppend("DETECTION STATE: ButtonFound=" . ButtonFound . ", CurrentPurchaseButton=" . (CurrentPurchaseButton ? "SET" : "NOT SET") . "`n", "command_debug.txt")
    } else {
        FileAppend("Button NOT found`n", "command_debug.txt")
        FileAppend("DETECTION STATE: ButtonFound=false, CurrentPurchaseButton=" . (CurrentPurchaseButton ? "SET" : "NOT SET") . "`n", "command_debug.txt")
    }
    ; If not found, ButtonFound stays false - user can click Override
}

; Global click handler for purchase detection
~LButton:: {
    global ButtonRegion, ButtonFound, CurrentPurchaseButton
    
    ; Get click position for logging
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    
    ; Debug: Always log clicks to see if hotkey is working
    FileAppend("CLICK HOTKEY: Mouse click detected at " . mouseX . "," . mouseY . "`n", "command_debug.txt")
    
    ; Debug: Log all clicks when button detection is active
    if (ButtonFound && CurrentPurchaseButton) {
        FileAppend("CLICK DEBUG: Mouse click at " . mouseX . "," . mouseY . " - ButtonFound=" . ButtonFound . "`n", "command_debug.txt")
        FileAppend("CLICK DEBUG: Button region " . ButtonRegion.left . "," . ButtonRegion.top . " to " . ButtonRegion.right . "," . ButtonRegion.bottom . "`n", "command_debug.txt")
        
        ; Check if click is in Add to Cart button region
        inRegion := (mouseX >= ButtonRegion.left && mouseX <= ButtonRegion.right && 
                     mouseY >= ButtonRegion.top && mouseY <= ButtonRegion.bottom)
        
        FileAppend("CLICK DEBUG: inRegion=" . inRegion . "`n", "command_debug.txt")
        
        if (inRegion) {
            FileAppend("CLICK DEBUG: Add to Cart click detected! Updating button state`n", "command_debug.txt")
            
            ; Change button state
            CurrentPurchaseButton.Text := "✅ Add & Purchase"
            CurrentPurchaseButton.Opt("BackgroundGreen cWhite")
            
            ; Price detection already started when dialog opened
            ; Just update button appearance to confirm cart addition
            FileAppend("Add to Cart click detected - price detection already active`n", "command_debug.txt")
        }
    } else {
        ; Debug: Log when click detection is not active
        if (!ButtonFound) {
            FileAppend("CLICK DEBUG: Click ignored - ButtonFound=false`n", "command_debug.txt")
        } else if (!CurrentPurchaseButton) {
            FileAppend("CLICK DEBUG: Click ignored - CurrentPurchaseButton not set`n", "command_debug.txt")
        }
    }
}

; Function to find browser and open new Walmart tab
FindAndOpenWalmart() {
    ; Try to find any common browser window
    browserHandle := WinExist('Baseline')
    if browserHandle {
        ; Set global handle for OpenURL to use
        global TargetWindowHandle := browserHandle

        ; Activate browser
        WinActivate(browserHandle)
        WinWaitActive(browserHandle, , 2)

        ; Open new tab
        Send("^t")  ; Ctrl+T for new tab
        Sleep(500)

        ; Use OpenURL to navigate to Walmart (without Ruby messaging)
        try {
            PasteURL("https://walmart.com")
            Sleep(2000)  ; Wait for page to start loading
            FileAppend("Successfully opened Walmart tab`n", "command_debug.txt")
            return browserHandle
        } catch as e {
            FileAppend("Failed to navigate to Walmart: " . e.message . "`n", "command_debug.txt")
            MsgBox("Failed to open Walmart page in browser. Please try manually opening walmart.com")
            return 0
        }
    }

    FileAppend("No browser windows found`n", "command_debug.txt")
    return 0
}

; Helper functions for timer callbacks
StartDetectionForPurchaseDialog(priceEdit) {
    StartPurchaseDetection()
    StartPriceDetection(priceEdit)
}

StartDetectionForAddItemDialog(priceEdit) {
    StartPurchaseDetection()
    StartPriceDetection(priceEdit)
}

; Price Detection Functions
StartPriceDetection(priceEditControl) {
    global PriceDetectionTimer, PriceDetectionActive, CurrentPriceEdit, PriceDetectionStartTime
    
    FileAppend("StartPriceDetection called`n", "command_debug.txt")
    
    ; Stop any existing price detection
    StopPriceDetection()
    
    ; Set up new price detection
    CurrentPriceEdit := priceEditControl
    PriceDetectionActive := true
    PriceDetectionStartTime := A_TickCount  ; Record start time in milliseconds
    
    ; Start timer to check for prices every 500ms
    PriceDetectionTimer := SetTimer(() => CheckForPrice(), 500)
    
    FileAppend("Price detection timer started - will stop after 4 seconds`n", "command_debug.txt")
}

StopPriceDetection() {
    global PriceDetectionTimer, PriceDetectionActive
    
    if (PriceDetectionTimer) {
        SetTimer(PriceDetectionTimer, 0)  ; Stop timer
        PriceDetectionTimer := ""
        FileAppend("Price detection timer stopped`n", "command_debug.txt")
    }
    
    PriceDetectionActive := false
    ; Note: Don't clear CurrentPriceEdit here - let new dialogs set it when they open
}

CheckForPrice() {
    global CurrentPriceEdit, PriceDetectionActive, PriceDetectionStartTime
    
    ; Stop if detection is no longer active or dialog closed
    if (!PriceDetectionActive || !CurrentPriceEdit) {
        StopPriceDetection()
        return
    }
    
    ; Check if 4 seconds have elapsed (4000 milliseconds)
    elapsedTime := A_TickCount - PriceDetectionStartTime
    if (elapsedTime > 4000) {
        FileAppend("Price detection timeout after 4 seconds - stopping detection`n", "command_debug.txt")
        StopPriceDetection()
        return
    }
    
    ; Check if user has manually entered a price - if so, stop detection
    currentText := Trim(CurrentPriceEdit.Text)
    if (currentText != "") {
        FileAppend("User entered price manually: '" . currentText . "' - stopping detection`n", "command_debug.txt")
        StopPriceDetection()
        return
    }
    
    ; Search for price on screen using same region as test script (right 25% of screen)
    screenWidth := A_ScreenWidth
    screenHeight := A_ScreenHeight
    
    ; Define search area: right 25%, vertically 25-75%
    x1 := Floor(screenWidth * 0.75)
    x2 := screenWidth
    y1 := Floor(screenHeight * 0.25)
    y2 := Floor(screenHeight * 0.75)
    
    ; Try to extract price - measure this specific OCR call
    ocrStartTime := A_TickCount
    price := get_price(x1, y1, x2, y2)
    ocrDuration := A_TickCount - ocrStartTime
    
    if (price && price != "") {
        FileAppend("SUCCESS: Price detected '" . price . "' - OCR took " . ocrDuration . "ms on this iteration - filling in field`n", "command_debug.txt")
        
        ; Fill in the price field
        try {
            CurrentPriceEdit.Text := Format("{:.2f}", price)
        } catch {
            CurrentPriceEdit.Text := price
        }
        
        ; Stop detection since we found a price
        StopPriceDetection()
    }
}

; Subscribe pattern detection functions
LoadSubscribePattern() {
    ; Load the subscribe pattern for FindText detection
    global SubscribePattern
    SubscribePattern := "|<subscribe>*163$135.00s0000000000000000000003U000000000000000000000A0000000000000000000001k0000000000M00000000006000000TU00300000001k00k00000Dz000M0000000C007000003UM00300000000000M00000M0000M0000000000300000300003303U0E00000M00000M030MNy1zUzlbC00300000300M33MsQAD6Btk00M00000S030MQ3X03U1sC003000001zUM33UAs0M0C1k00M000003z30MM1n0301kC0030000000sM330CTUs0A1k00s0000003X0MM1kz701UC0060000000AM330C0wM0A1k00k0000001X0MM1U1X01UC00C0000000AM73UA0CQ0A1k01U00000M33UsS3U1Vk1UC00Q000003zsDv3Tsyw7yA1k07000000Dy0yMNy1z0TlUC00s000000000000000000000C0000000000000000000003U00000000000000000004"
    FileAppend("Subscribe pattern loaded for auto-detection`n", "command_debug.txt")
}

DetectSubscribable() {
    ; Auto-detect if item is subscribable by looking for subscribe pattern on page
    global SubscribePattern, TargetWindowHandle
    
    FileAppend("DetectSubscribable: Starting subscribe pattern detection`n", "command_debug.txt")
    
    ; Ensure browser window is active for consistent detection
    try {
        if (TargetWindowHandle) {
            WinActivate(TargetWindowHandle)
            WinWaitActive(TargetWindowHandle, , 2)
        }
    } catch as e {
        FileAppend("DetectSubscribable: Could not activate window - " . e.Message . "`n", "command_debug.txt")
    }
    
    ; Search same area as price detection (right 25% of screen, vertically 25-75%)
    screenWidth := A_ScreenWidth  
    screenHeight := A_ScreenHeight
    
    ; Define search area: right 25%, vertically 25-75% (same as price detection)
    x1 := Floor(screenWidth * 0.75)
    x2 := screenWidth
    y1 := Floor(screenHeight * 0.25)
    y2 := Floor(screenHeight * 0.75)
    
    FileAppend("DetectSubscribable: Searching region " . x1 . "," . y1 . " to " . x2 . "," . y2 . " (same as price detection)`n", "command_debug.txt")
    
    ; Use FindText to detect subscribe pattern with moderate tolerance
    X := ""
    Y := ""
    result := FindText(&X, &Y, x1, y1, x2, y2, 0, 0, SubscribePattern)
    
    if (result) {
        FileAppend("DetectSubscribable: FOUND subscribe pattern - item is subscribable`n", "command_debug.txt")
        return true
    } else {
        FileAppend("DetectSubscribable: Subscribe pattern NOT found - item is not subscribable`n", "command_debug.txt") 
        return false
    }
}

; Send lookup request to Ruby
SendLookupRequest(url) {
    WriteDebug("Sending lookup request for URL: " . url)
    
    try {
        ; Use existing WriteResponse with lookup request format
        response_obj := Map()
        response_obj["type"] := "lookup_request" 
        response_obj["url"] := url
        WriteResponseJSON(response_obj)
        WriteDebug("Lookup request written to response file")
    } catch as e {
        WriteDebug("Failed to write lookup request: " . e.message)
    }
}



; Global reference to current dialog for lookup updates
CurrentAddItemDialog := ""
CurrentDialogControls := ""

; Clean up global dialog references
CleanupDialogReferences() {
    CurrentAddItemDialog := ""
    CurrentDialogControls := ""
    WriteDebug("Dialog references cleaned up")
}

ShowPurchaseSearchDialogAHK() {
    searchGui := Gui("+AlwaysOnTop", "Search Purchases")
    searchGui.SetFont("s10")

    searchGui.Add("Text", , "Search Term (item name or ID):")
    searchTermEdit := searchGui.Add("Edit", "w300 r1")

    searchGui.Add("Text", "xm y+10", "Start Date (YYYY-MM-DD, optional):")
    startDateEdit := searchGui.Add("Edit", "w150 r1")

    searchGui.Add("Text", "xm y+10", "End Date (YYYY-MM-DD, optional):")
    endDateEdit := searchGui.Add("Edit", "w150 r1")

    findButton := searchGui.Add("Button", "xm y+20 w100 h30", "Find")
    cancelButton := searchGui.Add("Button", "x+10 w100 h30", "Cancel")

    findButton.OnEvent("Click", (*) => FindPurchasesClickHandler(searchGui, searchTermEdit, startDateEdit, endDateEdit))
    cancelButton.OnEvent("Click", (*) => CancelSearchClickHandler(searchGui))
    searchGui.OnEvent("Close", (*) => CancelSearchClickHandler(searchGui))

    searchGui.Show("x" . (A_ScreenWidth / 2 - 200) . " y" . (A_ScreenHeight / 2 - 150))
}

ShowPurchaseSelectionDialogAHK(jsonParam) {
    purchases := jsongo.Parse(jsonParam)

    selectionGui := Gui("+AlwaysOnTop", "Select Purchase")
    selectionGui.SetFont("s10")

    selectionGui.Add("Text", "w400", "Select a purchase to edit or delete:")

    yPos := "y+5"
    if (purchases.Length > 0) {
        loop purchases.Length {
            purchase := purchases[A_Index]
            itemDesc := purchase["item_description"]
            purchaseDate := SubStr(purchase["purchase_date"], 1, 10) ; YYYY-MM-DD
            quantity := purchase["quantity"]
            price := Format("{:.2f}", purchase["price_cents"] / 100)

            display_text := Format("{} - {}x ${} on {}", itemDesc, quantity, price, purchaseDate)
            selectionGui.Add("Text", "xm " . yPos . " w300", display_text)
            
            btn := selectionGui.Add("Button", "x+5 w80 h25", "Select")
            btn.purchaseId := purchase["id"]
            btn.OnEvent("Click", SelectPurchase_OnClick)

            yPos := "y+5"
        }
    } else {
        selectionGui.Add("Text", "xm " . yPos . " w400", "No purchases found. You can add a new one.")
    }

    selectionGui.Add("Button", "xm y+20 w120 h30", "New Purchase").OnEvent("Click", (*) => NewPurchaseClickHandler(selectionGui))
    selectionGui.Add("Button", "x+10 w100 h30", "Cancel").OnEvent("Click", (*) => CancelSelectionClickHandler(selectionGui))
    selectionGui.OnEvent("Close", (*) => CancelSelectionClickHandler(selectionGui))

    selectionGui.Show("x" . (A_ScreenWidth / 2 - 250) . " y" . (A_ScreenHeight / 2 - 200))
}

SelectPurchase_OnClick(btn, info) {
    id := btn.purchaseId
    SelectPurchaseClickHandler(btn.Gui, id)
}

ShowEditablePurchaseDialogAHK(jsonParam) {
    purchaseData := jsongo.Parse(jsonParam)
    isNewPurchase := !purchaseData.Has("id")

    editGui := Gui("+AlwaysOnTop", isNewPurchase ? "Add New Purchase" : "Edit Purchase")
    editGui.SetFont("s10")

    if isNewPurchase {
        editGui.Add("Text", , "Product ID:")
        prodIdEdit := editGui.Add("Edit", "w200 r1")
    } else {
        editGui.Add("Text", , "Purchase ID: " . purchaseData["id"])
        editGui.Add("Text", "xm y+5", "Item: " . purchaseData["item_description"])
    }

    editGui.Add("Text", "xm y+10", "Quantity:")
    quantityEdit := editGui.Add("Edit", "w100 r1", purchaseData.Has("quantity") ? purchaseData["quantity"] : "1")

    editGui.Add("Text", "xm y+10", "Price:")
    priceEdit := editGui.Add("Edit", "w100 r1", purchaseData.Has("price_cents") ? Format("{:.2f}", purchaseData["price_cents"] / 100) : "")

    editGui.Add("Text", "xm y+10", "Purchase Date (YYYY-MM-DD):")
    purchaseDateEdit := editGui.Add("Edit", "w150 r1", purchaseData.Has("purchase_date") ? SubStr(purchaseData["purchase_date"], 1, 10) : FormatTime(,"yyyy-MM-dd"))

    saveButton := editGui.Add("Button", "xm y+20 w100 h30", "Save")
    cancelButton := editGui.Add("Button", "x+10 w100 h30", "Cancel")
    if !isNewPurchase {
        deleteButton := editGui.Add("Button", "x+10 w100 h30 BackgroundRed cWhite", "Delete")
    }

    if isNewPurchase {
        saveButton.OnEvent("Click", (*) => AddNewPurchaseHandler(editGui, prodIdEdit, quantityEdit, priceEdit, purchaseDateEdit))
    } else {
        saveButton.OnEvent("Click", (*) => UpdatePurchaseHandler(editGui, purchaseData, quantityEdit, priceEdit, purchaseDateEdit))
    }
    cancelButton.OnEvent("Click", (*) => CancelEditClickHandler(editGui))
    if !isNewPurchase {
        deleteButton.OnEvent("Click", (*) => DeletePurchaseClickHandler(editGui, purchaseData["id"]))
    }
    editGui.OnEvent("Close", (*) => CancelEditClickHandler(editGui))

    editGui.Show("x" . (A_ScreenWidth / 2 - 200) . " y" . (A_ScreenHeight / 2 - 250))
}

UpdatePurchaseHandler(gui, originalPurchaseData, quantityEdit, priceEdit, purchaseDateEdit) {
    response_obj := Map()
    newQuantity := Trim(quantityEdit.Text)
    newPrice := Trim(priceEdit.Text)
    newPurchaseDate := Trim(purchaseDateEdit.Text)

    ; Basic validation
    if !IsNumber(newQuantity) || Integer(newQuantity) < 1 {
        MsgBox("Please enter a valid quantity (number > 0).")
        return
    }
    if !IsNumber(newPrice) || Float(newPrice) < 0 {
        MsgBox("Please enter a valid price (number >= 0).")
        return
    }
    if !RegExMatch(newPurchaseDate, "^\d{4}-\d{2}-\d{2}$") {
        MsgBox("Please enter a valid date in YYYY-MM-DD format.")
        return
    }

    response_obj["type"] := "purchase_updated"
    response_obj["purchase_id"] := originalPurchaseData["id"]
    response_obj["quantity"] := Integer(newQuantity)
    response_obj["price"] := Float(newPrice)
    response_obj["purchase_date"] := newPurchaseDate

    WriteResponseJSON(response_obj)
    gui.Destroy()
}

AddNewPurchaseHandler(gui, prodIdEdit, quantityEdit, priceEdit, purchaseDateEdit) {
    response_obj := Map()
    newQuantity := Trim(quantityEdit.Text)
    newPrice := Trim(priceEdit.Text)
    newPurchaseDate := Trim(purchaseDateEdit.Text)

    ; Basic validation
    if !IsNumber(newQuantity) || Integer(newQuantity) < 1 {
        MsgBox("Please enter a valid quantity (number > 0).")
        return
    }
    if !IsNumber(newPrice) || Float(newPrice) < 0 {
        MsgBox("Please enter a valid price (number >= 0).")
        return
    }
    if !RegExMatch(newPurchaseDate, "^\d{4}-\d{2}-\d{2}$") {
        MsgBox("Please enter a valid date in YYYY-MM-DD format.")
        return
    }

    newProdId := Trim(prodIdEdit.Text)
    if newProdId = "" {
        MsgBox("Product ID is required for a new purchase.")
        return
    }
    response_obj["type"] := "purchase_added"
    response_obj["prod_id"] := newProdId
    response_obj["quantity"] := Integer(newQuantity)
    response_obj["price"] := Float(newPrice)
    response_obj["purchase_date"] := newPurchaseDate

    WriteResponseJSON(response_obj)
    gui.Destroy()
}

DeletePurchaseClickHandler(gui, purchaseId) {
    if MsgBox("Are you sure you want to delete this purchase?", "Confirm Delete", "YesNo") = "No" {
        return
    }
    response_obj := Map()
    response_obj["type"] := "purchase_deleted"
    response_obj["purchase_id"] := purchaseId
    WriteResponseJSON(response_obj)
    gui.Destroy()
}

CancelEditClickHandler(gui) {
    SendStatus("cancelled")
    gui.Destroy()
}

FindPurchasesClickHandler(gui, searchTermEdit, startDateEdit, endDateEdit) {
    response_obj := Map()
    response_obj["type"] := "search_purchases"
    response_obj["search_term"] := Trim(searchTermEdit.Text)
    response_obj["start_date"] := Trim(startDateEdit.Text)
    response_obj["end_date"] := Trim(endDateEdit.Text)
    WriteResponseJSON(response_obj)
    gui.Destroy()
}

CancelSearchClickHandler(gui) {
    SendStatus("cancelled")
    gui.Destroy()
}

SelectPurchaseClickHandler(gui, purchaseId) {
    response_obj := Map()
    response_obj["type"] := "purchase_selected"
    response_obj["purchase_id"] := purchaseId
    WriteResponseJSON(response_obj)
    gui.Destroy()
}

NewPurchaseClickHandler(gui) {
    response_obj := Map()
    response_obj["type"] := "new_purchase"
    WriteResponseJSON(response_obj)
    gui.Destroy()
}

CancelSelectionClickHandler(gui) {
    SendStatus("cancelled")
    gui.Destroy()
}

; Process lookup result from Ruby
ProcessLookupResult(jsonParam) {
    WriteDebug("ProcessLookupResult called with: " . jsonParam)
    
    ; Only process if we have an active dialog
    if (!CurrentAddItemDialog || !CurrentDialogControls) {
        WriteDebug("No active dialog to update - lookup result ignored")
        WriteDebug("DEBUG: ProcessLookupResult sending ready status (no active dialog)")
        SendStatus("ready")  ; Send acknowledgment anyway
        return
    }
    
    try {
        ; Parse the JSON response
        lookupData := jsongo.Parse(jsonParam)
        
        if (lookupData["found"]) {
            WriteDebug("Updating dialog with found item data")
            WriteDebug("Current description field text: '" . CurrentDialogControls.descriptionEdit.Text . "'")
            WriteDebug("Setting description to: '" . lookupData["description"] . "'")
            
            ; Update dialog fields with lookup data
            CurrentDialogControls.descriptionEdit.Text := lookupData["description"]
            CurrentDialogControls.modifierEdit.Text := lookupData["modifier"]
            CurrentDialogControls.priorityEdit.Text := lookupData["priority"]
            CurrentDialogControls.defaultQuantityEdit.Text := lookupData["default_quantity"]
            CurrentDialogControls.quantityEdit.Text := lookupData["default_quantity"]
            
            WriteDebug("After update, description field text: '" . CurrentDialogControls.descriptionEdit.Text . "'")
            WriteDebug("Dialog updated with: " . lookupData["description"])
        } else {
            WriteDebug("Item not found - clearing placeholder text")
            ; Clear the "< Looking up... >" placeholder
            CurrentDialogControls.descriptionEdit.Text := ""
        }
    } catch as e {
        WriteDebug("Error processing lookup result: " . e.message)
        ; Clear placeholder on error
        if (CurrentDialogControls.descriptionEdit) {
            CurrentDialogControls.descriptionEdit.Text := ""
        }
    }
    
    SendStatus("ready")
}