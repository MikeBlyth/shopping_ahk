; Walmart Grocery Automation
; Uses Ctrl+Shift+A to add items and Ctrl+Shift+Q to quit

; Include JSON library and image search function
#Include lib/jsongo.v2.ahk
#Include lib/image_search_function.ahk

; Use fast typing of URL 
SendMode "Input"

; File paths for communication
ScriptDir := A_ScriptDir
CommandFile := ScriptDir . "\ahk_command.txt"
StatusFile := ScriptDir . "\ahk_status.txt"
ResponseFile := ScriptDir . "\ahk_response.txt"

; Global variables
UserReady := false
StatusGui := ""
; Purchase detection variables
ButtonRegion := {left: 0, top: 0, right: 0, bottom: 0}
ButtonFound := false
CurrentPurchaseButton := ""

; Initialize - clear any leftover files from previous session
try {
    FileDelete(CommandFile)
    FileDelete(ResponseFile)
} catch {
    ; Ignore errors if files don't exist
}

WriteStatus("WAITING_FOR_HOTKEY")

; Clear debug log at startup
try {
    FileDelete("command_debug.txt")
    FileAppend("=== AutoHotkey started at " . A_Now . " ===`n", "command_debug.txt")
} catch {
    ; Ignore errors if file doesn't exist
}

; Show initial status
ShowPersistentStatus("Assistant ready - select browser window and click OK to start")

MsgBox("AutoHotkey ready!`n`nPlease select your browser window with Walmart.com open and click OK to start.", "Walmart Assistant", 0x40000)

; Auto-start after initial dialog closes
UserReady := true
WriteStatus("READY")
TargetWindowHandle := WinExist("A")

if !TargetWindowHandle {
    MsgBox("Could not find an active window handle.")
    ExitApp
}

; Update status for shopping mode
ShowPersistentStatus("Processing shopping list")


; Main loop - check for commands every 500ms
Loop {
    if FileExist(CommandFile) {
        command := FileRead(CommandFile)
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
    
    WriteStatus("PROCESSING")
    
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
        case "SHOW_MULTIPLE_CHOICE":
            FileAppend("MATCHED SHOW_MULTIPLE_CHOICE`n", "command_debug.txt")
            ShowMultipleChoice(param)
        case "GET_PRICE_INPUT":
            FileAppend("MATCHED GET_PRICE_INPUT`n", "command_debug.txt")
            GetPriceInput()
        case "SESSION_COMPLETE":
            FileAppend("MATCHED SESSION_COMPLETE`n", "command_debug.txt")
            ProcessSessionComplete()
        case "ADD_ITEM_DIALOG":
            FileAppend("MATCHED ADD_ITEM_DIALOG`n", "command_debug.txt")
            ShowAddItemDialog(param)
        case "TERMINATE":
            FileAppend("MATCHED TERMINATE - shutting down`n", "command_debug.txt")
            global StatusGui
            
            ; Close status window
            if StatusGui != "" {
                try {
                    StatusGui.Destroy()
                }
            }
            
            WriteStatus("SHUTDOWN")
            MsgBox("Ruby requested AutoHotkey shutdown", "Walmart Assistant", "OK")
            ExitApp()
        default:
            FileAppend("UNKNOWN COMMAND - action: '" . action . "', original: '" . command . "'`n", "command_debug.txt")
            WriteStatus("ERROR")
            WriteResponse("Unknown command: " . action)
    }
}

OpenURL(url) {
    ; Go to address bar and navigate
    WinActivate(TargetWindowHandle)
    WinWaitActive(TargetWindowHandle)
    PasteURL(url)
    
    ; Wait briefly for page to start loading
    Sleep(800)
    
    ; Don't wait for user here - let the next command (SHOW_ITEM_PROMPT) handle user interaction
    WriteStatus("COMPLETED")
}

PasteURL(url) {
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
    WriteStatus("COMPLETED")
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
    
    WriteResponse(currentURL)
    WriteStatus("COMPLETED")
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
    WriteStatus("COMPLETED")
    WriteResponse("Browser active (user controlled)")
}

