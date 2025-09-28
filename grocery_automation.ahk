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

; Show initial status
ShowPersistentStatus("Assistant ready - select browser window and click OK to start")

MsgBox("AutoHotkey ready!`n`nPlease select your browser window with Walmart.com open and click OK to start.", "Walmart Assistant", 0x40000)

; Auto-start after initial dialog closes
UserReady := true
SendStatus("ready")
MsgBox("Status ready sent via JSON")
TargetWindowHandle := WinExist("A")

if !TargetWindowHandle {
    MsgBox("Could not find an active window handle.")
    ExitApp
}

; Immediately activate the captured window to ensure it's the browser
WinActivate(TargetWindowHandle)
WinWaitActive(TargetWindowHandle, , 3)  ; 3 second timeout
; Show confirmation of which window we're using
MsgBox("Using window: " . WinGetTitle(TargetWindowHandle), "Confirmation", "T2")  ; 2 second auto-dismiss

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
    PasteURL(url)
    
    ; Return immediately - don't wait for page loading
    WriteDebug("DEBUG: OpenURL sending ready status")
    SendStatus("ready")
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
    ; Parse param: "url|item_name|is_known_item|description|item_description|default_quantity"
    parts := StrSplit(param, "|")
    url := parts[1]
    item_name := parts[2]
    is_known := parts[3] = "true"
    description := parts.Length >= 4 ? parts[4] : ""
    item_description := parts.Length >= 5 ? parts[5] : item_name
    default_quantity := parts.Length >= 6 ? parts[6] : "1"
    
    FileAppend("NavigateAndShowDialog: Navigating to " . url . "`n", "command_debug.txt")
    
    ; Navigate to URL (background loading)
    WinActivate(TargetWindowHandle)
    WinWaitActive(TargetWindowHandle)
    PasteURL(url)
    
    ; Show dialog immediately while page loads (no lookup needed for known items)
    FileAppend("NavigateAndShowDialog: Showing dialog for " . item_name . " (known=" . is_known . ")`n", "command_debug.txt")
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
    
    ; Subscribable checkbox (auto-detect and set)
    purchaseGui.Add("Text", "xm y+10", "Subscribable (auto-detected):")
    subscribableCheckbox := purchaseGui.Add("Checkbox", "xm y+5 w200 h20", "Subscribable")
    
    ; Auto-detect subscribable status and set checkbox
    isSubscribable := DetectSubscribable()
    subscribableCheckbox.Value := isSubscribable ? 1 : 0
    
    ; Buttons - Override button starts as warning state
    addButton := purchaseGui.Add("Button", "xm y+20 w120 h30 BackgroundRed cWhite", "⚠️ Override")
    skipButton := purchaseGui.Add("Button", "x+10 w100 h30", "Skip Item")
    searchButton := purchaseGui.Add("Button", "x+10 w100 h30", "Search Again")
    
    ; Store references for event handlers
    purchaseGui.priceEdit := priceEdit
    purchaseGui.quantityEdit := quantityEdit
    purchaseGui.subscribableCheckbox := subscribableCheckbox
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
    
    ; Show dialog immediately (positioned 400px left of center)
    dialogX := (A_ScreenWidth / 2) - 400 - 200  ; Center minus 400px minus half dialog width
    purchaseGui.Show("x" . dialogX)

    ; Start purchase detection and price detection immediately
    SetTimer(StartDetectionForPurchaseDialog.Bind(priceEdit), -100)  ; Run once after 100ms delay
}

