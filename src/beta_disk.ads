-- ***************************************************************************
--                             AdaZX - Beta_Disk
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************

--  The Beta 128 disk interface (TR-DOS): a WD1793 controller, four drives
--  and the TR-DOS ROM.
--
--  The ROM is paged over &0000 - &3FFF by an opcode fetch from &3D00 -
--  &3DFF while the 48K BASIC ROM is selected, and paged out by any fetch
--  from &4000 up.  While it is paged the controller answers on ports &1F
--  (command / status), &3F (track), &5F (sector), &7F (data) and &FF (system:
--  written bits 0 - 1 drive, 2 reset (low), 4 side (low = side 1); read
--  bit 6 DRQ, bit 7 INTRQ).
--
--  Discs: .trd images (tracks of 16 sectors of 256 bytes, side 0 and 1 in
--  turn; written back to the file) and .scl archives (made into a TR-DOS
--  disc in memory; changes are not written back).

with Types; use Types;

package Beta_Disk is

   Enabled : Boolean := False;     --  fitted (the Pentagon has it built in)
   Active : Boolean := False;      --  the TR-DOS ROM is paged in

   procedure Load_ROM (Path : String; Ok : out Boolean);
   function ROM_Loaded return Boolean;
   function ROM_Byte (Addr : Word) return Byte with Inline;

   procedure Before_Fetch (Addr : Word; Basic48 : Boolean) with Inline;
   --  Basic48: the 48K BASIC ROM is the one selected

   procedure Reset;

   function Port_Selected (Port : Word) return Boolean with Inline;
   function Port_In (Port : Word; Cycle : Long_Long_Integer) return Byte;
   procedure Port_Out (Port : Word; Value : Byte; Cycle : Long_Long_Integer);
   --  Cycle: T-states since power on (for the index pulse)

   subtype Drive_Number is Natural range 0 .. 3;     --  A: .. D:
   procedure Insert (Drive : Drive_Number; Path : String; Ok : out Boolean);
   procedure Eject (Drive : Drive_Number);
   function Name (Drive : Drive_Number) return String;
   procedure Create (Path : String; Ok : out Boolean);
   --  A blank formatted disc (80 tracks, 2 sides)
   function Has_Boot (Drive : Drive_Number) return Boolean;
   --  The disc has a BASIC program called "boot" (what RUN starts)
   procedure Flush_All;
   function Error_Message return String;
   function Activity return Boolean;    --  used lately (cleared by reading)

end Beta_Disk;
