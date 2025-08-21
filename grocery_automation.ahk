; Walmart Grocery Automation with Hotkey Trigger
; Press Ctrl+Shift+R when you're ready on the Walmart page

; File paths for communication
ScriptDir := A_ScriptDir
CommandFile := ScriptDir . "\ahk_command.txt"
StatusFile := ScriptDir . "\ahk_status.txt"
ResponseFile := ScriptDir . "\ahk_response.txt"

; Global variables
UserReady := false
WaitingForUser := false
StatusGui := ""

; Initialize
WriteStatus("WAITING_FOR_HOTKEY")

; Clear debug log at startup
try {
    FileDelete("command_debug.txt")
    FileAppend("=== AutoHotkey started at " . A_Now . " ===`n", "command_debug.txt")
} catch {
    ; Ignore errors if file doesn't exist
}

; Show initial status
ShowPersistentStatus("Assistant ready - processing shopping list, press Ctrl+Shift+Q to quit")

; Create a TopMost dialog
startupComplete := false
startupGui := Gui("+AlwaysOnTop", "Walmart Assistant")
startupGui.SetFont("s10")
startupGui.Add("Text", "x20 y15 w300", "AutoHotkey ready!")
startupGui.Add("Text", "x20 y40 w300", "Instructions:")
startupGui.Add("Text", "x20 y60 w300", "1. Switch to your Walmart browser window")
startupGui.Add("Text", "x20 y80 w300", "2. Press OK to start automation")
okButton := startupGui.Add("Button", "x130 y110 w60 h30", "OK")
okButton.OnEvent("Click", (*) => StartupOKClicked(startupGui))
startupGui.Show("w340 h160")

; Wait for user to click OK
while !startupComplete {
    Sleep(100)
}

; After user presses OK, signal readiness immediately
UserReady := true
TargetWindowHandle := WinExist("A")

if !TargetWindowHandle {
    MsgBox("Could not find an active window handle.", "Error", "OK TopMost")
    ExitApp
}

WriteStatus("READY")
ShowPersistentStatus("Assistant processing shopping list, press Ctrl+Shift+Q to quit")

; Hotkey to continue when waiting for user (mid-process only)
^+r::{
    global WaitingForUser
    
    if WaitingForUser {
        WaitingForUser := false
        WriteStatus("READY")
    } else {
        ; If we're in a search state, respond with skip and complete command
        WriteResponse("skip")
        WriteStatus("COMPLETED")
    }
}

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
    
    pipe_pos := InStr(command, "|")
    if (pipe_pos > 0) {
        action := SubStr(command, 1, pipe_pos - 1)
        param := SubStr(command, pipe_pos + 1)
    } else {
        action := command
        param := ""
    }
    
    ; Debug: Log parsed action and param
    FileAppend("Parsed action: '" . action . "', param: '" . param . "'`n", "command_debug.txt")
    
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
        case "WAIT_FOR_CONTINUE":
            FileAppend("MATCHED WAIT_FOR_CONTINUE`n", "command_debug.txt")
            WaitForContinue()
        case "LIST_COMPLETE":
            FileAppend("MATCHED LIST_COMPLETE`n", "command_debug.txt")
            ProcessSessionComplete()
        case "ADD_ITEM_DIALOG":
            FileAppend("MATCHED ADD_ITEM_DIALOG`n", "command_debug.txt")
            ShowAddItemDialog(param)
        case "WAIT_FOR_USER":
            FileAppend("MATCHED WAIT_FOR_USER`n", "command_debug.txt")
            WaitForUser()
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
    SendInput("^l")  ; Ctrl+L to focus address bar
    Sleep(50)
    SendInput("^a")  ; Select all
    Sleep(50)
    
    ; Copy URL to clipboard and paste (fastest method)
    A_Clipboard := url
    SendInput("^v")  ; Paste URL
    Sleep(50)
    SendInput("{Enter}")
    
    ; Wait a moment for page to start loading
    Sleep(1500)
    
    ; Don't wait for user here - let the next command (SHOW_ITEM_PROMPT) handle user interaction
    WriteStatus("COMPLETED")
}

SearchWalmart(searchTerm) {
    ; Update status to show what user should do
    ShowPersistentStatus("Searching for " . searchTerm . ". Navigate to product, then Ctrl+Shift+A to add or Ctrl+Shift+R to skip.")
    
    ; Build search URL
    searchURL := "https://www.walmart.com/search?q=" . UriEncode(searchTerm)
    
    ; Go to address bar and search
    SendInput("^l")  ; Ctrl+L to focus address bar
    Sleep(50)
    SendInput("^a")  ; Select all
    Sleep(50)
    
    ; Copy search URL to clipboard and paste (fastest method)
    A_Clipboard := searchURL
    SendInput("^v")  ; Paste search URL
    Sleep(50)
    SendInput("{Enter}")
    
    ; Wait for search results to load
    Sleep(2000)
    
    ; Don't send anything to Ruby - just wait for user action
    ; Ctrl+Shift+A or Ctrl+Shift+R will complete the command
}

