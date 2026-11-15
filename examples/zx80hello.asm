; AdaZX example for the ZX80: the code lives in a REM line at 16427 and
; is called by 2 PRINT USR(16427), which prints what it returns in HL.
;   bin/adazx --zx80 --asm examples/zx80hello.asm  -> zx80hello.o
;   bin/adazx --zx80 examples/zx80hello.asm        -> assemble and run
; (the code must not contain the byte $76: it would end the REM line;
; the ROM's RST $10 only prints inside a PRINT statement on the ZX80)

            org 16427
start:      ld bc,0             ; sum of the squares 1 .. 10
            ld e,1
.next       ld l,e              ; HL = E * E by repeated addition
            ld h,0
            ld d,e
            ld a,0
            ld h,a
            ld l,a
.mul        ld a,l
            add a,e
            ld l,a
            jr nc,.nc
            inc h
.nc         dec d
            jr nz,.mul
            ld a,c              ; BC += HL
            add a,l
            ld c,a
            ld a,b
            adc a,h
            ld b,a
            inc e
            ld a,e
            cp 11
            jr nz,.next
            ld h,b              ; the ZX80's USR returns HL
            ld l,c
            ret                 ; HL = 385
