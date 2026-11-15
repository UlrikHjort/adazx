; TC2068 AY test (ports &F5 register, &F6 data): tone A, period 200
; (1750000 / 16 / 200 = 547 Hz)
            org 32768
start:      ld hl,regs
            ld b,4
.next       ld a,(hl)
            out ($f5),a
            inc hl
            ld a,(hl)
            out ($f6),a
            inc hl
            djnz .next
.wait       jr .wait
regs:       db 0,200, 1,0, 7,$3e, 8,15
