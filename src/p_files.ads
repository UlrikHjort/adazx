-- ***************************************************************************
--                              AdaZX - P_Files
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

--  ZX81 programs on "tape": a .p file (the memory from &4009 up to
--  E_LINE) is loaded by the ROM's LOAD command through a trap, and what
--  SAVE writes is kept as a .p recording.

with Types; use Types;

package P_Files is

   procedure Insert (Path : String; Ok : out Boolean);
   procedure Set_Image (Data : Byte_Array);   --  a .p image from memory
   procedure Eject;
   function Loaded return Boolean;
   function Name return String;

   procedure Load_Into_Memory;
   --  Copy the image to &4009 (the tape is consumed: the next LOAD needs
   --  a new file, as with a real tape that has run past the program).
   function Last_Address return Word;    --  last byte loaded

   procedure Record_Memory;
   --  SAVE: keep &4009 .. E_LINE - 1.
   function Recorded return Natural;
   procedure Save_Recording (Path : String; Ok : out Boolean);

end P_Files;
