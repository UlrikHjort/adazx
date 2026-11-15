# AdaZX

A ZX Spectrum (48K, 128K, +2, +2A, +3 with its disc drive), Pentagon 128, Timex TC2048, Sinclair ZX81 and ZX80
emulator written in Ada 2012 with GtkAda, with **Forge**: a Z80 assembler
IDE, Sinclair BASIC editor, source-level debugger and graphics editors
around the running machine. It is the Sinclair sibling of AdaC64
(`../c64`) and AdaBeeb (`../bbc`).

## Build and run

    make                     # GNAT, gprbuild, GtkAda, libpulse-dev,
                             # libgtksourceview-4 (Forge's editor)
    bin/adazx                # 48K Spectrum (or the model used last time)
    bin/adazx --128          # also --plus2, --plus2a, --plus3, --pentagon,
                             # --tc2048, --zx81, --zx80
    bin/adazx game.tzx       # autostart (also .tap .z80 .szx .sna .azx .rzx .p .81
                             # .scr .bas .b81 .asm)
    bin/adazx-forge          # Forge as the main window
    make tests               # Z80 core, assembler, machine tests
    make zexall              # ZEXALL instruction exerciser (~1 minute)

Tapes are started the way a user would: `LOAD ""` on the 48K and the
ZX81, the "Tape Loader" menu entry on the 128K models. `.bas` / `.b81`
files are tokenised and RUN; `.asm` files are assembled and started with
`RANDOMIZE USR` (Spectrum) or put into a REM line at 16514 (ZX81).

Options: `--trd FILE` / `--new-trd FILE` / `--beta` (TR-DOS), `--sd FILE` / `--sd-dir DIR` / `--new-sd FILE` / `--divmmc` (DivMMC with esxDOS), `--nmi-at FRAME`, `--print-log` (echo what the ROM prints to stdout, never stop at scroll?), `--roms DIR`, `--disc FILE` (+3 drive A), `--if1`, `--mdr FILE` (Interface 1, cartridge in Microdrive 1), `--1k` (ZX81 without the 16K pack), `--zonx` / `--quicksilva` (ZX81 sound board), `--ram2000`
(ZX81 8K RAM at &2000), `--issue2`, `--real-tape` (no flash loading),
`--attach FILE`, and for testing `--headless N` (run N frames, save
`shot.png`), `--png FILE`, `--type TEXT` (`\n` = ENTER), `--type-at FRAME
TEXT`, `--screen` (print the screen as text), `--wav FILE`, `--dump FILE`,
`--save-tape FILE`, `--record-rzx FILE`, `--load-snapshot` / `--save-snapshot FILE`, `--break
ADDR`, `--monitor "r;d 8000;m 5c00"`. Command-line tools: `--new-disc FILE` (blank +3 disc), `--new-mdr FILE` (blank cartridge), `--basic SRC`
(tokenise into a .tap, or a .p with `--zx81`), `--list FILE` (list the
BASIC in a .tap / .p), `--asm SRC`.

## ROMs

The ROMs are not part of AdaZX and `roms/` is not in version control.
They are looked for in `--roms DIR`, `roms/` next to `bin/`, `roms/` in
the current directory, `/usr/share/spectrum-roms` and `/usr/share/fuse`.

