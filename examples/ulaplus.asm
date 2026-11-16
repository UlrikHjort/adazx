; ULAplus demo: all 64 palette entries as bars (bin/adazx --ulaplus)
; Each character row uses one CLUT (FLASH / BRIGHT select it); the 8 ink
; and 8 paper entries of the four CLUTs get a ramp through the colours.
            org 32768
start:      ld bc,$bf3b         ; fill the 64 entries: GGGRRRBB ramp
            ld e,0
.pal        ld b,$bf
            out (c),e           ; register = entry
            ld b,$ff
            ld a,e              ; colour: spread the index over G, R, B
            rlca
            rlca
            xor e
            out (c),a
            inc e
            ld a,e
            cp 64
            jr nz,.pal
            ld b,$bf
            ld a,64             ; mode register: palette on
            out (c),a
            ld b,$ff
            ld a,1
            out (c),a
            ld hl,$4000         ; bitmap: left half of each cell set
            ld de,$4001
            ld bc,6143
            ld (hl),$f0
            ldir
            ld hl,$5800         ; attributes: row r -> CLUT r mod 4,
            ld c,24             ; column c -> ink / paper c mod 8
            ld d,0
.row        ld b,32
            ld e,0
.col        ld a,d              ; CLUT in bits 6 - 7
            and 3
            rrca
            rrca
            ld (scratch),a
            ld a,e
            and 7
            ld (scratch+1),a    ; ink
            ld a,e
            inc a
            and 7
            rlca
            rlca
            rlca                ; paper in bits 3 - 5
            push hl
            ld hl,scratch+1
            or (hl)
            dec hl
            or (hl)
            pop hl
            ld (hl),a
            inc hl
            inc e
            djnz .col
            inc d
            dec c
            jr nz,.row
            ld bc,$bf3b         ; border: CLUT 0 paper entry 8 + 1
            ld a,0
            out ($fe),a
.wait       jr .wait
scratch:    db 0,0
