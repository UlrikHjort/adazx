-- ***************************************************************************
--                              AdaZX - Memory
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

--  Memory of the Spectrum models and the ZX81.
--
--  Spectrum: eight 16K RAM banks and up to four 16K ROMs.  The 48K uses
--  banks 5, 2 and 0 at &4000, &8000 and &C000 (as the 128K does after a
--  reset), so snapshots treat all models alike.  The 128K / +2 page with
--  port &7FFD, the +2A / +3 also with &1FFD (special all-RAM modes).
--
--  ZX81: the 8K ROM at &0000 (mirrored at &2000), 1K or 16K RAM at &4000,
--  and the whole lower 32K mirrored at &8000 (which is how the display
--  file is executed above 32K).

with Types; use Types;

package Memory is

   Bank_Size : constant := 16#4000#;
   type Store_Type is array (0 .. 12 * Bank_Size - 1) of Byte;
   --  RAM banks 0 .. 7, then ROMs 0 .. 3
   Store : Store_Type := (others => 0);

   function ROM_Base (N : Natural) return Natural is ((8 + N) * Bank_Size);
   function RAM_Base (N : Natural) return Natural is (N * Bank_Size);

   --  Current map: store offset and attributes of each 16K slot
   type Slot is range 0 .. 3;
   Slot_Base : array (Slot) of Natural := (0, 0, 0, 0);
   Slot_Writable : array (Slot) of Boolean := (False, True, True, True);
   Slot_Contended : array (Slot) of Boolean := (False, True, False, False);

   Port_7FFD : Byte := 0;
   Port_1FFD : Byte := 0;
   Paging_Locked : Boolean := False;

   ZX81_RAM_Size : Natural := 16#4000#;   --  1K (&400) or 16K
   ZX81_RAM_2000 : Boolean := False;
   --  8K RAM at &2000-&3FFF (the popular modification for hi-res games
   --  and the hi-res routines of some programs); the ROM stays at &0000.

   procedure Reset_Paging;
   --  The power-on map for Config.Model.

   procedure Clear_RAM;

   procedure Write_7FFD (V : Byte);
   procedure Write_1FFD (V : Byte);
   --  128K paging ports (ignored on the 48K and while locked).

   function Screen_Bank return Natural;   --  5 or 7 (128K bit 3)
   function Current_ROM return Natural;   --  0 .. 3
   function Basic48_ROM return Natural;
   --  The ROM that holds the 48K BASIC (where the tape routines are):
   --  0 on the 48K, 1 on the 128K / +2, 3 on the +2A / +3.
   function Special_Paging return Boolean;   --  +2A all-RAM mode

   --  TC2068: port &F4 (HSR) bit n maps 8K chunk n from the EXROM (when
   --  bit 7 of port &FF is set) or the dock (empty: reads &FF)
   TC_HSR : Byte := 0;
   TC_EXROM : Boolean := False;
   EXROM : Byte_Array (0 .. 16#1FFF#) := (others => 16#FF#);

   function Read (Addr : Word) return Byte with Inline;
   procedure Write (Addr : Word; V : Byte) with Inline;
   procedure Poke_Any (Addr : Word; V : Byte);
   --  Write even into ROM (debugger, loaders of ROM images).
   function Contended (Addr : Word) return Boolean with Inline;

   function Screen_Byte (Offset : Natural) return Byte with Inline;
   --  Byte Offset (0 .. 6911) of the displayed screen bank.

   function Bank_Of (Addr : Word) return Integer;
   --  RAM bank mapped at Addr, -1 for ROM.

end Memory;