| Model | Files |
|---|---|
| 48K | `48.rom` |
| 128K | `128-0.rom`, `128-1.rom` |
| +2 | `plus2-0.rom`, `plus2-1.rom` |
| +2A / +3 | `plus3-0.rom` .. `plus3-3.rom` |
| Pentagon 128 | `128-0.rom`, `128-1.rom` |
| TC2048 | `tc2048.rom` (in Fuse's ROMs; covered by Amstrad's permission) |
| Beta 128 / TR-DOS | `trdos.rom` (16 KB, TR-DOS 5.0x) |
| ZX81 | `zx81.rom` (8 KB, the "improved" version 2 ROM) |
| ZX80 | `zx80.rom` (4 KB) |
| Interface 1 | `if1-2.rom` (8 KB, edition 2; in the spectrum-roms package) |
| Pentagon 128 | 71680 T-states per frame (320 lines of 224), INT for 36 T-states, no contention and no floating bus, AY at 1.792 MHz; the 128K ROMs. |
| Timex TC2048 | The SCLD's video modes on port &FF: second screen at &6000, 8x1 colour attributes, the 512 x 192 modes (drawn at full resolution in the window and PNG) and their colours, and bit 6 switching off the frame interrupt; port &FF reads back; .z80 / .szx keep the mode. |
| ULAplus | `--ulaplus` or the Machine menu: the 64-colour palette (ports &BF3B / &FF3B, GGGRRRBB entries, four CLUTs chosen by FLASH / BRIGHT, the border from CLUT 0's paper entries). |
| Beta 128 / TR-DOS | Built into the Pentagon, `--beta` (or the Machine menu) on a 48K / 128K / +2: a WD1793 (all commands; Write Track ends at the index pulse, Read Address returns the IDs a FORMAT wrote), four drives, the TR-DOS ROM paged by a fetch from &3Dxx while the 48K BASIC ROM is selected. `.trd` images are written back; `.scl` archives become a disc in memory. Opening a .trd / .scl starts it (`RUN` of its "boot", else `CAT`). From BASIC: `RANDOMIZE USR 15619: REM : CAT` (after a `:` the editor is in keyword mode even in a REM, and typing follows that), or `RANDOMIZE USR 15616` for the TR-DOS prompt. `--trd FILE`, `--new-trd FILE`; File menu items for drives A and B. |
| DivMMC | `esxmmc.bin` (8 KB esxDOS firmware) and the folder `esxdos/` with esxDOS's `SYS`, `BIN` and `TMP` folders (from the esxDOS zip) |

**Spectrum:** Amstrad allow the Spectrum ROMs to be distributed with
emulators: *"Amstrad have kindly given their permission for the
redistribution of their copyrighted material but retain that copyright."*
They may not be sold. On Debian / Ubuntu `apt install spectrum-roms`
(multiverse / non-free) installs them in `/usr/share/spectrum-roms`, where
AdaZX finds them.

**ZX81:** the ZX81 ROM belongs to Nine Tiles, and there is no published
licence to redistribute it. Many emulators ship it (sz81, EightyOne).
Use a copy you are entitled to use, and do not pass it on with AdaZX.

**TR-DOS** (Technology Research) has no published licence either; use a
copy you are entitled to use (several emulators ship one) as
`roms/trdos.rom`.

**esxDOS** (Papaya Dezign) is free to download from www.esxdos.org but
states no licence, so it is not included either: put `ESXMMC.BIN` from the
zip in `roms/` as `esxmmc.bin`, and its `SYS`, `BIN` and `TMP` folders in
`roms/esxdos/`.  AdaZX then puts them on every SD card it builds.

## What is emulated

| Part | Notes |
|------|-------|
| Z80 | All documented and undocumented instructions and flags, MEMPTR and Q, IM 0/1/2, NMI, HALT. Every memory and I/O cycle happens at its own T-state, so contention is applied exactly: passes all 1356 tests of Fuse's per-cycle suite (bus events and timings identical), ZEXALL and all variants of Patrik Rak's z80test 1.2a (including the flags of interrupted LDIR / INIR, MEMPTR and CCF). |
| ULA (Spectrum) | 48K / 128K / +2A timings (69888 / 70908 T-states), memory and I/O contention, the picture drawn behind the CPU in 8-pixel steps (border and multicolour effects appear where they happen), FLASH, floating bus (48K and 128K phases checked with Richard Butler's timing tests and Ramsoft's Floating Spy; all 72 timing cases pass). |
| Memory | 128K paging (&7FFD), +2A / +3 paging and all-RAM modes (&1FFD). |
| +3 disc | uPD765A controller (read / write / deleted data, read track, read ID, format, seek, sense status; +3DOS polling, no terminal count) with two drives; .dsk images (standard and extended, sector status flags kept for copy protection) written back as extended DSK; blank formatted discs (File menu or `--new-disc`); a .dsk autostarts through the menu's Loader. |
| Sound | Beeper and MIC, AY-3-8912 (128K models: tones, noise, envelopes), the tape signal while loading; PulseAudio, which also paces the emulation. |
| Tape | TAP and TZX (standard, turbo, pure tone, pulse sequences, pure data, direct recording, generalized data, CSW recordings (RLE and Z-RLE), pauses, loops, jumps, stop-if-48K) played as the EAR signal in real time (turbo and custom loaders work) or flash-loaded through a ROM trap; SAVE is recorded and can be written as a .tap. |
| Snapshots | .z80 (v1-v3), .szx (ZX-State v1.4, zlib-compressed pages) and .sna load and save; .azx (AdaZX) holds the complete state of every model, ZX81 included. RZX input recordings: playback (embedded .szx / .z80 / .sna snapshots, several parts) and recording (Machine menu or `--record-rzx FILE`). |
| Interface 1 | Shadow ROM paged at &0008 / &1708 and out after &0700, eight Microdrives with .mdr cartridges (read-driven tape loop with GAP / SYNC as in Fuse), FORMAT / SAVE * / LOAD * / CAT, cartridges written back; blank cartridges (File menu or `--new-mdr`); a .mdr autostarts by loading "run". RS232 and network are not connected. |
| ZX80 | The ZX81 display hardware without the NMI generator (a picture only while the ROM waits for a key, as on the real machine), 4K ROM, 1K or 16K RAM; .o files load through the ROM's LOAD and SAVE writes .o; ZX80 BASIC (integer, operators as tokens) in the tokenizer, lister, typing and Forge; machine code in a REM line at 16427 called with PRINT USR (the ZX80's USR returns HL). |
| ZX81 / ZX80 sound | AY sound boards: the ZON X-81 (`--zonx`; ports &DF / &CF select, &0F writes; 1.625 MHz) and the Quicksilva board (`--quicksilva`; &7FFF select, &7FFE write; 0.8125 MHz), also in the Machine menu. |
| DivMMC | esxDOS's interface: 8K ROM, 512K RAM, automapping (&0000, &0008, &0038, &0066, &04C6, &0562, &3Dxx; off at &1FF8), port &E3 (CONMEM, MAPRAM, bank), an SDHC card on SPI (ports &E7 / &EB) on an image file, written in place. `--sd FILE` inserts an image, `--sd-dir DIR` builds a FAT16 card from a host folder (8.3 names; esxDOS's system folders added), `--new-sd FILE` makes a new card; File and Machine menus too. In BASIC: `.ls`, `.cd`, `.tapein game.tap` then `LOAD ""`, `SAVE *"name"`; the NMI (Alt+N) opens esxDOS's file browser. 48K, 128K, +2, +2A and +3. |
| Joysticks | Kempston, Sinclair 1 / 2, Cursor; keypad, cursor keys or a game controller. |
| ZX81 | Display generated as on the real machine: the CPU executes the display file above 32K, the ULA turns characters into NOPs and fetches their pattern (I register, line counter), HSYNC / NMI generator / VSYNC from the ports, INT from A6 during refresh; SLOW and FAST mode, WRX hi-res (pattern from RAM via the refresh address), pseudo hi-res with a VSYNC per scanline (short pulses don't start a frame; HSYNC kept free-running under DI), 1K or 16K, optional 8K RAM at &2000. .p files load through the ROM's LOAD (trap), SAVE writes a .p. |

## Keys

Symbolic mapping by default (Input menu: positional): type the character
you mean and the emulator presses SYMBOL SHIFT (ZX81: SHIFT) for it.
Shift = CAPS SHIFT, Ctrl = SYMBOL SHIFT, Tab = extended mode (ZX81:
FUNCTION), Backspace = DELETE, cursor keys, Esc = BREAK, Home = EDIT,
End = GRAPHICS, Caps Lock = CAPS LOCK.
Emulator: F11 warp, Alt+Enter fullscreen, Alt+A autostart, Alt+T insert
tape, Alt+P play / stop tape, Alt+R reset, Alt+N NMI, Alt+M monitor,
Alt+S / Alt+L quick snapshot, Ctrl+Shift+V paste text (BASIC keywords
are typed with their keys on the 48K and the ZX81).

## Forge

Assembler (pasmo / sjasmplus style, see the top of `src/asm.ads`): local
`.labels`, `macro` / `rept` / `if`, `include` / `incbin`, every
undocumented instruction. F5 builds and runs (Spectrum: code injected and
started with `RANDOMIZE USR`; ZX81: `org 16514`, the code goes into a REM
line), Shift+F5 builds a tape (.tap with a BASIC loader, or .p) and loads
it through the ROM. Sinclair BASIC tab (Ctrl+Shift+N; Spectrum or ZX81
dialect by the machine; escapes for UDGs, block graphics and control
codes as in zmakebas, see `src/basic.ads`): the running line is
highlighted, F9 sets breakpoints on BASIC lines, F10 / F11 step lines.
Debugger: F5 continue, F6 pause, F9 breakpoint, F10 / F11 / Shift+F11
step, Ctrl+F10 run to cursor, watchpoints, memory and disassembly panels.
Shift+F9 gives a breakpoint a condition (`a = 3 and [hl] <> 0`, `b > 10 ||
zf`, `{sp} = label`: registers, flags `sf zf hf pf nf cf`, `[addr]` byte,
`{addr}` word, labels, `= <> < > <= >= + - * / & | ^ << >> and or not`).
The profiler (Debug menu) counts T-states and executions per instruction
and shows the hottest addresses with their labels and source lines, and
the time per source line. In the monitor: `b ADDR CONDITION`, `prof on`,
`prof off`, `prof [n]`; headless: `--break-if ADDR CONDITION`,
`--profile`.

Tools:

* **UDG / character set editor** (Ctrl+K, `.udg`): the 21 UDGs or the
  whole font; export as DATA + POKE lines or db lines; show / live / grab
  with the emulator.
* **Spectrum screen editor** (Ctrl+B, `.scr`): pencil, line, rectangles,
  circle, fill, attribute brush, text in the ROM font (dragged into place, on
  character cells or anywhere with Shift), ink / paper / BRIGHT / FLASH, PNG import
  (best two colours per cell, ordered dithering), export as db lines or a
  .tap with `LOAD ""SCREEN$`; show / live / grab.
* **ZX81 screen editor** (Ctrl+R, `.z81s`): typing (inverse with Ctrl+I),
  painting characters, plotting 64 x 48 block graphics; export as PRINT
  lines (.b81) or display-file db lines; show / grab.


## Source layout

    src/z80.*          Z80 core (generic over the bus)   src/tstates.ads
    src/machine*.*     run loop, ports, ZX81 display, debugger, autostart,
                       snapshots (machine-snapshots)
    src/memory.*       paging, contention map         src/ula.*   picture
    src/sound.*, ay.*  beeper / AY mixing              src/tape.*  TAP/TZX
    src/fdc765.*, dsk.* +3 disc controller, .dsk images
    src/interface_1.*  Interface 1 and Microdrives
    src/p_files.*      ZX81 .p                         src/keyboard.* typist.*
    src/asm.*          assembler                       src/disasm.* monitor*.*
    src/basic.*        Sinclair BASIC                  src/tap_files.*
    src/forge.*        Forge window                    src/source_view.*
    src/udg_editor.*, screen_editor.*, zx81_editor.*, editor_util.*
    share/adazx/language-specs   Z80 and Sinclair BASIC highlighting
    tests/             Fuse's Z80 tests (GPL, from Fuse 1.6.0), ZEXDOC /
                       ZEXALL (GPL), assembler round trip, run_tests.sh
    tests/z80test/     Patrik Rak's z80test 1.2a tapes (MIT, see LICENSE there)
    tests/timing/      Richard Butler's 48K timing tests (GPL-3.0 redistribution)
    examples/          hello.asm (Spectrum), zx81hello.asm

## License

AdaZX is released under the MIT license (see `LICENSE`). The test data in
`tests/z80` comes from other projects under their own licenses: Fuse's
Z80 core tests (GPL v2, Fuse 1.6.0) and ZEXDOC / ZEXALL by Frank D.
Cringle (GPL v2). No ROMs, tapes or other Sinclair / Amstrad / Nine Tiles
software is included.
