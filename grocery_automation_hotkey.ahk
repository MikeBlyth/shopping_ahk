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

; Initialize
WriteStatus("WAITING_FOR_HOTKEY")
MsgBox("AutoHotkey ready!`n`nInstructions:`n1. Start ruby grocery_bot.rb`n2. Open/switch to your Walmart page`n3. Press Ctrl+Shift+R when ready", "Walmart Assistant", "OK")

; Hotkey to signal readiness or continue
^+r::{
    global UserReady, WaitingForUser
    
    if WaitingForUser {
        ; User is continuing from a pause
        WaitingForUser := false
        WriteStatus("READY")
        ToolTip("Continuing...", 10, 10)
        SetTimer(() => ToolTip(), -1000)
    } else {
        ; Initial ready signal
        UserReady := true
        WriteStatus("READY")
        MsgBox("Ready signal received! Automation starting...", "Walmart Assistant", "OK")
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
    parts := StrSplit(command, "|", , 2)
    action := parts[1]
    param := parts.Length >= 2 ? parts[2] : ""
    
    WriteStatus("PROCESSING")
    
    switch action {
        case "OPEN_URL":
            OpenURL(param)
        case "SEARCH":
            SearchWalmart(param)
        case "GET_URL":
            GetCurrentURL()
        case "ACTIVATE_BROWSER":
            ActivateBrowserCommand()
        case "SHOW_MESSAGE":
            ShowMessage(param)
        case "SHOW_ITEM_PROMPT":
            ShowItemPrompt(param)
        case "GET_PRICE_INPUT":
            GetPriceInput()
        case "WAIT_FOR_CONTINUE":
            WaitForContinue()
        case "SESSION_COMPLETE":
            ProcessSessionComplete()
        default:
            WriteStatus("ERROR")
            WriteResponse("Unknown command: " . action)
    }
}

OpenURL(url) {
    ; Go to address bar and navigate
    Send("^l")  ; Ctrl+L to focus address bar
    Sleep(100)
    Send("^a")  ; Select all
    Sleep(100)
    SendText(url)
    Sleep(100)
    Send("{Enter}")
    
    ; Wait a moment for page to start loading
    Sleep(2000)
    
    ; Pause and wait for user to continue
    global WaitingForUser
    WaitingForUser := true
    WriteStatus("WAITING_FOR_USER")
    ToolTip("Page opened. Press Ctrl+Shift+R when ready to continue...", 10, 10)
    
    ; Wait for user signal
    while WaitingForUser {
        Sleep(100)
    }
    
    ToolTip()  ; Clear tooltip
    WriteStatus("COMPLETED")
}

SearchWalmart(searchTerm) {
    ; Build search URL
    searchURL := "https://www.walmart.com/search?q=" . UriEncode(searchTerm)
    
    ; Go to address bar and search
    Send("^l")  ; Ctrl+L to focus address bar
    Sleep(100)
    Send("^a")  ; Select all
    Sleep(100)
    SendText(searchURL)
    Sleep(100)
    Send("{Enter}")
    
    ; Wait for search results
    Sleep(3000)
    
    ; Pause and wait for user to continue
    global WaitingForUser
    WaitingForUser := true
    WriteStatus("WAITING_FOR_USER")
    ToolTip("Search results loaded. Find the product and add to cart, then press Ctrl+Shift+R...", 10, 10)
    
    ; Wait for user signal
    while WaitingForUser {
        Sleep(100)
    }
    
    ToolTip()  ; Clear tooltip
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
    ; Parse param: "item_name|is_known_item|url|description"
    parts := StrSplit(param, "|")
    item_name := parts[1]
    is_known := parts[2] = "true"
    url := parts.Length >= 3 ? parts[3] : ""
    description := parts.Length >= 4 ? parts[4] : ""
    
    if is_known {
        message := "✅ Found saved item: " . item_name . "`n"
        if description != "" {
            message .= "Description: " . description . "`n"
        }
        if url != "" {
            message .= "URL: " . url . "`n"
        }
        message .= "`nReady to add to cart."
    } else {
        message := "🔍 New item: " . item_name . "`n"
        message .= "Search results should be displayed. Find the correct product and add to cart."
    }
    
    message .= "`n`nAfter adding to cart, choose:"
    message .= "`n[Yes] - Continue to next item"
    message .= "`n[No] - Save this product URL"
    message .= "`n[Cancel] - Record price"
    
    result := MsgBox(message, "Item: " . item_name, "YesNoCancel")
    
    switch result {
        case "Yes":
            WriteResponse("continue")
        case "No":
            WriteResponse("save_url")
        case "Cancel":
            WriteResponse("record_price")
        default:
            WriteResponse("continue")
    }
    
    WriteStatus("COMPLETED")
}

GetPriceInput() {
    result := InputBox("💰 Enter the current price (e.g., 3.45):", "Record Price", "w300 h150")
    
    if result.Result = "OK" && result.Text != "" {
        WriteResponse("price|" . result.Text)
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

WriteResponse(response) {
    try {
        if FileExist(ResponseFile)
            FileDelete(ResponseFile)
        FileAppend(response, ResponseFile)
    }
}

; Add a function to reset everything for next session
ResetForNextSession() {
    global WaitingForUser, UserReady
    WaitingForUser := false
    UserReady := false
    WriteStatus("WAITING_FOR_HOTKEY")
    ToolTip("Session complete. Ready for next session.`nPress Ctrl+Shift+R when on Walmart page to start again.", 10, 10)
    SetTimer(() => ToolTip(), -5000)  ; Clear after 5 seconds
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

; Add command to reset session
ProcessSessionComplete() {
    ResetForNextSession()
    WriteResponse("session_reset")
    WriteStatus("WAITING_FOR_HOTKEY")
}

; Hotkeys
^+q::{
    ; Clean exit - reset status file
    WriteStatus("WAITING_FOR_HOTKEY")
    ExitApp()
}

^+s::{  ; Ctrl+Shift+S to show status
    status := FileExist(StatusFile) ? FileRead(StatusFile) : "No status file"
    MsgBox("Current Status: " . status . "`n`nPress Ctrl+Shift+R when on Walmart page to start")
}