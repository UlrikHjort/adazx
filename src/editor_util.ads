-- ***************************************************************************
--                           AdaZX - Editor_Util
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
--  Helpers shared by the forge's graphics editors.

with Gtk.Window;
with Cairo;
with Types; use Types;

package Editor_Util is

   function Choose_File (Parent : Gtk.Window.Gtk_Window; Title : String;
                         Save : Boolean; Kind, Pattern : String;
                         Default_Name : String := "") return String;
   --  A file dialog filtering on Pattern ("*.m7"); "" when cancelled.

   procedure Message (Parent : Gtk.Window.Gtk_Window; Text : String);

   procedure Set_RGB (Cr : Cairo.Cairo_Context; P : Pixel);
   procedure Set_Colour (Cr : Cairo.Cairo_Context; Physical : Byte);
   --  Spectrum colour 0 .. 15 (8 .. 15 bright)

   function Hex2 (N : Natural) return String;
   function Hex4 (N : Natural) return String;

   function Read_Bytes (Path : String; Ok : out Boolean) return Byte_Array;
   procedure Write_Bytes (Path : String; Data : Byte_Array; Ok : out Boolean);
   procedure Write_Text (Path, Text : String; Ok : out Boolean);

   function Physical_Name (C : Byte) return String;
   --  "black", "red" ... "white"

end Editor_Util;
