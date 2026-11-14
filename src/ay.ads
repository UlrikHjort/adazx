-- ***************************************************************************
--                                AdaZX - Ay
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

--  General Instrument AY-3-8912 sound chip (128K, +2, +2A, +3): three
--  square-wave tone channels, a noise generator and the envelope
--  generator, clocked at 1.7734 MHz.  Port &FFFD selects a register (and
--  reads it), &BFFD writes it.

with Types; use Types;

package AY is

   Clock_Hz : constant := 1_773_400;

   Regs : array (0 .. 15) of Byte := (others => 0);
   Selected : Natural range 0 .. 15 := 0;

   procedure Reset;
   procedure Select_Register (V : Byte);
   procedure Write (V : Byte);
   function Read return Byte;

   function Next_Sample (Rate : Positive) return Float;
   --  Run the chip for one output sample at Rate Hz and return its mean
   --  output level (0.0 .. 1.0, the three channels mixed).

end AY;