GetCurrentURL() {
    ; Select address bar content to get URL
    SendInput("^l")  ; Focus address bar
    Sleep(50)
    SendInput("^c")  ; Copy URL
    Sleep(50)
    
    ; Get URL from clipboard
    currentURL := A_Clipboard
    
    ; Clear clipboard
    A_Clipboard := ""
    
    WriteResponse(currentURL)
    WriteStatus("COMPLETED")
}

GetCurrentURLSilent() {
    ; Get current URL without writing to response file
    ; First ensure browser window is active
    WinActivate(TargetWindowHandle)
    WinWaitActive(TargetWindowHandle)
    
    ; Clear clipboard first
    A_Clipboard := ""
    
    SendInput("^l")  ; Focus address bar
    Sleep(100)
    SendInput("^a")  ; Select all in address bar
    Sleep(50)
    SendInput("^c")  ; Copy URL
    Sleep(100)
    
    ; Get URL from clipboard
    currentURL := A_Clipboard
    
    ; Debug log the captured URL
    FileAppend("GetCurrentURLSilent captured: " . currentURL . "`n", "command_debug.txt")
    
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
    
    ; Buttons
    addButton := purchaseGui.Add("Button", "xm y+20 w100 h30", "Record Purchase")
    skipButton := purchaseGui.Add("Button", "x+10 w100 h30", "Skip/Cancel")
    
    ; Store references for event handlers
    purchaseGui.priceEdit := priceEdit
    purchaseGui.quantityEdit := quantityEdit
    purchaseGui.is_known := is_known
    
    ; Button event handlers
    addButton.OnEvent("Click", (*) => PurchaseClickHandler(purchaseGui))
    skipButton.OnEvent("Click", (*) => SkipClickHandler(purchaseGui))
    
    ; Show dialog
    purchaseGui.Show()
    WriteStatus("WAITING_FOR_INPUT")
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
            GetCurrentURLAndRespond("save_url_only")
        } else {
            WriteResponse("skip")
        }
    } else {
        ; Valid price entered - record purchase
        if !IsNumber(price) {
            MsgBox("Please enter a valid price (numbers only)", "Invalid Price")
            return
        }
        
        ; For new items, also capture the URL
        if !gui.is_known {
            GetCurrentURLAndRespond("purchase_new|" . price . "|" . quantity)
        } else {
            WriteResponse("purchase|" . price . "|" . quantity)
        }
    }
    
    WriteStatus("COMPLETED")
    gui.Destroy()
}

SkipClickHandler(gui) {
    ; Skip purchase, but for new items, still capture URL
    if !gui.is_known {
        GetCurrentURLAndRespond("save_url_only")
    } else {
        WriteResponse("skip")
    }
    
    WriteStatus("COMPLETED")
    gui.Destroy()
}

CancelPurchaseClickHandler(gui) {
    ; Cancel completely - for new items, still save URL
    if !gui.is_known {
        GetCurrentURLAndRespond("save_url_only")
    } else {
        WriteResponse("skip")
    }
    
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
                    WriteResponse("skip")
                }
            } catch {
                WriteResponse("skip")
            }
        }
    } else {
        WriteResponse("skip")
    }
    
    WriteStatus("COMPLETED")
}

