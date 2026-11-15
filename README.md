# AdaZX

A ZX Spectrum (48K, 128K, +2, +2A, +3 with its disc drive) and Sinclair ZX81
emulator written in Ada 2012 with GtkAda, with **Forge**: a Z80 assembler
IDE, Sinclair BASIC editor, source-level debugger and graphics editors
around the running machine. It is the Sinclair sibling of AdaC64
(`../c64`) and AdaBeeb (`../bbc`).

## Build and run

    make                     # GNAT, gprbuild, GtkAda, libpulse-dev,
                             # libgtksourceview-4 (Forge's editor)
    bin/adazx                # 48K Spectrum (or the model used last time)
    bin/adazx --128          # also --plus2, --plus2a, --plus3, --zx81
    bin/adazx game.tzx       # autostart (also .tap .z80 .szx .sna .azx .rzx .p .81
                             # .scr .bas .b81 .asm)
    bin/adazx-forge          # Forge as the main window
    make tests               # Z80 core, assembler, machine tests
    make zexall              # ZEXALL instruction exerciser (~1 minute)

Tapes are started the way a user would: `LOAD ""` on the 48K and the
ZX81, the "Tape Loader" menu entry on the 128K models. `.bas` / `.b81`
files are tokenised and RUN; `.asm` files are assembled and started with
`RANDOMIZE USR` (Spectrum) or put into a REM line at 16514 (ZX81).

Options: `--roms DIR`, `--disc FILE` (+3 drive A), `--if1`, `--mdr FILE` (Interface 1, cartridge in Microdrive 1), `--1k` (ZX81 without the 16K pack), `--ram2000`
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
| ZX81 | `zx81.rom` (8 KB, the "improved" version 2 ROM) |
| Interface 1 | `if1-2.rom` (8 KB, edition 2; in the spectrum-roms package) |

**Spectrum:** Amstrad allow the Spectrum ROMs to be distributed with
emulators: *"Amstrad have kindly given their permission for the
redistribution of their copyrighted material but retain that copyright."*
They may not be sold. On Debian / Ubuntu `apt install spectrum-roms`
(multiverse / non-free) installs them in `/usr/share/spectrum-roms`, where
AdaZX finds them.

**ZX81:** the ZX81 ROM belongs to Nine Tiles, and there is no published
licence to redistribute it. Many emulators ship it (sz81, EightyOne).
Use a copy you are entitled to use, and do not pass it on with AdaZX.

## What is emulated

| Part | Notes |
|------|-------|
| Z80 | All documented and undocumented instructions and flags, MEMPTR and Q, IM 0/1/2, NMI, HALT. Every memory and I/O cycle happens at its own T-state, so contention is applied exactly: passes all 1356 tests of Fuse's per-cycle suite (bus events and timings identical) and ZEXALL. |
| ULA (Spectrum) | 48K / 128K / +2A timings (69888 / 70908 T-states), memory and I/O contention, the picture drawn behind the CPU in 8-pixel steps (border and multicolour effects appear where they happen), FLASH, floating bus. |
| Memory | 128K paging (&7FFD), +2A / +3 paging and all-RAM modes (&1FFD). |
| +3 disc | uPD765A controller (read / write / deleted data, read track, read ID, format, seek, sense status; +3DOS polling, no terminal count) with two drives; .dsk images (standard and extended, sector status flags kept for copy protection) written back as extended DSK; blank formatted discs (File menu or `--new-disc`); a .dsk autostarts through the menu's Loader. |
| Sound | Beeper and MIC, AY-3-8912 (128K models: tones, noise, envelopes), the tape signal while loading; PulseAudio, which also paces the emulation. |
| Tape | TAP and TZX (standard, turbo, pure tone, pulse sequences, pure data, direct recording, generalized data, CSW recordings (RLE and Z-RLE), pauses, loops, jumps, stop-if-48K) played as the EAR signal in real time (turbo and custom loaders work) or flash-loaded through a ROM trap; SAVE is recorded and can be written as a .tap. |
| Snapshots | .z80 (v1-v3), .szx (ZX-State v1.4, zlib-compressed pages) and .sna load and save; .azx (AdaZX) holds the complete state of every model, ZX81 included. RZX input recordings: playback (embedded .szx / .z80 / .sna snapshots, several parts) and recording (Machine menu or `--record-rzx FILE`). |
| Interface 1 | Shadow ROM paged at &0008 / &1708 and out after &0700, eight Microdrives with .mdr cartridges (read-driven tape loop with GAP / SYNC as in Fuse), FORMAT / SAVE * / LOAD * / CAT, cartridges written back; blank cartridges (File menu or `--new-mdr`); a .mdr autostarts by loading "run". RS232 and network are not connected. |
| Joysticks | Kempston, Sinclair 1 / 2, Cursor; keypad, cursor keys or a game controller. |
| ZX81 | Display generated as on the real machine: the CPU executes the display file above 32K, the ULA turns characters into NOPs and fetches their pattern (I register, line counter), HSYNC / NMI generator / VSYNC from the ports, INT from A6 during refresh; SLOW and FAST mode, WRX hi-res (pattern from RAM via the refresh address), 1K or 16K, optional 8K RAM at &2000. .p files load through the ROM's LOAD (trap), SAVE writes a .p. |

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

Tools:

* **UDG / character set editor** (Ctrl+K, `.udg`): the 21 UDGs or the
  whole font; export as DATA + POKE lines or db lines; show / live / grab
  with the emulator.
* **Spectrum screen editor** (Ctrl+B, `.scr`): pencil, line, rectangles,
  circle, fill, attribute brush, ink / paper / BRIGHT / FLASH, PNG import
  (best two colours per cell, ordered dithering), export as db lines or a
  .tap with `LOAD ""SCREEN$`; show / live / grab.
* **ZX81 screen editor** (Ctrl+R, `.z81s`): typing (inverse with Ctrl+I),
  painting characters, plotting 64 x 48 block graphics; export as PRINT
  lines (.b81) or display-file db lines; show / grab.

## Not (yet) emulated

the ZX80, ZX81 sound boards. The ZX81
pseudo hi-res of some programs (sz81's tetris title) shows thin
two-scanline offsets that have not been checked against a reference.

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
    examples/          hello.asm (Spectrum), zx81hello.asm

## License

AdaZX is released under the MIT license (see `LICENSE`). The test data in
`tests/z80` comes from other projects under their own licenses: Fuse's
Z80 core tests (GPL v2, Fuse 1.6.0) and ZEXDOC / ZEXALL by Frank D.
Cringle (GPL v2). No ROMs, tapes or other Sinclair / Amstrad / Nine Tiles
software is included.
