; ULAplus test: palette entry 15 (CLUT 0 paper 7) = pure red (GGGRRRBB =
; %00011100), entry 8 (border 0) = pure blue; palette mode on
            org 32768
start:      ld bc,$bf3b
            ld a,15             ; register 15
            out (c),a
            ld b,$ff
            ld a,%00011100      ; red
            out (c),a
            ld b,$bf
            ld a,8              ; register 8: border colour 0
            out (c),a
            ld b,$ff
            ld a,%00000011      ; blue
            out (c),a
            ld b,$bf
            ld a,64             ; mode register
            out (c),a
            ld b,$ff
            ld a,1              ; palette on
            out (c),a
            xor a
            out ($fe),a         ; border 0
.wait       jr .wait
