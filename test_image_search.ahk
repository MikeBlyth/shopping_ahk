; Test script for image search development
; Tests finding add_to_cart_left.png button on Walmart pages

#Requires AutoHotkey v2.0
#SingleInstance Force

; Hotkey to test image search
F1::TestImageSearch()

TestImageSearch() {
    ; Get screen dimensions
    ScreenWidth := SysGet(78)
    ScreenHeight := SysGet(79)
    
    ; Calculate search area (75-90% width, 20-80% height)
    SearchLeft := Round(ScreenWidth * 0.75)
    SearchTop := Round(ScreenHeight * 0.20)
    SearchRight := Round(ScreenWidth * 0.90)
    SearchBottom := Round(ScreenHeight * 0.80)
    
    ; Show search area info
    result := MsgBox("Screen: " . ScreenWidth . " x " . ScreenHeight . "`n"
        . "Search Area:`n" 
        . "Left: " . SearchLeft . " (75% of width)`n"
        . "Top: " . SearchTop . " (20% of height)`n"
        . "Right: " . SearchRight . " (90% of width)`n"
        . "Bottom: " . SearchBottom . " (80% of height)`n`n"
        . "Click Yes to search for add_to_cart_left.png`n"
        . "Click No to exit", "Image Search Test", "YesNo")
        
    if (result = "No")
        return
    
    ; Check if image file exists first
    if (!FileExist("images/add_to_cart_left.png")) {
        MsgBox("ERROR: images/add_to_cart_left.png file not found!`n`nCurrent directory: " . A_WorkingDir, "File Error")
        return
    }
    
    ; Search for 5 seconds maximum
    startTime := A_TickCount
    found := false
    attempts := 0
    
    MsgBox("Searching for add_to_cart_left.png... (5 second timeout)", "Searching", "T1")
    
    ; Search until found or timeout
    loop {
        attempts++
        
        ; Try ImageSearch - in v2 it throws on error or returns true on success
        try {
            if (ImageSearch(&FoundX, &FoundY, SearchLeft, SearchTop, SearchRight, SearchBottom, "*100 images/add_to_cart_left.png")) {
                ; Found the image
                found := true
                break
            }
        } catch as err {
            ; Error occurred - continue silently
        }
        
        ; Check if we've exceeded timeout
        if ((A_TickCount - startTime) >= 5000)
            break
            
        ; Brief pause before next attempt
        Sleep(50)
    }
    
    ; Report final result
    searchTime := A_TickCount - startTime
    if (found) {
        ClickBottom := FoundY + 100
        MsgBox("SUCCESS!`n`n"
            . "Found add_to_cart_left.png after " . searchTime . "ms (" . attempts . " attempts)`n"
            . "Location: X=" . FoundX . ", Y=" . FoundY . "`n`n"
            . "Click region would be:`n"
            . "X: " . FoundX . " to " . ScreenWidth . "`n" 
            . "Y: " . FoundY . " to " . (FoundY + 100), "Image Found!")
        
        ; Highlight the found button for 2 seconds
        HighlightButton(FoundX, FoundY)
    }
    
    ; Show failure message if not found within 5 seconds
    if (!found) {
        searchTime := A_TickCount - startTime
        MsgBox("FAILED`n`n"
            . "Could not find add_to_cart_left.png`n"
            . "Search time: " . searchTime . "ms`n"
            . "Attempts made: " . attempts . "`n`n"
            . "Check that:`n"
            . "1. You're on a Walmart product page`n"
            . "2. The 'Add to cart' button is visible`n"
            . "3. The add_to_cart_left.png image is correct", "Search Failed")
    }
}

; Function to visually highlight the found button
HighlightButton(x, y) {
    ; Create a simple highlight GUI
    myGui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "Button Highlight")
    myGui.BackColor := "Red"
    myGui.Show("x" . x . " y" . y . " w200 h50 NoActivate")
    
    Sleep(2000)
    myGui.Close()
}

; Show instructions
MsgBox("Instructions:`n"
    . "1. Navigate to a Walmart product page in your browser`n"
    . "2. Press F1 to test image search`n" 
    . "3. The script will show search parameters and look for add_to_cart_left.png`n`n"
    . "Press OK to continue...", "Image Search Test")