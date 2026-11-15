-- ***************************************************************************
--                            AdaZX - Peripherals
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

--  Smaller Spectrum peripherals: the Kempston mouse, the ZX Printer and
--  the Multiface 128.

with Types; use Types;

package Peripherals is

   ---------------------------------------------------------------------
   --  Kempston mouse: buttons when (port and &0121) = &0001 (bit 0 right,
   --  1 left, 2 middle; low = pressed), X when (port and &0521) = &0101
   --  (grows to the right), Y when (port and &0521) = &0501 (grows up)
   ---------------------------------------------------------------------

   Mouse_On : Boolean := False;
   Mouse_X, Mouse_Y : Byte := 0;
   Mouse_Buttons : Byte := 16#FF#;
   function Mouse_Port (Port : Word) return Boolean with Inline;
   function Mouse_In (Port : Word) return Byte;

   ---------------------------------------------------------------------
   --  ZX Printer on port &FB (decoded fully, not by A2 alone): written bit 7 stylus, bit 2 motor
   --  off, bit 1 slow; read bit 0 encoder, bit 7 the start of a line,
   --  bit 6 low = there is a printer.  Printing follows the ROM's
   --  handshake and takes no time.
   ---------------------------------------------------------------------

   Printer_On : Boolean := False;
   function Printer_Port (Port : Word) return Boolean with Inline;
   function Printer_In (Cycle : Long_Long_Integer) return Byte;
   procedure Printer_Out (V : Byte; Cycle : Long_Long_Integer);
   function Printed_Lines return Natural;
   function Printed_Pixel (X, Y : Natural) return Boolean;
   procedure Clear_Printout;
   procedure Save_Printout (Path : String; Ok : out Boolean);
   --  A PNG of the paper (256 pixels wide)

   ---------------------------------------------------------------------
   --  Multiface 128: the red button (an NMI) pages its 8K ROM (&0000) and
   --  8K RAM (&2000) in at the fetch from &0066; IN from a port with
   --  (port and &72) = &32 pages it in (A7 high, when allowed) or out
   ---------------------------------------------------------------------

   MF_Enabled : Boolean := False;
   MF_Active : Boolean := False;          --  paged in
   procedure MF_Load_ROM (Path : String; Ok : out Boolean);
   function MF_ROM_Loaded return Boolean;
   function MF_Read (Addr : Word) return Byte with Inline;
   procedure MF_Write (Addr : Word; V : Byte) with Inline;
   function MF_Red_Button return Boolean;  --  True: raise an NMI
   procedure MF_Before_Fetch (Addr : Word) with Inline;
   function MF_Port (Port : Word) return Boolean with Inline;
   function MF_In (Port : Word; Last_7FFD : Byte) return Byte;
   procedure MF_Out (Port : Word);
   procedure MF_Reset (Hard : Boolean);

end Peripherals;