GetPriceInput() {
    result := InputBox("Enter the current price (e.g., 3.45):", "Record Price", "w300 h150")
    
    if result.Result = "OK" && result.Value != "" {
        WriteResponse("price|" . result.Value)
    } else {
        WriteResponse("skip")
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

WriteResponse(response) {
    try {
        if FileExist(ResponseFile)
            FileDelete(ResponseFile)
        FileAppend(response, ResponseFile)
        ToolTip("DEBUG: Wrote response: " . SubStr(response, 1, 50) . "...", 400, 50)
        SetTimer(() => ToolTip("", 400, 50), -2000)  ; Clear debug tooltip after 2 seconds
    }
}

; Reset state after shopping list completion
ResetForNextSession() {
    global WaitingForUser, UserReady
    WaitingForUser := false
    UserReady := false
    WriteStatus("WAITING_FOR_HOTKEY")
    ; Tooltip is already set by ProcessSessionComplete, don't override it
}

WaitForContinue() {
    global WaitingForUser
    WaitingForUser := true
    WriteStatus("WAITING_FOR_USER")
    ToolTip("Press Ctrl+Shift+R to continue...", 10, 10)
    
    ; Wait for user signal
    while WaitingForUser {
        Sleep(100)
    }
    
    ToolTip()  ; Clear tooltip
    WriteStatus("COMPLETED")
}

WaitForUser() {
    global WaitingForUser
    WaitingForUser := true
    WriteStatus("WAITING_FOR_USER")
    ToolTip("Press Ctrl+Shift+A to add item or Ctrl+Shift+R to continue...", 10, 10)
    
    ; Wait for user signal
    while WaitingForUser {
        Sleep(100)
    }
    
    ToolTip()  ; Clear tooltip
    WriteStatus("COMPLETED")
}

; Shopping list processing complete
ProcessSessionComplete() {
    FileAppend("ProcessSessionComplete called - setting completion tooltip`n", "command_debug.txt")
    WriteResponse("session_reset")
    WriteStatus("WAITING_FOR_HOTKEY")
    ShowPersistentStatus("Shopping list complete! Press Ctrl+Shift+A to add or purchase item, Ctrl+Shift+Q to quit")
    ResetForNextSession()
}


; Hotkeys
^+q::{
    ; Clean exit - signal Ruby and shutdown
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

^+a::{
    ; Add new item hotkey
    FileAppend("Ctrl+Shift+A pressed - calling ShowAddItemDialogHotkey`n", "command_debug.txt")
    ShowAddItemDialogHotkey()
}

^+s::{  ; Ctrl+Shift+S to show status
    status := FileExist(StatusFile) ? FileRead(StatusFile) : "No status file"
    MsgBox("Current Status: " . status . "`n`nPress Ctrl+Shift+R when on Walmart page to start")
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
    
    ; Small delay to ensure page is ready and clipboard is clear
    Sleep(200)
    
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
    
    ; Buttons
    addButton := addItemGui.Add("Button", "xm y+15 w120 h30", "Add & Purchase")
    addOnlyButton := addItemGui.Add("Button", "x+10 w100 h30", "Add Only")
    skipButton := addItemGui.Add("Button", "x+10 w100 h30", "Skip/Cancel")
    
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
    skipButton.OnEvent("Click", (*) => CancelItemClickHandler(addItemGui))
    
    ; Show dialog
    addItemGui.Show()
    WriteStatus("WAITING_FOR_INPUT")
}

; Event handler functions for Add Item dialog
AddAndPurchaseClickHandler(gui) {
    global WaitingForUser
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
    
    ; Format response with purchase info
    response := "add_and_purchase|" . description . "|" . modifier . "|" . priority . "|" . defaultQuantity . "|" . gui.currentUrl . "|" . price . "|" . purchaseQuantity
    FileAppend("AddAndPurchaseClickHandler - writing response: " . response . "`n", "command_debug.txt")
    WriteResponse(response)
    WriteStatus("COMPLETED")
    WaitingForUser := false  ; End the wait state
    gui.Destroy()
    
    ; Show confirmation
    MsgBox("Item '" . description . "' has been sent to Ruby for processing!", "Item Added", "OK")
}

AddOnlyClickHandler(gui) {
    global WaitingForUser
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
    
    ; Format response without purchase info (original format)
    response := description . "|" . modifier . "|" . priority . "|" . defaultQuantity . "|" . gui.currentUrl
    FileAppend("AddOnlyClickHandler - writing response: " . response . "`n", "command_debug.txt")
    WriteResponse(response)
    WriteStatus("COMPLETED")
    WaitingForUser := false  ; End the wait state
    gui.Destroy()
    
    ; Show confirmation
    MsgBox("Item '" . description . "' has been sent to Ruby for processing!", "Item Added", "OK")
}

CancelItemClickHandler(gui) {
    global WaitingForUser
    WriteResponse("skip")
    WriteStatus("COMPLETED")
    WaitingForUser := false  ; End the wait state
    gui.Destroy()
}

; Create a persistent status window
ShowPersistentStatus(message) {
    global StatusGui
    
    ; Close existing status window if any
    if StatusGui != "" {
        try {
            StatusGui.Destroy()
        }
    }
    
    ; Create a new status GUI with styling
    StatusGui := Gui("+AlwaysOnTop +LastFound -MaximizeBox -MinimizeBox +Resize", "Assistant Status")
    StatusGui.BackColor := "0x2D3748"  ; Dark blue-gray background
    StatusGui.SetFont("s12 Bold", "Segoe UI")
    
    ; Add status text with light color
    statusText := StatusGui.Add("Text", "x20 y15 w400 h60 c0xF7FAFC Center", message)
    
    ; Position in top-right corner with more margin (100px further left)
    StatusGui.Show("x" . (A_ScreenWidth - 900) . " y20 w440 h90 NoActivate")
    
    ; Make it stay on top but not steal focus
    WinSetAlwaysOnTop(1, StatusGui.Hwnd)
}

StartupOKClicked(gui) {
    global startupComplete
    startupComplete := true
    gui.Destroy()
}
