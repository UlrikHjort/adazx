; TC2048 8x1 colour test: bitmap all paper, the 8x1 attributes at &6000
; alternate per pixel line between paper 2 (red) and paper 4 (green)
            org 32768
start:      ld hl,$4000
            ld de,$4001
            ld bc,6143
            ld (hl),0
            ldir
            ld hl,$6000
            ld b,8              ; character rows 0 - 7 (the top third)
.grp        push bc
            ld c,8              ; pixel line in the character (256 apart)
            ld a,$10            ; paper 2
.line       ld d,32
.col        ld (hl),a
            inc hl
            dec d
            jr nz,.col
            ld de,224
            add hl,de
            xor $30             ; $10 <-> $20 (paper 2 / paper 4)
            dec c
            jr nz,.line
            ld de,-2048+32
            add hl,de
            pop bc
            djnz .grp
            ld a,2              ; 8x1 colour mode
            out ($ff),a
.wait       jr .wait
