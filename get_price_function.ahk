#include <FindTextv2>

; Load character library for price recognition - call this once at startup
LoadPriceCharacters() {
    ; Combine all characters into one Text string
    Text := "|<$>*50$26.01y000TU007s00Dzs0DzzU7zzw3zzz1zzzkTs3w7s073w00Ez000Dk003w000z000Dw003zs00Tzw07zzk0zzz07zzs0Tzz00zzs00zy001zU007s001y000TU007sU01yC00zXs0TszzzwDzzz3zzzUTzzk1zzk03zU00Dk003w000z000Dk003w08"
    Text .= "|<1>*147$17.0000000003zUDz0zy3zwDzszznzzbzzDzyTjwyTtsznVza3z87y0Dw0Ts0zk1zU3z07y0Dw0Ts0zk1zU3z07y0Dw0Ts0zk1zU3z07y0Dw0Ts0zk00000000001"
    Text .= "|<2>*148$26.00000000000000zz00zzw0zzzUTzzw7zzzVzzzsTxzy7k3zlk0TwE03z000zk00Dw003z001zk00Tw007y003zU00zk00Tw00Dy007z003zk01zs00zw00zy00Ty00Dz00DzU07zk01zzzsTzzz7zzzlzzzwTzzz7zzzlzzzw0000000000000U"
    Text .= "|<3>*147$26.000000000zzzsDzzy3zzzUzzzsDzzy3zzzUzzzs007y003z001zU01zk00zs00Tw00Dy007z007zU01zz00Tzw07zzk1zzy007zU00Tw003z000zs00Dy003zU00zt00DyQ07z7s7zlzzzwTzzy7zzz1zzzUDzzk0zzk01zU0000000000000000008"
    Text .= "|<4>*146$32.0000000000000Ty000DzU003zs001zy000zzU00Dzs007zy003zzU00zzs00Try00DtzU03yTs01z7y00TVzU0DsTs07w7y01z1zU0zUTs0Tk7y07w1zU3y0Ts0z07y0Dzzzz3zzzzkzzzzwDzzzz3zzzzkzzzzw001zk000Ts0007y0001zU000Ts0007y0001zU000Ts00000000000000002"
    Text .= "|<5>*147$27.0000000007zzz0zzzs7zzz0zzzs7zzz0zzzs7zzz0z0007s000z0007s000z0007s000z0007zy00zzy07zzw0zzzk7zzy001zs007zU00Tw001zU00Dw001zU00Dw003zU00TwA07zVs3zsDzzz1zzzkDzzw1zzz0Dzzk0Tzs00Tk000000000000000U"
    Text .= "|<6>*146$31.0000000000003zs00Dzz00TzzU0Tzzk0Tzzs0Tzzw0Tzky0Dz030Dy0007y0007z0003z0001zU001zUzk0zlzy0TtzzUDxzzs7zzzw3zyzz1zs3zUzs0zsTs0DwDw07y7y03z3z01zVzU0zkzk0TsDs0Dw7y0Dy1zUDy0zyzz0Dzzz03zzz00zzz00Dzz001zy000Dw00000000000000000U"
    Text .= "|<7>*152$24.000000000000zzzwzzzwzzzwzzzwzzzwzzzwzzzw00Tw00Ts00Ts00zk00zk01zk01zU03zU03z007z007y00Dy00Dw00Dw00Tw00Ts00zs00zk01zk01zU03zU03z007z007y007y00Dy00Dw00Tw00Ts000000000000000000U"
    Text .= "|<8>*146$30.0000007zk00Tzy00zzz01zzzU3zzzk7zzzs7z0zsDy0TsDw0DsDw0DwDw0DwDw0Ds7w0Ts7y0Ts3zVzk1zzzU0zzz00Dzw00zzy01zzzU7zzzk7y0zsDw0TwDw0DwTs0DwTs0DwTs0DwTs0DwTw0DwDy0TwDznzwDzzzs7zzzk3zzzU1zzz00Tzw001zU000000000000000000000U"
    Text .= "|<9>*148$31.000000000000zy001zzk01zzy01zzzU1zzzs1zzzw0zs7z0zs1zUTs0TsDw0DwDw03y7y01z3z00zlzU0Tszs0TwDw0Dy7z0Dz3zkDzUzzzzkTzzzs7zzjw1zzjy0Dz7y01y3z0001zU001zk000zk000zs300zs1s1zw0zzzw0Tzzw0Dzzw07zzw03zzw00Tzs001z00000000000000000000000E"
    Text .= "|<0>*147$33.00000007zU007zz001zzw00Tzzs07zzzU1zzzw0Dz7zk3zUDz0zs0zs7z03z0zk0TwDy01zVzk0DwDw01zVzU0DyDw01zlzU07yDw00zlzU07yDw00zlzU07yDw01zlzU0DyDw01zVzk0Dw7y01zUzk0Tw7z03z0Tw0zs3zkTy0Dzzzk0zzzw07zzz00Tzzk00zzw001zy0003y000000000000000000000000U"
    Text .= "|<.>*143$13.000E0z0zUzsTwDy7z1z0T00000U"
    
    ; Add the combined character set to library
    FindText().PicLib(Text, 1)
}

; Extract price from screen region - returns price without $ (e.g. "13.98") or empty string if failed
; Silent operation - no messages, failures ignored
get_price(x1, y1, x2, y2) {
    ; Character recognition with stored character library - only large price font
    priceChars := "$1234567890."
    X := ""
    Y := ""
    
    ; Use stricter error tolerance and exact size matching to avoid smaller text
    if (ok := FindText(&X, &Y, x1, y1, x2, y2, 0.05, 0.05, FindText().PicN(priceChars))) {
        ; Use OCR to assemble characters into text with tighter spacing
        if (ocrResult := FindText().OCR(ok, 5, 3)) {
            extractedText := ocrResult.text
        } else {
            return ""  ; OCR assembly failed - silent failure
        }
    } else {
        return ""  ; No price characters found - silent failure
    }
    
    ; Clean up the OCR result and extract price
    cleanedText := StrReplace(extractedText, "*", ".")  ; Replace * with . for decimal point
    
    ; Extract price pattern - $ is optional but require exactly 2 decimal places
    pricePattern := ""
    
    ; Try with $ first
    if RegExMatch(cleanedText, "\$(\d+\.\d{2})", &match) {
        pricePattern := match[1]  ; Return without $
    } else if RegExMatch(extractedText, "\$(\d+)\*(\d{2})", &match) {
        ; Handle the * case directly  
        pricePattern := match[1] . "." . match[2]  ; Return without $
    } else if RegExMatch(cleanedText, "(\d+\.\d{2})", &match) {
        ; No $ found, but valid ##.## pattern
        pricePattern := match[1]
    } else if RegExMatch(extractedText, "(\d+)\*(\d{2})", &match) {
        ; No $ found, * for decimal
        pricePattern := match[1] . "." . match[2]
    }
    
    return pricePattern  ; Returns "13.98" or "" if no valid price found
}