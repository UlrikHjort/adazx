-- ***************************************************************************
--                               AdaZX - Video
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

--  The framebuffer shared between the display hardware and the GUI.
--
--  One framebuffer pixel is one Spectrum pixel (half a T-state of the
--  3.5 MHz clock): the 256 x 192 picture with a 48 pixel border on the
--  left and right and 48 lines above and below, as much of the border as
--  a television showed.  The ZX81's picture is drawn in the same frame.

with Types; use Types;

package Video is

   Border  : constant := 48;
   Width   : constant := 256 + 2 * Border;     --  352
   Height  : constant := 192 + 2 * Border;     --  288

   type Frame is array (0 .. Height - 1, 0 .. Width - 1) of Pixel;
   type Frame_Access is access all Frame;
   FB : constant Frame_Access := new Frame'(others => (others => 0));

   --  Spectrum colours 0 .. 15 (8 .. 15 bright); bit 0 blue, 1 red,
   --  2 green
   type Palette is array (Natural range 0 .. 15) of Pixel;
   Colours : constant Palette :=
     (16#000000#, 16#0000D7#, 16#D70000#, 16#D700D7#,
      16#00D700#, 16#00D7D7#, 16#D7D700#, 16#D7D7D7#,
      16#000000#, 16#0000FF#, 16#FF0000#, 16#FF00FF#,
      16#00FF00#, 16#00FFFF#, 16#FFFF00#, 16#FFFFFF#);

   ZX81_Ink   : constant Pixel := 16#101010#;
   ZX81_Paper : constant Pixel := 16#E8E8E0#;

   --  The Timex 512 x 192 mode: the picture at twice the horizontal
   --  resolution (the window and PNG are drawn at twice the size anyway);
   --  used for the frame when Wide_Shown.
   type Wide_Frame is array (0 .. Height - 1, 0 .. 2 * Width - 1) of Pixel;
   FB_Wide : constant access Wide_Frame :=
     new Wide_Frame'(others => (others => 0));
   Wide_Drawn : Boolean := False;   --  this frame has 512-pixel chunks
   Wide_Shown : Boolean := False;   --  the last finished frame had them

   Scanlines : Boolean := False;
   --  Darken every other line (CRT look); applied by Blit.

end Video;
