-- ***************************************************************************
--                              AdaZX - Disasm
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

--  Z80 disassembler and hex helpers for the monitor and the forge.
--  Output style: "8000  21 00 40     LD HL,$4000".

with Types; use Types;

package Disasm is

   type Reader is access function (Addr : Word) return Byte;

   function Hex2 (B : Byte) return String;
   function Hex4 (W : Word) return String;

   procedure Disassemble (Read : Reader; Addr : Word;
                          Text : out String; Last : out Natural;
                          Length : out Natural);
   --  One instruction at Addr with address and bytes in Text (1 .. Last).

   function Instruction (Read : Reader; Addr : Word;
                         Length : out Natural) return String;
   --  Only the instruction text ("LD HL,$4000").

   function Is_Call (Read : Reader; Addr : Word) return Boolean;
   --  CALL / RST / DJNZ / LDIR-type instruction that "step over" should
   --  run to completion.

end Disasm;