; Event handler functions for Purchase dialog
PurchaseClickHandler(gui) {
    price := Trim(gui.priceEdit.Text)
    quantity := Trim(gui.quantityEdit.Text)
    subscribable := gui.subscribableCheckbox.Value
    
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
            response_obj["subscribable"] := subscribable ? 1 : 0
            response_obj["url"] := current_url
        } else {
            response_obj["type"] := "purchase"
            response_obj["price"] := Float(price)
            response_obj["quantity"] := Integer(quantity)
            response_obj["subscribable"] := subscribable ? 1 : 0
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
        FileAppend(json_response, ResponseFile)
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

WriteResponse(response) {
    try {
        ; Delete existing response file
        if FileExist(ResponseFile)
            FileDelete(ResponseFile)
        ; Write response as plain text
        FileAppend(response, ResponseFile)
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
    
    ; Show dialog FIRST with "looking up" placeholder
    WriteDebug("Showing dialog with lookup placeholder")
    ShowAddItemDialogWithDefaults("< Looking up... >", currentUrl)
    
    ; THEN send lookup request to Ruby (after dialog is created)
    WriteDebug("Sending lookup request for URL: " . currentUrl)
    SendLookupRequest(currentUrl)
}

ShowAddItemDialogWithDefaults(suggestedName, currentUrl) {
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
    
    ; Subscribable checkbox (auto-detect and set)
    addItemGui.Add("Text", "xm y+10", "Subscribable (auto-detected):")
    subscribableCheckbox := addItemGui.Add("Checkbox", "xm y+5 w200 h20", "Enable subscription")
    
    ; Auto-detect subscribable status and set checkbox
    isSubscribable := DetectSubscribable()
    subscribableCheckbox.Value := isSubscribable ? 1 : 0
    
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
    addItemGui.subscribableCheckbox := subscribableCheckbox
    addItemGui.priceEdit := priceEdit
    addItemGui.purchaseQuantityEdit := purchaseQuantityEdit
    addItemGui.currentUrl := currentUrl
    
    ; Store control references globally for lookup updates IMMEDIATELY
    global CurrentDialogControls := {
        descriptionEdit: descriptionEdit,
        modifierEdit: modifierEdit,
        priorityEdit: priorityEdit,
        defaultQuantityEdit: defaultQuantityEdit,
        subscribableCheckbox: subscribableCheckbox,
        quantityEdit: purchaseQuantityEdit
    }
    
    ; Button event handlers
    addButton.OnEvent("Click", (*) => AddAndPurchaseClickHandler(addItemGui))
    addOnlyButton.OnEvent("Click", (*) => AddOnlyClickHandler(addItemGui))
    cancelButton.OnEvent("Click", (*) => CancelItemClickHandler(addItemGui))
    
    ; Store purchase button and price edit references globally for click detection
    global CurrentPurchaseButton := addButton
    global CurrentPriceEdit := priceEdit
    WriteDebug("ShowAddItemDialog: Set CurrentPriceEdit reference")
    
    ; Add cleanup handler when dialog is closed
    addItemGui.OnEvent("Close", (*) => CleanupDialogReferences())
    
    ; Show dialog immediately (positioned 400px left of center)
    dialogX := (A_ScreenWidth / 2) - 400 - 250  ; Center minus 400px minus half dialog width
    dialogX := 600 ; Center minus 400px minus half dialog width
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
    subscribable := gui.subscribableCheckbox.Value
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
    response_obj["subscribable"] := subscribable ? 1 : 0
    response_obj["url"] := currentUrl
    response_obj["price"] := price != "" ? Float(price) : ""
    response_obj["purchase_quantity"] := Integer(purchaseQuantity)
    
    WriteDebug("AddAndPurchaseClickHandler - writing JSON response")
    WriteResponseJSON(response_obj)
    StopPriceDetection()
    gui.Destroy()
    
    ; Show confirmation
    MsgBox("Item '" . description . "' has been sent to Ruby for processing!", "Item Added", "OK")
}

AddOnlyClickHandler(gui) {
    description := Trim(gui.descriptionEdit.Text)
    modifier := Trim(gui.modifierEdit.Text)
    priority := Trim(gui.priorityEdit.Text)
    defaultQuantity := Trim(gui.defaultQuantityEdit.Text)
    subscribable := gui.subscribableCheckbox.Value
    
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
    response_obj["subscribable"] := subscribable ? 1 : 0
    response_obj["url"] := currentUrl
    response_obj["price"] := "" ; Empty price indicates "add only"
    response_obj["purchase_quantity"] := 0

    WriteResponseJSON(response_obj)
    StopPriceDetection()
    gui.Destroy()
    
    ; Show confirmation
    MsgBox("Item '" . description . "' has been sent to Ruby for processing!", "Item Added", "OK")
}

CancelItemClickHandler(gui) {
    SendStatus("cancelled")
    StopPriceDetection()
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
        CurrentPriceEdit.Text := price
        
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
            CurrentDialogControls.subscribableCheckbox.Value := lookupData["subscribable"] ? 1 : 0
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