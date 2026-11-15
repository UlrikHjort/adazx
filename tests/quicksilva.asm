; Quicksilva test: tone A with period 200 (812500 / 16 / 200 = 254 Hz)
            org 16514
            ld hl,regs
            ld b,4
.next       ld a,(hl)
            ld ($7fff),a        ; register
            inc hl
            ld a,(hl)
            ld ($7ffe),a        ; value
            inc hl
            djnz .next
            ret
regs:       db 0,200, 1,0, 7,$3e, 8,15
