-- ***************************************************************************
--                                AdaZX - Ula
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

with Interfaces; use Interfaces;
with Config; use Config;
with Memory;
with Video;

package body ULA is

   Max_Frame : constant := 71_000;
   Delays : array (0 .. Max_Frame) of Byte := (others => 0);

   --  The visible picture starts 48 lines above and 24 T-states (48
   --  pixels) left of the first display pixel.
   Origin : Integer := 0;
   Render_Pos : Integer := 0;    --  relative to Origin, multiple of 4
   Visible_T : constant := Video.Width / 2;    --  176 T-states per line

   procedure Configure is
      First : Natural;
      Pattern : array (0 .. 7) of Byte;
   begin
      case Model is
         when ZX48 | ZX81 | ZX80 =>
            Line_T := 224; Lines := 312; Int_Length := 32;
            Display_Start := 14_336;
            First := 14_335;
            Pattern := (6, 5, 4, 3, 2, 1, 0, 0);
         when ZX128 | Plus2 =>
            Line_T := 228; Lines := 311; Int_Length := 36;
            Display_Start := 14_364;
            First := 14_361;
            Pattern := (6, 5, 4, 3, 2, 1, 0, 0);
         when Plus2A | Plus3 =>
            Line_T := 228; Lines := 311; Int_Length := 32;
            Display_Start := 14_364;
            First := 14_365;
            Pattern := (1, 0, 7, 6, 5, 4, 3, 2);
      end case;
      Frame_T := Line_T * Lines;
      Delays := (others => 0);
      for Line in 0 .. 191 loop
         for H in 0 .. 127 loop
            Delays (First + Line * Line_T + H) := Pattern (H mod 8);
         end loop;
      end loop;
      Origin := Display_Start - Video.Border / 2 - Video.Border * Line_T;
      Render_Pos := 0;
   end Configure;

   function Delay_At (T : Integer) return Natural is
     (if T in Delays'Range then Natural (Delays (T)) else 0);

   function Is_Screen_Address (Addr : Word) return Boolean is
     (Addr in 16#4000# .. 16#5AFF#
      or else (Model /= ZX48
               and then Addr >= 16#C000# and then Addr < 16#DB00#
               and then Memory.Bank_Of (Addr) = Memory.Screen_Bank));

   procedure Draw_Chunk (Pos : Integer) is
      Y : constant Integer := Pos / Line_T;
      H : constant Integer := Pos mod Line_T;
      X : constant Natural := 2 * H;
      DY : constant Integer := Y - Video.Border;
      DX : constant Integer := X - Video.Border;
   begin
      if DY in 0 .. 191 and then DX in 0 .. 255 then
         declare
            Col : constant Natural := DX / 8;
            Bitmap_Ofs : constant Natural :=
              (DY / 64) * 2048 + (DY mod 8) * 256 + ((DY / 8) mod 8) * 32
              + Col;
            Bits : Byte := Memory.Screen_Byte (Bitmap_Ofs);
            Attr : constant Byte :=
              Memory.Screen_Byte (6144 + (DY / 8) * 32 + Col);
            Bright : constant Natural :=
              (if (Attr and 16#40#) /= 0 then 8 else 0);
            Ink : constant Pixel :=
              Video.Colours (Natural (Attr and 7) + Bright);
            Paper : constant Pixel :=
              Video.Colours (Natural (Shift_Right (Attr, 3) and 7) + Bright);
         begin
            if (Attr and 16#80#) /= 0 and then (Frame_Counter / 16) mod 2 = 1
            then
               Bits := not Bits;
            end if;
            for K in 0 .. 7 loop
               Video.FB (Y, X + K) :=
                 (if (Bits and Shift_Right (Byte'(16#80#), K)) /= 0
                  then Ink else Paper);
            end loop;
         end;
      else
         declare
            P : constant Pixel := Video.Colours (Border_Colour);
         begin
            for K in 0 .. 7 loop
               Video.FB (Y, X + K) := P;
            end loop;
         end;
      end if;
   end Draw_Chunk;

   procedure Render_To (T : Integer) is
      Target : constant Integer :=
        Integer'Min (T - Origin, Video.Height * Line_T);
   begin
      while Render_Pos < Target loop
         if Render_Pos mod Line_T >= Visible_T then
            Render_Pos := (Render_Pos / Line_T + 1) * Line_T;
         else
            Draw_Chunk (Render_Pos);
            Render_Pos := Render_Pos + 4;
         end if;
      end loop;
   end Render_To;

   procedure Set_Border (C : Natural; T : Integer) is
   begin
      if C /= Border_Colour then
         Render_To (T);
         Border_Colour := C;
      end if;
   end Set_Border;

   procedure End_Frame is
   begin
      Render_To (Integer'Last / 2);
      Render_Pos := 0;
      Frame_Counter := Frame_Counter + 1;
   end End_Frame;

   function Floating_Bus (T : Integer) return Byte is
   begin
      if Model in Plus2A .. Plus3 then
         return 16#FF#;
      end if;
      declare
         Rel : constant Integer := T - (Display_Start - 1);
         Y : constant Integer := Rel / Line_T;
         H : constant Integer := Rel mod Line_T;
      begin
         if Rel < 0 or else Y > 191 or else H > 127 or else H mod 8 > 3 then
            return 16#FF#;
         end if;
         declare
            Col : constant Natural := (H / 8) * 2 + (H mod 8) / 2;
         begin
            if H mod 2 = 0 then
               return Memory.Screen_Byte
                 ((Y / 64) * 2048 + (Y mod 8) * 256 + ((Y / 8) mod 8) * 32
                  + Col);
            else
               return Memory.Screen_Byte (6144 + (Y / 8) * 32 + Col);
            end if;
         end;
      end;
   end Floating_Bus;

end ULA;
