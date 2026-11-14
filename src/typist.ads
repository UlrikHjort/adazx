-- ***************************************************************************
--                              AdaZX - Typist
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

--  Typing BASIC into the machine the way its editor expects it.
--
--  The 48K Spectrum and the ZX81 take keywords as single keys: in K mode
--  (start of a statement) a letter key gives the statement keyword, other
--  keywords need SYMBOL SHIFT or E mode (FUNCTION on the ZX81).  Text is
--  tokenised first and each token is typed with its key, tracking the
--  cursor mode as the ROM does.  The 128K editor takes keywords spelt out.

with Types; use Types;

package Typist is

   procedure Type_Text (S : String);
   procedure Type_Load;
   --  LOAD "" and ENTER (also on the ZX81).

   procedure Install_Program (Data : Byte_Array; Run_Line : Integer := -1);
   --  A tokenised program (Basic memory form) as if it had been loaded:
   --  poked in at PROG with the system variables updated (Spectrum), or
   --  loaded from a .p image through LOAD "" (ZX81).

end Typist;
