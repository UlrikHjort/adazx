-- ***************************************************************************
--                                AdaZX - Ula
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

--  The Spectrum ULA: frame timing, memory contention, the picture and
--  the floating bus.
--
--  The picture is drawn behind the CPU: Render_To (T) draws everything
--  the beam has passed up to T-state T, 8 pixels (4 T-states) at a time,
--  with the screen memory and border colour of that moment.  The machine
--  calls it before every write to the displayed screen memory and every
--  border change, so mid-frame and mid-line changes (border stripes,
--  multicolour effects) appear where they happened.

with Types; use Types;

package ULA is

   Line_T  : Natural := 224;     --  T-states per line
   Lines   : Natural := 312;
   Frame_T : Natural := 69_888;
   Int_Length : Natural := 32;   --  T-states the INT line is held low
   Display_Start : Natural := 14_336;   --  T-state of the first pixel

   procedure Configure;
   --  Timing and contention for Config.Model.

   function Delay_At (T : Integer) return Natural with Inline;
   --  Contention delay of a memory cycle in contended memory at T.

   Border_Colour : Natural range 0 .. 7 := 7;

   procedure Set_Border (C : Natural; T : Integer);
   procedure Render_To (T : Integer);
   procedure End_Frame;
   --  Draw the rest of the frame and start the next one.

   function Is_Screen_Address (Addr : Word) return Boolean with Inline;
   --  Addr is in the bitmap / attributes of the displayed bank (as mapped).

   function Floating_Bus (T : Integer) return Byte;
   --  What an unattached port reads at T: the byte the ULA is fetching.

   Frame_Counter : Natural := 0;    --  flash phase (inverts every 16)

   --  Timex SCLD (TC2048, port &FF): bits 0 - 2 screen mode (0 standard,
   --  1 second screen at &6000, 2 / 3 8x1 colour attributes at &6000,
   --  4 / 5 / 6 / 7 512-pixel modes), 3 - 5 the 512-pixel mode's colours,
   --  6 no frame interrupt
   SCLD : Byte := 0;
   procedure Set_SCLD (V : Byte; T : Integer);
   function Interrupts_Off return Boolean;     --  SCLD bit 6 (TC2048)

   --  ULAplus: 64 palette entries (GGGRRRBB), register 64 the mode
   Plus_Register : Byte := 0;
   Plus_Palette : Byte_Array (0 .. 63) := (others => 0);
   Plus_On : Boolean := False;          --  palette mode
   procedure ULAplus_Out (Port : Word; V : Byte; T : Integer);
   function ULAplus_In return Byte;
   procedure Reset_Extras;              --  SCLD and ULAplus at power on

end ULA;
