; Simple test script - just shows "Click OK to continue" dialog
; File paths for communication
#SingleInstance force

ScriptDir := A_ScriptDir
CommandFile := ScriptDir . "\ahk_command.txt"
StatusFile := ScriptDir . "\ahk_status.txt"
ResponseFile := ScriptDir . "\ahk_response.txt"

; Global variables
UserReady := false
WaitingForUser := false

; Initialize
WriteStatus("WAITING_FOR_HOTKEY")
MsgBox("Simple test script ready!`n`nPress Ctrl+Shift+R when ready", "Test Script", "OK")

; Hotkey to signal readiness
^+r::{
    global UserReady, WaitingForUser, TargetWindowHandle
    
    if WaitingForUser {
        WaitingForUser := false
        WriteStatus("READY")
    } else {
        UserReady := true
        WriteStatus("READY")
        TargetWindowHandle := WinExist("A")

        if !TargetWindowHandle {
            MsgBox("Could not find an active window handle.")
            ExitApp
        }
        MsgBox("Ready signal received!", "Test Script", "OK")
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
    WriteStatus("PROCESSING")
    MsgBox("Processing command: " . command)
    ; Debug: Write received command to file
    FileAppend("Received command: '" . command . "'`n", "command_debug.txt")
    
    if InStr(command, "OPEN_URL") {
        ; Extract URL
        url := SubStr(command, InStr(command, "|") + 1)
        MsgBox("Opening URL: " . url, "Open URL", "OK")
        ; Navigate to URL
        WinActivate(TargetWindowHandle)
        WinWaitActive(TargetWindowHandle)
        Send("^l")
        Sleep(100)
        Send("^a")
        Sleep(100)
        SendInput(url)
        Sleep(100)
        Send("{Enter}")
        Sleep(2000)
        
        WriteStatus("COMPLETED")
        
    } else if InStr(command, "SHOW_ITEM_PROMPT") {
        ; Debug: Log that we matched this command
        FileAppend("MATCHED SHOW_ITEM_PROMPT`n", "command_debug.txt")
        
        ; Just show simple dialog
        MsgBox("Click OK to continue to next item", "Continue?", "OK")
        WriteResponse("continue")
        WriteStatus("COMPLETED")
        
    } else if InStr(command, "SHOW_PROGRESS") {
        ; Do nothing for progress
        MsgBox("SHOW_PROGRESS Running")
        WriteStatus("COMPLETED")
        
    } else if InStr(command, "SHOW_MESSAGE") {
        ; Show message
        msg := SubStr(command, InStr(command, "|") + 1)
        MsgBox(msg, "Message", "OK")
        WriteResponse("ok")
        WriteStatus("COMPLETED")
        
    } else {
        ; Unknown command
        WriteStatus("ERROR")
        WriteResponse("Unknown command")
    }
}

WriteStatus(status) {
    try {
        if FileExist(StatusFile)
            FileDelete(StatusFile)
        FileAppend(status, StatusFile)
    }
}

WriteResponse(response) {
    try {
        if FileExist(ResponseFile)
            FileDelete(ResponseFile)
        FileAppend(response, ResponseFile)
    }
}

; Exit hotkey
^+q::{
    WriteStatus("SHUTDOWN")
    ExitApp()
}