ShowMessage(param) {
    MsgBox(param, "Walmart Shopping Assistant", "OK")
    WriteResponse("ok")
    WriteStatus("COMPLETED")
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

ShowPurchaseDialog(item_name, is_known, item_description, default_quantity) {
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
    purchaseGui.Add("Text", "xm y+15", "Price (leave blank to skip):")
    priceEdit := purchaseGui.Add("Edit", "w150 r1")
    purchaseGui.Add("Text", "x+5 yp+3", "$")
    
    ; Quantity field
    purchaseGui.Add("Text", "xm y+10", "Quantity:")
    quantityEdit := purchaseGui.Add("Edit", "w150 r1", default_quantity)
    
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
    
    ; Store purchase button reference globally for click detection
    global CurrentPurchaseButton := addButton
    
    ; Show dialog
    purchaseGui.Show()
    WriteStatus("WAITING_FOR_INPUT")
    
    ; Start purchase detection with delay for page loading
    SetTimer(() => StartPurchaseDetection(), 2000)  ; 2 second delay
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
            response_obj := Map()
            response_obj["type"] := "continue"
            WriteResponseJSON(response_obj)
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
    
    WriteStatus("COMPLETED")
    gui.Destroy()
}

SkipClickHandler(gui) {
    ; Skip purchase, but for new items, still capture URL
    response_obj := Map()
    if !gui.is_known {
        current_url := GetCurrentURLSilent()
        response_obj["type"] := "save_url_only"
        response_obj["url"] := current_url
    } else {
        response_obj["type"] := "skipped"
    }
    WriteResponseJSON(response_obj)
    
    WriteStatus("COMPLETED")
    gui.Destroy()
}

SearchAgainClickHandler(gui) {
    ; User wants to search for alternatives - return like selecting "search for new item" in multi-choice
    response_obj := Map()
    response_obj["type"] := "choice"
    response_obj["choice_index"] := 999  ; Use high number to indicate "search for new item" option
    WriteResponseJSON(response_obj)
    WriteStatus("COMPLETED")
    gui.Destroy()
}

GetCurrentURLAndRespond(responsePrefix) {
    ; Get current URL from browser (silent)
    current_url := GetCurrentURLSilent()
    
    if responsePrefix = "save_url_only" {
        WriteResponse("save_url_only|" . current_url)
    } else {
        WriteResponse(responsePrefix . "|" . current_url)
    }
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
            WriteResponse("skipped")
        } else {
            ; Validate numeric choice
            try {
                choice_num := Integer(choice_text)
                if choice_num >= 1 && choice_num <= options.Length {
                    WriteResponse("choice|" . choice_num)
                } else {
                    WriteResponse("cancelled")
                }
            } catch {
                WriteResponse("cancelled")
            }
        }
    } else {
        WriteResponse("cancelled")
    }
    
    WriteStatus("COMPLETED")
}

