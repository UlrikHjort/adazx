; TC2048 512-pixel mode test: screen 0 all ink, screen 1 all paper; in
; mode 6 every 16-pixel column is 8 ink pixels and 8 paper pixels
            org 32768
start:      ld hl,$4000
            ld de,$4001
            ld bc,6143
            ld (hl),$ff
            ldir
            ld hl,$6000
            ld de,$6001
            ld bc,6143
            ld (hl),0
            ldir
            ld a,6              ; 512 x 192, black on white
            out ($ff),a
.wait       jr .wait
