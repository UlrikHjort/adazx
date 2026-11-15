-- ***************************************************************************
--                               AdaZX - Blit
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
with System;
with Glib; use Glib;
with Cairo.Image_Surface; use Cairo.Image_Surface;
with Cairo.Surface;
with Cairo.Png;
with Interfaces; use Interfaces;
with Types; use Types;
with Video;

package body Blit is

   function Width return Natural is (2 * Video.Width);
   function Height return Natural is (2 * Video.Height);

   function Dim (P : Pixel) return Pixel is
     (Interfaces.Shift_Right (P and 16#FEFEFE#, 1)
      + Interfaces.Shift_Right (P and 16#FCFCFC#, 2));

   procedure Copy (Surface : Cairo.Cairo_Surface) is
      H : constant Natural := Height;
      Stride : constant Natural := Natural (Get_Stride (Surface)) / 4;
      Addr : constant System.Address := Get_Data_Generic (Surface);
      type Pixels is array (0 .. H - 1, 0 .. Stride - 1) of Pixel;
      Dst : Pixels;
      for Dst'Address use Addr;
      pragma Import (Ada, Dst);
   begin
      Cairo.Surface.Flush (Surface);
      for Y in 0 .. Video.Height - 1 loop
         for X in 0 .. Video.Width - 1 loop
            declare
               P : constant Pixel :=
                 (if Video.Wide_Shown then Video.FB_Wide (Y, 2 * X)
                  else Video.FB (Y, X));
               Q : constant Pixel :=
                 (if Video.Wide_Shown then Video.FB_Wide (Y, 2 * X + 1)
                  else P);
            begin
               Dst (2 * Y, 2 * X) := P;
               Dst (2 * Y, 2 * X + 1) := Q;
               Dst (2 * Y + 1, 2 * X) :=
                 (if Video.Scanlines then Dim (P) else P);
               Dst (2 * Y + 1, 2 * X + 1) :=
                 (if Video.Scanlines then Dim (Q) else Q);
            end;
         end loop;
      end loop;
      Cairo.Surface.Mark_Dirty (Surface);
   end Copy;

   procedure Save_PNG (Path : String) is
      Surf : constant Cairo.Cairo_Surface :=
        Create (Cairo_Format_RGB24, Gint (Width), Gint (Height));
      Status : Cairo.Cairo_Status;
   begin
      Copy (Surf);
      Status := Cairo.Png.Write_To_Png (Surf, Path);
      pragma Unreferenced (Status);
      Cairo.Surface.Destroy (Surf);
   end Save_PNG;

end Blit;