GetPriceInput() {
    result := InputBox("Enter the current price (e.g., 3.45):", "Record Price", "w300 h150")
    
    if result.Result = "OK" && result.Value != "" {
        WriteResponse("price|" . result.Value)
    } else {
        WriteResponse("cancelled")
    }
    
    WriteStatus("COMPLETED")
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
        ; Convert to JSON and write to file - using manual JSON to avoid jsongo bugs
        try {
            json_response := jsongo.Stringify(response_obj)
            ; Check if JSON is properly formatted (should start with { and have quoted properties)
            if (!InStr(json_response, '{"') && InStr(json_response, '{')) {
                ; jsongo generated malformed JSON, use manual approach
                throw Error("jsongo malformed output")
            }
        } catch {
            ; Manual JSON generation as fallback
            json_parts := []
            for key, value in response_obj {
                if (IsObject(value)) {
                    ; Handle arrays
                    if (value.Has(1)) {
                        array_items := []
                        for item in value {
                            array_items.Push('"' . StrReplace(StrReplace(String(item), '\', '\\'), '"', '\"') . '"')
                        }
                        json_parts.Push('"' . key . '": [' . array_items.Join(', ') . ']')
                    }
                } else {
                    ; Handle strings and numbers
                    if (IsNumber(value)) {
                        json_parts.Push('"' . key . '": ' . value)
                    } else {
                        json_parts.Push('"' . key . '": "' . StrReplace(StrReplace(String(value), '\', '\\'), '"', '\"') . '"')
                    }
                }
            }
            json_response := '{' . json_parts.Join(', ') . '}'
        }
        
        if FileExist(ResponseFile)
            FileDelete(ResponseFile)
        FileAppend(json_response, ResponseFile)
        ToolTip("DEBUG: Wrote JSON response: " . SubStr(json_response, 1, 50) . "...", 400, 50)
        SetTimer(() => ToolTip("", 400, 50), -2000)
    } catch as e {
        ; Fallback to simple text if JSON conversion fails
        if FileExist(ResponseFile)
            FileDelete(ResponseFile)
        FileAppend("ERROR: " . e.message, ResponseFile)
    }
}

WriteResponse(response) {
    try {
        ; Convert all responses to JSON format for consistency
        response_obj := Map()
        
        ; Parse response string to determine type and data
        if (response = "ok" || response = "cancelled" || response = "skipped" || response = "continue" || response = "session_reset" || response = "quit") {
            ; Simple status responses
            response_obj["type"] := "status"
            response_obj["value"] := response
        } else if (InStr(response, "|") > 0) {
            ; Pipe-delimited responses - convert to structured format
            parts := StrSplit(response, "|")
            response_obj["type"] := parts[1]
            
            switch parts[1] {
                case "choice":
                    response_obj["value"] := Integer(parts[2])
                case "price":
                    response_obj["value"] := Float(parts[2])
                case "purchase":
                    response_obj["price"] := Float(parts[2])
                    response_obj["quantity"] := Integer(parts[3])
                case "purchase_new":
                    response_obj["price"] := Float(parts[2])
                    response_obj["quantity"] := Integer(parts[3])
                    response_obj["url"] := parts.Length >= 4 ? parts[4] : ""
                case "save_url_only":
                    response_obj["url"] := parts[2]
                case "add_and_purchase":
                    response_obj["description"] := parts[2]
                    response_obj["modifier"] := parts[3]
                    response_obj["priority"] := Integer(parts[4])
                    response_obj["default_quantity"] := Integer(parts[5])
                    response_obj["url"] := parts[6]
                    response_obj["price"] := Float(parts[7])
                    response_obj["purchase_quantity"] := Integer(parts[8])
                case "search_again":
                    response_obj["search_term"] := parts[2]
                default:
                    ; For unknown pipe-delimited formats, store as array
                    response_obj["data"] := []
                    loop parts.Length - 1 {
                        response_obj["data"].Push(parts[A_Index + 1])
                    }
            }
        } else {
            ; Simple string response (like URL)
            response_obj["type"] := "data"
            response_obj["value"] := response
        }
        
        ; Convert to JSON and write to file - using manual JSON to avoid jsongo bugs
        try {
            json_response := jsongo.Stringify(response_obj)
            ; Check if JSON is properly formatted (should start with { and have quoted properties)
            if (!InStr(json_response, '{"') && InStr(json_response, '{')) {
                ; jsongo generated malformed JSON, use manual approach
                throw Error("jsongo malformed output")
            }
        } catch {
            ; Manual JSON generation as fallback
            json_parts := []
            for key, value in response_obj {
                if (IsObject(value)) {
                    ; Handle arrays
                    if (value.Has(1)) {
                        array_items := []
                        for item in value {
                            array_items.Push('"' . StrReplace(StrReplace(String(item), '\', '\\'), '"', '\"') . '"')
                        }
                        json_parts.Push('"' . key . '": [' . array_items.Join(', ') . ']')
                    }
                } else {
                    ; Handle strings and numbers
                    if (IsNumber(value)) {
                        json_parts.Push('"' . key . '": ' . value)
                    } else {
                        json_parts.Push('"' . key . '": "' . StrReplace(StrReplace(String(value), '\', '\\'), '"', '\"') . '"')
                    }
                }
            }
            json_response := '{' . json_parts.Join(', ') . '}'
        }
        
        if FileExist(ResponseFile)
            FileDelete(ResponseFile)
        FileAppend(json_response, ResponseFile)
        ToolTip("DEBUG: Wrote JSON response: " . SubStr(json_response, 1, 50) . "...", 400, 50)
        SetTimer(() => ToolTip("", 400, 50), -2000)  ; Clear debug tooltip after 2 seconds
    } catch as e {
        ; Fallback to simple text if JSON conversion fails
        if FileExist(ResponseFile)
            FileDelete(ResponseFile)
        FileAppend(response, ResponseFile)
        ToolTip("DEBUG: JSON failed, wrote simple response: " . response, 400, 50)
        SetTimer(() => ToolTip("", 400, 50), -3000)
    }
}

; Reset state after shopping list completion
ResetForNextSession() {
    global UserReady
    UserReady := false
    WriteStatus("WAITING_FOR_HOTKEY")
    ; Tooltip is already set by ProcessSessionComplete, don't override it
}


; Shopping list processing complete
ProcessSessionComplete() {
    FileAppend("ProcessSessionComplete called - setting completion tooltip`n", "command_debug.txt")
    WriteResponse("session_reset")
    WriteStatus("WAITING_FOR_HOTKEY")
    ShowPersistentStatus("Shopping list complete! Press Ctrl+Shift+A to add items or Ctrl+Shift+Q to quit")
    ResetForNextSession()
}


; Hotkeys
^+q::{
    ; Clean exit - signal Ruby and shutdown
    PerformQuit()
}

^+a::{
    ; Add new item hotkey
    FileAppend("Ctrl+Shift+A pressed - calling ShowAddItemDialogHotkey`n", "command_debug.txt")
    ShowAddItemDialogHotkey()
}

^+s::{  ; Ctrl+Shift+S to show status
    status := FileExist(StatusFile) ? FileRead(StatusFile) : "No status file"
    MsgBox("Current Status: " . status . "`n`nActive hotkeys: Ctrl+Shift+A (add item), Ctrl+Shift+Q (quit)")
}

; Add Item Dialog Functions
ShowAddItemDialog(suggestedName) {
    ; Get current URL
    currentUrl := GetCurrentURL()
    
    ; Show the add item dialog
    ShowAddItemDialogWithDefaults(suggestedName, currentUrl)
}

ShowAddItemDialogHotkey() {
    FileAppend("ShowAddItemDialogHotkey called`n", "command_debug.txt")
    
    ; Get current URL (silent - doesn't write to response file)
    currentUrl := GetCurrentURLSilent()
    FileAppend("Current URL captured: " . currentUrl . "`n", "command_debug.txt")
    
    ; Show dialog with empty suggested name (user triggered)
    ShowAddItemDialogWithDefaults("", currentUrl)
}

ShowAddItemDialogWithDefaults(suggestedName, currentUrl) {
    ; Create dialog
    addItemGui := Gui("+AlwaysOnTop", "Add Item & Purchase")
    addItemGui.SetFont("s10")
    
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
    priceEdit := addItemGui.Add("Edit", "w150 r1")
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
    cancelButton := addItemGui.Add("Button", "x+10 w100 h30", "Cancel")
    
    ; Make variables accessible to event handlers
    addItemGui.descriptionEdit := descriptionEdit
    addItemGui.modifierEdit := modifierEdit
    addItemGui.priorityEdit := priorityEdit
    addItemGui.defaultQuantityEdit := defaultQuantityEdit
    addItemGui.priceEdit := priceEdit
    addItemGui.purchaseQuantityEdit := purchaseQuantityEdit
    addItemGui.currentUrl := currentUrl
    
    ; Button event handlers
    addButton.OnEvent("Click", (*) => AddAndPurchaseClickHandler(addItemGui))
    addOnlyButton.OnEvent("Click", (*) => AddOnlyClickHandler(addItemGui))
    cancelButton.OnEvent("Click", (*) => CancelItemClickHandler(addItemGui))
    
    ; Store purchase button reference globally for click detection
    global CurrentPurchaseButton := addButton
    
    ; Show dialog
    addItemGui.Show()
    WriteStatus("WAITING_FOR_INPUT")
    
    ; Start purchase detection with delay for page loading
    SetTimer(() => StartPurchaseDetection(), 2000)  ; 2 second delay
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
    
    FileAppend("AddAndPurchaseClickHandler - writing JSON response`n", "command_debug.txt")
    WriteResponseJSON(response_obj)
    WriteStatus("COMPLETED")
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
    
    ; Format response without purchase info (original format)
    response := description . "|" . modifier . "|" . priority . "|" . defaultQuantity . "|" . currentUrl
    FileAppend("AddOnlyClickHandler - writing response: " . response . "`n", "command_debug.txt")
    WriteResponse(response)
    WriteStatus("COMPLETED")
    gui.Destroy()
    
    ; Show confirmation
    MsgBox("Item '" . description . "' has been sent to Ruby for processing!", "Item Added", "OK")
}

CancelItemClickHandler(gui) {
    WriteResponse("cancelled")
    WriteStatus("COMPLETED")
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

; Shared quit functionality
PerformQuit() {
    global StatusGui
    
    ; Close status window
    if StatusGui != "" {
        try {
            StatusGui.Destroy()
        }
    }
    
    WriteResponse("quit")  ; Tell Ruby we're quitting
    WriteStatus("SHUTDOWN")
    MsgBox("AutoHotkey script shutting down...", "Walmart Assistant", "OK")
    ExitApp()
}

; Purchase Detection Functions
StartPurchaseDetection() {
    global ButtonRegion, ButtonFound
    
    ; Search for Add to Cart button on page
    result := FindAddToCartButton(3000)  ; 3 second search
    
    if (result.found) {
        ButtonRegion := result.clickRegion
        ButtonFound := true
    } else {
        ButtonFound := false
    }
}

; Global click handler for purchase detection
~LButton:: {
    global ButtonRegion, ButtonFound, CurrentPurchaseButton
    
    if (!ButtonFound || !CurrentPurchaseButton)
        return
    
    ; Get click position
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    
    ; Check if click is in Add to Cart button region
    if (mouseX >= ButtonRegion.left && mouseX <= ButtonRegion.right && 
        mouseY >= ButtonRegion.top && mouseY <= ButtonRegion.bottom) {
        
        ; Change button to Add & Purchase state
        CurrentPurchaseButton.Text := "✅ Add & Purchase"
        CurrentPurchaseButton.Opt("BackgroundGreen cWhite")
        
        ; Stop monitoring this page immediately
        ButtonFound := false
    }
}