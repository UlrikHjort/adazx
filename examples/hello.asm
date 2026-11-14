; AdaZX example: print a message with the ROM and draw colour bars
;   bin/adazx --asm examples/hello.asm    -> hello.tap (with a BASIC loader)
;   bin/adazx examples/hello.asm          -> assemble and run

ROM_CLS     equ $0daf           ; clear the screen
CHAN_OPEN   equ $1601           ; open channel A
ATTR        equ $5800

            org $8000

macro       print_at row, col
            ld a,22             ; AT control code
            rst $10
            ld a,row
            rst $10
            ld a,col
            rst $10
endm

start:      call ROM_CLS
            ld a,2              ; upper screen
            call CHAN_OPEN
            print_at 2, 6
            ld hl,message
.next       ld a,(hl)
            or a
            jr z,.bars
            rst $10
            inc hl
            jr .next

.bars       ld hl,ATTR + 8*32   ; colour bars in rows 8..15
            ld c,8
.row        ld b,32
.col        ld a,b
            and %00111000       ; paper colour from the column
            ld (hl),a
            inc hl
            djnz .col
            dec c
            jr nz,.row
            ret

message:    db "Hello from AdaZX!", 0

            if $ > $9000
            error "too long"
            endif

checks:     rept 3
            nop
            endr
            end start
