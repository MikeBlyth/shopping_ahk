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
        message .= "`nPage should be loaded. Add to cart if desired."
    } else {
        message := "🔍 New item: " . item_name . "`n"
        message .= "Search results displayed. Find the correct product, navigate to it, and add to cart if desired."
    }
    
    message .= "`n`nAfter reviewing/adding to cart:"
    
    ; Show informational message first
    MsgBox(message, "Item: " . item_name, "OK")
    
    ; Now ask for price
    price_result := InputBox("💰 Enter the price if you added this item to cart`n(Leave blank or enter 0 to skip):", "Price for " . item_name, "w300 h150")
    
    if price_result.Result = "OK" {
        price_text := price_result.Text
        
        ; Check if price is blank or zero
        if price_text = "" || price_text = "0" || price_text = "0.00" {
            ; No purchase, but for new items, still capture URL
            if !is_known {
                ; Get current URL from browser
                Send("^l")  ; Focus address bar
                Sleep(100)
                Send("^c")  ; Copy URL
                Sleep(100)
                current_url := A_Clipboard
                A_Clipboard := ""  ; Clear clipboard
                
                WriteResponse("save_url_only|" . current_url)
            } else {
                WriteResponse("continue")
            }
        } else {
            ; Valid price entered - now ask for quantity
            qty_result := InputBox("🛒 How many " . item_name . " did you add to cart?", "Quantity", "w300 h150", "1")
            
            if qty_result.Result = "OK" && qty_result.Text != "" {
                quantity := qty_result.Text
                
                ; For new items, also capture the URL
                if !is_known {
                    ; Get current URL from browser
                    Send("^l")  ; Focus address bar
                    Sleep(100)
                    Send("^c")  ; Copy URL
                    Sleep(100)
                    current_url := A_Clipboard
                    A_Clipboard := ""  ; Clear clipboard
                    
                    WriteResponse("purchase_new|" . price_text . "|" . quantity . "|" . current_url)
                } else {
                    WriteResponse("purchase|" . price_text . "|" . quantity)
                }
            } else {
                ; Cancelled quantity - for new items, still save URL without purchase
                if !is_known {
                    ; Get current URL from browser
                    Send("^l")  ; Focus address bar
                    Sleep(100)
                    Send("^c")  ; Copy URL
                    Sleep(100)
                    current_url := A_Clipboard
                    A_Clipboard := ""  ; Clear clipboard
                    
                    WriteResponse("save_url_only|" . current_url)
                } else {
                    WriteResponse("continue")
                }
            }
        }
    } else {
        ; Cancelled price dialog - for new items, still save URL
        if !is_known {
            ; Get current URL from browser
            Send("^l")  ; Focus address bar
            Sleep(100)
            Send("^c")  ; Copy URL
            Sleep(100)
            current_url := A_Clipboard
            A_Clipboard := ""  ; Clear clipboard
            
            WriteResponse("save_url_only|" . current_url)
        } else {
            WriteResponse("continue")
        }
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