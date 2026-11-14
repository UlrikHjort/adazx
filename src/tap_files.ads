-- ***************************************************************************
--                             AdaZX - Tap_Files
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

--  Building .tap images: headers, data blocks and BASIC loaders.

with Types; use Types;

package Tap_Files is

   function Block (Flag : Byte; Data : Byte_Array) return Byte_Array;
   --  A .tap block: length, flag, data, checksum.

   function Header (Kind : Byte; Name : String;
                    Length, Param1, Param2 : Natural) return Byte_Array;
   --  A header block (0 program, 3 bytes).

   function Program (Name : String; Basic_Text : String;
                     Autostart : Natural := 10) return Byte_Array;
   --  Header and data block of a BASIC program (tokenised from text).

   function Code (Name : String; Data : Byte_Array; Load : Natural)
                  return Byte_Array;

end Tap_Files;
