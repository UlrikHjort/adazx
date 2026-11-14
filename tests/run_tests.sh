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
exit $fail
