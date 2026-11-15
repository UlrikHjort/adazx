; ZON X-81 test: tone A with period 200 (1625000 / 16 / 200 = 508 Hz)
            org 16514
            ld hl,regs
            ld b,4
.next       ld a,(hl)
            out ($df),a         ; register
            inc hl
            ld a,(hl)
            out ($0f),a         ; value
            inc hl
            djnz .next
            ret
regs:       db 0,200, 1,0, 7,$3e, 8,15
