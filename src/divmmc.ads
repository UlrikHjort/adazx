-- ***************************************************************************
--                              AdaZX - DivMMC
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

--  DivMMC: an 8K ROM (esxDOS), 512K of RAM in 8K banks and an SD card.
--
--  The interface maps itself over &0000 - &3FFF: &0000 - &1FFF is the ROM
--  (or RAM bank 3 with MAPRAM, read-only), &2000 - &3FFF the selected RAM
--  bank (not writable when MAPRAM maps bank 3 there).  It is mapped while
--  CONMEM (bit 7 of port &E3) is set, or by automapping: after an opcode
--  fetch from &0000, &0008, &0038, &0066, &04C6 or &0562, at once for a
--  fetch from &3D00 - &3DFF, and it unmaps after a fetch from &1FF8 -
--  &1FFF.  Port &E3: bit 7 CONMEM, bit 6 MAPRAM (stays set until power
--  off), bits 0 - 5 the RAM bank.  Port &E7: card select (bit 0 low =
--  card 0); port &EB: SPI data (a write sends a byte to the card, a read
--  takes the card's next byte).
--
--  The SD card is an SDHC card (block addressing) on an image file (a
--  disc image with a FAT file system, with or without a partition table);
--  sectors are read and written in the file directly.

with Types; use Types;

package DivMMC is

   Enabled : Boolean := False;     --  fitted (takes effect at reset)

   procedure Load_ROM (Path : String; Ok : out Boolean);
   function ROM_Loaded return Boolean;

   function Active return Boolean with Inline;   --  mapped in now
   function Read (Addr : Word) return Byte with Inline;   --  &0000 - &3FFF
   procedure Write (Addr : Word; V : Byte) with Inline;

   procedure Before_Fetch (Addr : Word) with Inline;
   procedure After_Fetch (Addr : Word) with Inline;

   procedure Reset;                --  a reset: unmapped, CONMEM off
   procedure Power_On;             --  also clears MAPRAM and the RAM

   function Port_Selected (Port : Word) return Boolean with Inline;
   function Port_In (Port : Word) return Byte;
   procedure Port_Out (Port : Word; Value : Byte);

   procedure Insert (Path : String; Ok : out Boolean);
   procedure Eject;
   function Card_Name return String;        --  "" when no card
   function Error_Message return String;
   function Card_Active return Boolean;     --  read or written lately

end DivMMC;
