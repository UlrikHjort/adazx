-- ***************************************************************************
--                            AdaZX - Zx81_Editor
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

--  The forge's ZX81 screen editor.
--
--  The 32 x 24 character screen of the ZX81: text typed at the cursor
--  (Ctrl+I toggles inverse video), characters painted from the palette,
--  and a plot mode for the 64 x 48 block graphics (left button sets a
--  quadrant, right button clears it).  Files: .z81s (768 character codes,
--  row by row).  Exports BASIC PRINT lines (.b81) or assembler db lines
--  laid out like the display file; "Show" / "Grab" use the running ZX81's
--  display file (it must be the expanded 16K one).

with Gtk.Window;

package ZX81_Editor is

   procedure Open (Parent : Gtk.Window.Gtk_Window; Path : String := "");
   function Is_ZX81_Screen_File (Path : String) return Boolean;

end ZX81_Editor;
