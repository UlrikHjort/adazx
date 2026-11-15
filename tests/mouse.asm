; Kempston mouse test: X, Y and the buttons stored at 23296 (&5B00)
            org 32768
start:      ld bc,$fbdf         ; X
            in a,(c)
            ld ($5b00),a
            ld b,$ff            ; Y (&FFDF)
            in a,(c)
            ld ($5b01),a
            ld b,$fa            ; buttons (&FADF)
            in a,(c)
            ld ($5b02),a
.wait       jr .wait
