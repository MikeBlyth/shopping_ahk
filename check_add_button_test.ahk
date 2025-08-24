#Requires AutoHotkey v2.0
#SingleInstance Force

; Include the existing image search function
#Include lib\image_search_function.ahk

; Quit hotkey
^+q::ExitApp()

; Global variables
buttonRegion := {left: 0, top: 0, right: 0, bottom: 0}
buttonFound := false
testDialog := ""
overrideButton := ""

; F1: Find button and set flag
F1::FindButton()

; Show dialog on startup
ShowDialog()

FindButton() {
    global buttonRegion, buttonFound
    
    ; Use the existing image search function
    result := FindAddToCartButton(5000)
    
    if (result.found) {
        buttonRegion := result.clickRegion
        buttonFound := true
        MsgBox("Button found and flag set to true!", "Success", "T2")
    } else {
        buttonFound := false
        MsgBox("Button not found", "Failed", "T2")
    }
}

ShowDialog() {
    global testDialog, overrideButton
    
    ; Create dialog
    testDialog := Gui("+AlwaysOnTop", "Purchase Dialog")
    
    ; Add fields
    testDialog.Add("Text", "x10 y10", "Price:")
    testDialog.Add("Edit", "x50 y5 w80 vPrice")
    testDialog.Add("Text", "x150 y10", "Quantity:")
    testDialog.Add("Edit", "x200 y5 w50 vQuantity", "1")
    
    ; Override button with warning emoji and red outline
    overrideButton := testDialog.Add("Button", "x10 y40 w120 h35 BackgroundRed cWhite", "⚠️ Override")
    overrideButton.OnEvent("Click", (*) => MsgBox("Override clicked"))
    
    ; Cancel button
    testDialog.Add("Button", "x140 y40 w80 h35", "Cancel").OnEvent("Click", (*) => ExitApp())
    
    ; Show dialog
    testDialog.Show("w260 h90")
}

; Click handler - changes button when cart button is clicked
~LButton:: {
    global buttonRegion, buttonFound, overrideButton
    
    if (!buttonFound || !overrideButton)
        return
    
    ; Get click position
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    
    ; Check if click is in button region
    if (mouseX >= buttonRegion.left && mouseX <= buttonRegion.right && 
        mouseY >= buttonRegion.top && mouseY <= buttonRegion.bottom) {
        
        ; Change to checkmark emoji, new text, and green outline
        overrideButton.Text := "✅ Add & Purchase"
        overrideButton.Opt("BackgroundGreen cWhite")
        
        ; Stop monitoring
        buttonFound := false
        
        MsgBox("Button changed to checkmark!", "Success", "T2")
    }
}

; Show instructions
MsgBox("Simple Test:`n"
    . "1. Navigate to Walmart product page`n"
    . "2. Press F1 to find Add to Cart button`n"
    . "3. Click the Add to Cart button on webpage`n"
    . "4. ⚠️ Override button should change to ✅ Add & Purchase`n"
    . "5. Ctrl+Shift+Q to quit", "Instructions")