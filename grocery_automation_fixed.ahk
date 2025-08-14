; Walmart Grocery Automation Script for AutoHotkey v2
; Communicates with Ruby script via text files

; File paths for communication (use absolute paths)
ScriptDir := A_ScriptDir
CommandFile := ScriptDir . "\ahk_command.txt"
StatusFile := ScriptDir . "\ahk_status.txt"
ResponseFile := ScriptDir . "\ahk_response.txt"

; Initialize
WriteStatus("READY")
SetTitleMatchMode(2)  ; Partial title matching

; Main loop - check for commands every 500ms
Loop {
    ; Ensure status file exists (in case it gets deleted)
    if !FileExist(StatusFile) {
        WriteStatus("READY")
    }
    
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
        case "WAIT_FOR_USER":
            WaitForUser()
        case "SHOW_ITEM_PROMPT":
            ShowItemPrompt(param)
        case "SHOW_PROGRESS":
            ShowProgress(param)
        case "SHOW_MESSAGE":
            ShowMessage(param)
        case "GET_PRICE_INPUT":
            GetPriceInput()
        default:
            WriteStatus("ERROR")
            WriteResponse("Unknown command: " . action)
    }
}

OpenURL(url) {
    ; Find and activate browser window
    if !ActivateBrowser() {
        WriteStatus("ERROR")
        WriteResponse("No browser window found")
        return
    }
    
    WriteStatus("NAVIGATING")
    
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
    WriteStatus("COMPLETED")
}

SearchWalmart(searchTerm) {
    ; First navigate to Walmart if not already there
    if !ActivateBrowser() {
        WriteStatus("ERROR")
        WriteResponse("No browser window found")
        return
    }
    
    WriteStatus("NAVIGATING")
    
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
    WriteStatus("COMPLETED")
}

GetCurrentURL() {
    if !ActivateBrowser() {
        WriteStatus("ERROR")
        WriteResponse("No browser window found")
        return
    }
    
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
    if ActivateBrowser() {
        WriteStatus("COMPLETED")
        WriteResponse("Browser activated")
    } else {
        WriteStatus("ERROR")
        WriteResponse("Could not find browser window")
    }
}

WaitForUser() {
    WriteStatus("WAITING_FOR_USER")
    ; This status will remain until next command
}

ActivateBrowser() {
    SetTitleMatchMode 2  ; Partial title match
    
    ; Try to find any browser window first, don't worry about Walmart specifically
    browsers := ["Chrome", "Firefox", "Edge", "Brave", "Opera", "Mozilla"]
    
    for browser in browsers {
        if WinExist(browser) {
            WinActivate browser
            ; Wait a moment for activation
            if WinWaitActive(browser, , 2) {
                return true
            }
        }
    }
    
    ; If no specific browser found, try to find any window that looks like a browser
    windows := WinGetList()
    for hwnd in windows {
        title := WinGetTitle(hwnd)
        ; Look for browser-like patterns in window titles
        if (InStr(title, "http") || InStr(title, "www.") || InStr(title, ".com") || 
            InStr(title, "Mozilla") || InStr(title, "Chrome") || InStr(title, "Edge")) {
            try {
                WinActivate(hwnd)
                if WinWaitActive(hwnd, , 1) {
                    return true
                }
            }
        }
    }
    
    return false
}

; Simplified GUI functions using MsgBox instead of custom GUI
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
    
    ; Yes = Continue, No = Save URL, Cancel = Record Price
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

ShowProgress(param) {
    ; Parse param: "current|total|item_name"
    parts := StrSplit(param, "|")
    current := parts[1]
    total := parts[2]
    item_name := parts.Length >= 3 ? parts[3] : ""
    
    message := "Processing item " . current . " of " . total
    if item_name != "" {
        message .= ": " . item_name
    }
    
    ; Show as a tooltip that disappears automatically
    ToolTip(message, 10, 10)
    SetTimer(() => ToolTip(), -3000)  ; Hide after 3 seconds
    
    WriteResponse("ok")
    WriteStatus("COMPLETED")
}

ShowMessage(param) {
    ; Simple message display
    MsgBox(param, "Walmart Shopping Assistant", "OK")
    WriteResponse("ok")
    WriteStatus("COMPLETED")
}

GetPriceInput() {
    ; Get price input from user
    result := InputBox("💰 Enter the current price (e.g., 3.45):", "Record Price", "w300 h150")
    
    if result.Result = "OK" && result.Text != "" {
        WriteResponse("price|" . result.Text)
    } else {
        WriteResponse("cancelled")
    }
    
    WriteStatus("COMPLETED")
}

UriEncode(str) {
    ; Simple URL encoding for search terms
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

; Hotkeys for manual control (optional)
; Ctrl+Shift+Q to quit
^+q::ExitApp()

; Ctrl+Shift+S to show status
^+s::{
    status := FileExist(StatusFile) ? FileRead(StatusFile) : "No status file"
    MsgBox("Current Status: " . status)
}