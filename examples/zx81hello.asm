; AdaZX example for the ZX81: the code lives in a REM line at 16514
;   bin/adazx --zx81 --asm examples/zx81hello.asm  -> zx81hello.p
;   bin/adazx --zx81 examples/zx81hello.asm        -> assemble and run

PRINT_CH    equ $0010           ; RST 10: print the character in A

            org 16514
start:      ld hl,message
.next       ld a,(hl)
            cp $ff
            ret z
            rst PRINT_CH
            inc hl
            jr .next

; ZX81 character codes: "HELLO ZX81 FROM ADA"
message:    db $2d,$2a,$31,$31,$34,$00,$3f,$3d,$24,$1d,$00
            db $2b,$37,$34,$32,$00,$26,$29,$26,$ff
