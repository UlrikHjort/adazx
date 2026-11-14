-- ***************************************************************************
--                              AdaZX - Types
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
--  Basic types shared by all emulator components.
with Interfaces;

package Types is
   pragma Preelaborate;

   subtype Byte is Interfaces.Unsigned_8;
   subtype Word is Interfaces.Unsigned_16;
   subtype U32  is Interfaces.Unsigned_32;

   use type Interfaces.Unsigned_16;

   type Byte_Array is array (Natural range <>) of Byte;
   type Byte_Array_Access is access all Byte_Array;

   function Lo (W : Word) return Byte is (Byte (W and 16#FF#));
   function Hi (W : Word) return Byte is (Byte (Interfaces.Shift_Right (W, 8)));
   function Make_Word (L, H : Byte) return Word is
     (Word (L) or Interfaces.Shift_Left (Word (H), 8));

   --  Pixel framebuffers hold 0x00RRGGBB values (Cairo RGB24 layout).
   subtype Pixel is U32;
end Types;
