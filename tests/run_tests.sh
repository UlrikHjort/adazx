#!/bin/sh
# AdaZX tests: Z80 core (Fuse's per-cycle suite), assembler round trip,
# and the machines running BASIC, tapes and programs through the ROMs.
cd "$(dirname "$0")/.." || exit 1
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
check() {   # name, command output file, expected text
  if grep -q -- "$3" "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}

bin/fuse_test tests/z80/fuse/tests.in > "$T/fuse.out"
if cmp -s "$T/fuse.out" tests/z80/fuse/tests.expected; then
  echo "ok   Z80 core: Fuse tests (1356 tests, every bus cycle)"
else
  echo "FAIL Z80 core: Fuse tests"; diff "$T/fuse.out" tests/z80/fuse/tests.expected | head; fail=1
fi
bin/asm_test > "$T/asm.out"; check "assembler round trip" "$T/asm.out" " 0 failures"

if [ ! -f roms/48.rom ] || [ ! -f roms/zx81.rom ]; then
  echo "skipping machine tests: ROMs missing (see README)"; exit $fail
fi

# 48K: keywords typed in K / E mode, floating point, BEEP, BIN
bin/adazx --48 --headless 1000 --png "$T/a.png" --screen \
  --type '10 FOR i=1 TO 3: PRINT i*1.5,INT (PI*100),BIN 101: NEXT i\nRUN\n' > "$T/48.out"
check "48K BASIC typed in" "$T/48.out" "4.5             314"
# tokenizer + tape building + flash loading
cat > "$T/t.bas" <<'B'
#autostart 10
10 DEF FN f(a)=a*a: PRINT "TAPE";FN f(12);1E3/8
B
bin/adazx --basic "$T/t.bas" > /dev/null
bin/adazx --48 --headless 300 --png "$T/b.png" --screen "$T/t.tap" > "$T/tap.out"
check "48K tape, flash load" "$T/tap.out" "TAPE144125"
bin/adazx --48 --real-tape --headless 1300 --png "$T/c.png" --screen "$T/t.tap" > "$T/tap2.out"
check "48K tape, real-time load" "$T/tap2.out" "TAPE144125"
# TZX generalized data and CSW (RLE / Z-RLE) blocks, loaded in real time
if command -v python3 > /dev/null; then
  for m in gdb csw cswz; do
    python3 -I tests/make_tzx.py $m "$T/t.tap" "$T/$m.tzx"
    bin/adazx --48 --headless 1500 --png "$T/x.png" --screen "$T/$m.tzx" > "$T/$m.out"
    check "TZX $m block" "$T/$m.out" "TAPE144125"
  done
fi
# assembler, loader, RANDOMIZE USR
bin/adazx --asm examples/hello.asm > /dev/null
bin/adazx --48 --headless 300 --png "$T/d.png" --screen examples/hello.tap > "$T/asm.out"
check "48K machine code from the assembler" "$T/asm.out" "Hello from AdaZX!"
# 128K: menu, 128 BASIC editor, AY
bin/adazx --128 --headless 500 --png "$T/e.png" --screen "$T/t.bas" > "$T/128.out"
check "128K BASIC" "$T/128.out" "TAPE144125"
# snapshots round trip
bin/adazx --48 --headless 300 --png "$T/f.png" --save-snapshot "$T/s.z80" "$T/t.tap" > /dev/null
bin/adazx --48 --headless 10 --png "$T/g.png" --screen --load-snapshot "$T/s.z80" > "$T/z80.out"
check ".z80 snapshot save / load" "$T/z80.out" "TAPE144125"
bin/adazx --48 --headless 300 --png "$T/f.png" --save-snapshot "$T/s.sna" "$T/t.tap" > /dev/null
bin/adazx --48 --headless 10 --png "$T/g.png" --screen --load-snapshot "$T/s.sna" > "$T/sna.out"
check ".sna snapshot save / load" "$T/sna.out" "TAPE144125"
for m in 128 plus2 plus2a; do
  bin/adazx --$m --headless 400 --png "$T/f.png" --screen --save-snapshot "$T/s_$m.szx" "$T/t.bas" > "$T/run_$m.out"
  check "$m: BASIC through the menu" "$T/run_$m.out" "TAPE144125"
  bin/adazx --$m --headless 10 --png "$T/g.png" --screen --load-snapshot "$T/s_$m.szx" > "$T/szx_$m.out"
  check "$m: .szx snapshot save / load" "$T/szx_$m.out" "TAPE144125"
done
# RZX: record a session, play it back, same screen
bin/adazx --48 --headless 600 --png "$T/r1.png" --record-rzx "$T/r.rzx" \
  --type '10 FOR i=1 TO 5: PRINT i,RND: NEXT i\nRUN\n' > /dev/null
bin/adazx --48 --headless 600 --png "$T/r2.png" "$T/r.rzx" > /dev/null
if cmp -s "$T/r1.png" "$T/r2.png"; then echo "ok   RZX record and playback"
else echo "FAIL RZX record and playback"; fail=1; fi
# +3 discs: SAVE, CAT, LOAD in a new session, boot with the Loader
rm -f "$T/d.dsk"
bin/adazx --new-disc "$T/d.dsk"
printf '10 SAVE "disk" LINE 20\n20 PRINT "BOOTED";FN a()\n30 DEF FN a()=42\n' > "$T/boot.bas"
bin/adazx --plus3 --disc "$T/d.dsk" --headless 700 --png "$T/x.png" "$T/boot.bas" > /dev/null
printf '10 CAT\n' > "$T/cat.bas"
bin/adazx --plus3 --disc "$T/d.dsk" --headless 600 --png "$T/x.png" --screen "$T/cat.bas" > "$T/cat.out"
check "+3 disc: SAVE and CAT" "$T/cat.out" "DISK    .      1K"
bin/adazx --headless 700 --png "$T/x.png" --screen "$T/d.dsk" > "$T/boot.out"
check "+3 disc: boot with the Loader" "$T/boot.out" "BOOTED42"
# Interface 1: FORMAT a blank cartridge, SAVE, CAT; boot with RUN
rm -f "$T/m.mdr"
bin/adazx --new-mdr "$T/m.mdr"
bin/adazx --48 --mdr "$T/m.mdr" --headless 3000 --png "$T/x.png" --screen \
  --type 'FORMAT "m";1;"adazx"\n' \
  --type-at 1700 '10 PRINT "MICRODRIVE";6*7\nSAVE *"m";1;"run" LINE 10\n' \
  --type-at 2500 'CAT 1\n' > "$T/mdr.out"
check "Interface 1: FORMAT, SAVE, CAT" "$T/mdr.out" "^run"
bin/adazx --headless 1200 --png "$T/x.png" --screen "$T/m.mdr" > "$T/mdrrun.out"
check "Interface 1: autostart loads \"run\"" "$T/mdrrun.out" "MICRODRIVE42"
# ZX81: display, typing, LOAD of .p
bin/adazx --zx81 --headless 900 --png "$T/h.png" --screen \
  --type-at 200 '10 PRINT "ZX81";2**10\nRUN\n' > "$T/81.out"
check "ZX81 BASIC typed in" "$T/81.out" "ZX811024"
bin/adazx --zx81 --asm examples/zx81hello.asm > /dev/null
bin/adazx --zx81 --headless 900 --png "$T/i.png" --screen examples/zx81hello.p > "$T/81p.out"
check "ZX81 .p load and machine code" "$T/81p.out" "HELLO ZX81 FROM ADA"
bin/adazx --zx81 --headless 400 --png "$T/j.png" --save-snapshot "$T/z.azx" examples/zx81hello.p > /dev/null
bin/adazx --zx81 --headless 900 --png "$T/k.png" --screen --load-snapshot "$T/z.azx" > "$T/azx.out"
check ".azx snapshot (ZX81)" "$T/azx.out" "HELLO ZX81 FROM ADA"
# ZX80: typing (keyword keys, SHIFT operator tokens), .o build / LOAD,
# SAVE, machine code in a REM line
bin/adazx --zx80 --headless 1500 --png "$T/x.png" --screen \
  --type-at 100 '10 PRINT "HELLO",PEEK(16384)\nRUN\n' > "$T/80.out"
check "ZX80 BASIC typed in" "$T/80.out" "HELLO   255"
printf '10 FOR I=1 TO 3\n20 PRINT I*I;\n30 NEXT I\n' > "$T/p.b80"
bin/adazx --zx80 --basic "$T/p.b80" > /dev/null
bin/adazx --zx80 --headless 1500 --png "$T/x.png" --screen "$T/p.o" > "$T/80o.out"
check "ZX80 .o through LOAD" "$T/80o.out" "149"
bin/adazx --zx80 --headless 900 --png "$T/x.png" --save-tape "$T/s.o" \
  --type-at 300 '10 PRINT 5\nSAVE\n' > /dev/null
bin/adazx --list "$T/s.o" > "$T/80s.out"
check "ZX80 SAVE as .o" "$T/80s.out" "10 PRINT 5"
bin/adazx --zx80 --headless 1500 --png "$T/x.png" --screen examples/zx80hello.asm > "$T/80a.out"
check "ZX80 machine code (PRINT USR)" "$T/80a.out" "^385"
# ZX81 line counter: the top-left quadrant block (CHR$ 1) is one run of
# 4 scanlines (8 PNG rows), not split across the character row
printf '10 PRINT CHR$ 1\n' > "$T/q.b81"
bin/adazx --zx81 --headless 600 --png "$T/q.png" "$T/q.b81" > /dev/null
python3 tests/png_runs.py "$T/q.png" 90 > "$T/q.out"
check "ZX81 character rows start at line 0" "$T/q.out" "^96:8 "
# ZX81 AY sound boards: tone A, period 200, at each board's AY clock
bin/adazx --zx81 --zonx --headless 600 --png "$T/x.png" --wav "$T/zonx.wav" \
  tests/zonx.asm > /dev/null
python3 tests/wav_freq.py "$T/zonx.wav" > "$T/zonx.out"
check "ZX81 ZON X-81 sound board (508 Hz)" "$T/zonx.out" "^50[789]$"
bin/adazx --zx81 --quicksilva --headless 600 --png "$T/x.png" --wav "$T/qs.wav" \
  tests/quicksilva.asm > /dev/null
python3 tests/wav_freq.py "$T/qs.wav" > "$T/qs.out"
check "ZX81 Quicksilva sound board (254 Hz)" "$T/qs.out" "^25[345]$"
# Patrik Rak's z80test 1.2a (MIT, tests/z80test): all flags and
# registers, MEMPTR, and flags after CCF; printed output via --print-log
for t in z80full z80memptr z80ccf; do
  bin/adazx --headless 50000 --png "$T/x.png" --print-log \
    tests/z80test/$t.tap > "$T/$t.out"
  check "z80test $t" "$T/$t.out" "Result: all tests passed"
done
# Richard Butler's 48K timing tests (tests/timing): instruction timings
# with and without contention, and the floating bus (35 - 37)
bin/adazx --headless 20000 --png "$T/x.png" --print-log --type-at 300 '\n' \
  --type-at 12000 ' ' --type-at 13000 ' ' --type-at 14000 ' ' \
  --type-at 15000 ' ' tests/timing/timing_tests_48k_v1.0.z80 > "$T/tm.log"
echo "pass $(grep -c Pass "$T/tm.log") fail $(grep -c Fail "$T/tm.log")" > "$T/tm.out"
check "48K timing tests (all 72 cases, floating bus)" "$T/tm.out" "^pass 7[2-9] fail 0$"
# DivMMC with esxDOS (only when roms/esxmmc.bin and roms/esxdos/ exist:
# esxDOS is not part of AdaZX): a card built from a folder, a tape loaded
# through esxDOS's tape emulation, a file saved to the card
if [ -f roms/esxmmc.bin ] && [ -d roms/esxdos ]; then
  rm -rf "$T/sdf" && mkdir -p "$T/sdf/My Programs"
  printf '10 PRINT "FROM THE SD CARD"\n' > "$T/sdf/My Programs/hello.bas"
  bin/adazx --basic "$T/sdf/My Programs/hello.bas" > /dev/null
  rm "$T/sdf/My Programs/hello.bas"
  bin/adazx --sd-dir "$T/sdf" --headless 1500 --png "$T/x.png" --screen \
    --type-at 450 '.cd myprog~1\n' --type-at 550 '.tapein hello.tap\n' \
    --type-at 650 'LOAD ""\n' --type-at 900 'RUN\n' \
    --type-at 1000 'SAVE *"saved.bas"\n' --type-at 1200 '.ls\n' > "$T/sd.out"
  check "DivMMC: esxDOS loads a tape from a folder card" "$T/sd.out" "FROM THE SD CARD"
  check "DivMMC: esxDOS saves to the card" "$T/sd.out" "SAVED.BAS"
else
  echo "skip DivMMC (no roms/esxmmc.bin and roms/esxdos/)"
fi
# Debugger: a breakpoint with a condition (stops at the frame interrupt
# only when FRAMES = $40) and the profiler
bin/adazx --headless 300 --png "$T/x.png" --break-if 38 '[23672] = $40 and iy = $5c3a' \
  --monitor 'm 5c78 5c78' > "$T/bc.out"
check "conditional breakpoint" "$T/bc.out" "^5C78  40 "
printf '10 FOR I=1 TO 200\n20 LET X=SQR I\n30 NEXT I\n' > "$T/prof.bas"
bin/adazx --headless 600 --png "$T/x.png" --profile "$T/prof.bas" > "$T/prof.out"
check "profiler (calculator's LDIR on top)" "$T/prof.out" "\$33C3 .*LDIR"
exit $fail
