-- ***************************************************************************
--                           AdaZX - Screen_Editor
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

--  The forge's ZX Spectrum screen editor (SCREEN$).
--
--  256 x 192 pixels with an 8 x 8 attribute grid (ink, paper, BRIGHT,
--  FLASH per cell).  Tools: pencil, line, rectangle, filled rectangle,
--  circle, flood fill and an attribute brush; left button draws in ink,
--  right button in paper.  Files: .scr (the 6912 bytes of screen memory),
--  PNG import (two best colours per cell, optional dithering), exports
--  as assembler db lines or a .tap with LOAD ""SCREEN$.  "Show" / "Live"
--  write into the emulator's screen, "Grab" reads it.

with Gtk.Window;

package Screen_Editor is

   procedure Open (Parent : Gtk.Window.Gtk_Window; Path : String := "");
   function Is_Screen_File (Path : String) return Boolean;
   --  .scr, or an image to import (.png)

end Screen_Editor;
