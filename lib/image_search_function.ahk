; Image search function for purchase detection
; Returns object with found status, coordinates, and timing

FindAddToCartButton(timeoutMs := 5000) {
    ; Get screen dimensions
    ScreenWidth := SysGet(78)
    ScreenHeight := SysGet(79)
    
    ; Calculate search area (75-90% width, 20-80% height)
    SearchLeft := Round(ScreenWidth * 0.75)
    SearchTop := Round(ScreenHeight * 0.20)
    SearchRight := Round(ScreenWidth * 0.90)
    SearchBottom := Round(ScreenHeight * 0.80)
    
    ; Check if image file exists
    if (!FileExist("images/add_to_cart_left.png")) {
        return {found: false, error: "Image file not found", attempts: 0, searchTime: 0}
    }
    
    ; Search until found or timeout
    startTime := A_TickCount
    found := false
    attempts := 0
    FoundX := 0
    FoundY := 0
    
    loop {
        attempts++
        
        try {
            if (ImageSearch(&FoundX, &FoundY, SearchLeft, SearchTop, SearchRight, SearchBottom, "*100 images/add_to_cart_left.png")) {
                found := true
                break
            }
        } catch {
            ; Continue on error
        }
        
        ; Check timeout
        if ((A_TickCount - startTime) >= timeoutMs)
            break
            
        Sleep(50)
    }
    
    searchTime := A_TickCount - startTime
    
    ; Return result object
    if (found) {
        return {
            found: true,
            x: FoundX,
            y: FoundY,
            clickRegion: {
                left: FoundX,
                top: FoundY,
                right: ScreenWidth,
                bottom: FoundY + 100
            },
            attempts: attempts,
            searchTime: searchTime
        }
    } else {
        return {
            found: false,
            attempts: attempts,
            searchTime: searchTime
        }
    }
}