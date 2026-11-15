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

   Max_Frame : constant := 72_000;
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
         when TC2048 =>
            Line_T := 224; Lines := 312; Int_Length := 32;
            Display_Start := 14_321;
            First := 14_320;
            Pattern := (6, 5, 4, 3, 2, 1, 0, 0);
         when Pentagon =>                      --  no contention
            Line_T := 224; Lines := 320; Int_Length := 36;
            Display_Start := 17_988;
            First := 17_987;
            Pattern := (others => 0);
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
      or else (Model = TC2048 and then Addr in 16#6000# .. 16#7AFF#)
      or else (Model not in ZX48 | TC2048
               and then Addr >= 16#C000# and then Addr < 16#DB00#
               and then Memory.Bank_Of (Addr) = Memory.Screen_Bank));

   function Interrupts_Off return Boolean is
     (Model = TC2048 and then (SCLD and 16#40#) /= 0);

   --  ULAplus palette entry as a pixel (G3 R3 B2; blue's low bit is the
   --  OR of its two bits)
   function Plus_Colour (Index : Natural) return Pixel is
      V : constant Byte := Plus_Palette (Index);
      G : constant Natural := Natural (Shift_Right (V, 5) and 7);
      R : constant Natural := Natural (Shift_Right (V, 2) and 7);
      B2 : constant Natural := Natural (V and 3);
      B : constant Natural := B2 * 2 + (if B2 /= 0 then 1 else 0);
      function C8 (X : Natural) return Natural is (X * 36 + X / 2);
   begin
      return Pixel (C8 (R) * 65536 + C8 (G) * 256 + C8 (B));
   end Plus_Colour;

   procedure Put8 (Y, X : Natural; Bits : Byte; Ink, Paper : Pixel) is
   begin
      for K in 0 .. 7 loop
         declare
            P : constant Pixel :=
              (if (Bits and Shift_Right (Byte'(16#80#), K)) /= 0
               then Ink else Paper);
         begin
            Video.FB (Y, X + K) := P;
            if Model = TC2048 then
               Video.FB_Wide (Y, 2 * (X + K)) := P;
               Video.FB_Wide (Y, 2 * (X + K) + 1) := P;
            end if;
         end;
      end loop;
   end Put8;

   --  The Timex 512-pixel modes: 16 pixels from two bytes
   procedure Put16 (Y, X : Natural; Left, Right : Byte; Ink, Paper : Pixel)
   is
      W : constant Unsigned_16 :=
        Shift_Left (Unsigned_16 (Left), 8) or Unsigned_16 (Right);
   begin
      for K in 0 .. 15 loop
         Video.FB_Wide (Y, 2 * X + K) :=
           (if (W and Shift_Right (Unsigned_16'(16#8000#), K)) /= 0
            then Ink else Paper);
      end loop;
      for K in 0 .. 7 loop             --  the normal picture: pairs
         Video.FB (Y, X + K) :=
           (if (W and Shift_Right (Unsigned_16'(16#C000#), 2 * K)) /= 0
            then Ink else Paper);
      end loop;
      Video.Wide_Drawn := True;
   end Put16;

   procedure Draw_Chunk (Pos : Integer) is
      Y : constant Integer := Pos / Line_T;
      H : constant Integer := Pos mod Line_T;
      X : constant Natural := 2 * H;
      DY : constant Integer := Y - Video.Border;
      DX : constant Integer := X - Video.Border;
      Timex : constant Boolean := Model = TC2048;
      Mode : constant Byte := (if Timex then SCLD and 7 else 0);
      Hires : constant Boolean := Timex and then (Mode and 4) /= 0;
      Hires_Attr : constant Byte :=     --  ink = bits 3 - 5, paper = 7 - ink
        16#40# or Shift_Right (SCLD and 16#38#, 3)
        or Shift_Left (7 - Shift_Right (SCLD and 16#38#, 3), 3);
   begin
      if DY in 0 .. 191 and then DX in 0 .. 255 then
         declare
            Col : constant Natural := DX / 8;
            Bitmap_Ofs : constant Natural :=
              (DY / 64) * 2048 + (DY mod 8) * 256 + ((DY / 8) mod 8) * 32
              + Col;
            Attr_Ofs : constant Natural := 6144 + (DY / 8) * 32 + Col;
            Alt : constant Natural :=
              (if (Mode and 1) /= 0 then 16#2000# else 0);
            Bits : Byte := Memory.Screen_Byte (Bitmap_Ofs + Alt);
            Attr : constant Byte :=
              (if Hires then Hires_Attr
               elsif Timex and then (Mode and 2) /= 0
               then Memory.Screen_Byte (Bitmap_Ofs + 16#2000#)
               else Memory.Screen_Byte (Attr_Ofs + Alt));
            Bright : constant Natural :=
              (if (Attr and 16#40#) /= 0 then 8 else 0);
            Ink, Paper : Pixel;
         begin
            if Plus_On then
               declare
                  CLUT : constant Natural :=
                    Natural (Shift_Right (Attr, 6)) * 16;
               begin
                  Ink := Plus_Colour (CLUT + Natural (Attr and 7));
                  Paper := Plus_Colour
                    (CLUT + 8 + Natural (Shift_Right (Attr, 3) and 7));
               end;
            else
               Ink := Video.Colours (Natural (Attr and 7) + Bright);
               Paper := Video.Colours
                 (Natural (Shift_Right (Attr, 3) and 7) + Bright);
               if (Attr and 16#80#) /= 0
                 and then (Frame_Counter / 16) mod 2 = 1
               then
                  Bits := not Bits;
               end if;
            end if;
            if Hires then
               declare
                  Right : constant Byte :=
                    (case Mode is
                        when 6 => Memory.Screen_Byte (Bitmap_Ofs + 16#2000#),
                        when 7 => Bits,
                        when 5 => Memory.Screen_Byte (Attr_Ofs + 16#2000#),
                        when others => Memory.Screen_Byte (Attr_Ofs));
               begin
                  Put16 (Y, X, Bits, Right, Ink, Paper);
               end;
            else
               Put8 (Y, X, Bits, Ink, Paper);
            end if;
         end;
      else
         declare
            P : constant Pixel :=
              (if Hires
               then Video.Colours (7 - Natural (Shift_Right (SCLD and 16#38#,
                                                              3)) + 8)
               elsif Plus_On then Plus_Colour (8 + Border_Colour)
               else Video.Colours (Border_Colour));
         begin
            Put8 (Y, X, 0, P, P);
         end;
      end if;
   end Draw_Chunk;

   procedure Set_SCLD (V : Byte; T : Integer) is
   begin
      Render_To (T);
      SCLD := V;
   end Set_SCLD;

   procedure ULAplus_Out (Port : Word; V : Byte; T : Integer) is
   begin
      if Port = 16#BF3B# then
         Plus_Register := V;
      elsif Port = 16#FF3B# then
         Render_To (T);
         if Plus_Register < 64 then
            Plus_Palette (Natural (Plus_Register)) := V;
         elsif Plus_Register = 64 then
            Plus_On := (V and 1) /= 0;
         end if;
      end if;
   end ULAplus_Out;

   function ULAplus_In return Byte is
     (if Plus_Register < 64 then Plus_Palette (Natural (Plus_Register))
      elsif Plus_Register = 64 then (if Plus_On then 1 else 0)
      else 0);

   procedure Reset_Extras is
   begin
      SCLD := 0;
      Plus_Register := 0;
      Plus_Palette := (others => 0);
      Plus_On := False;
   end Reset_Extras;

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
      Video.Wide_Shown := Video.Wide_Drawn;
      Video.Wide_Drawn := False;
      Render_Pos := 0;
      Frame_Counter := Frame_Counter + 1;
   end End_Frame;

   function Floating_Bus (T : Integer) return Byte is
   begin
      if Model in Plus2A .. Plus3 | Pentagon | TC2048 then
         return 16#FF#;
      end if;
      declare
         Rel : constant Integer :=
           T - Display_Start + (if Model in ZX128 .. Plus2 then 2 else 0);
         --  (checked with Richard Butler's 48K timing tests 35 - 37 and
         --  Ramsoft's Floating Spy self test on the 48K and 128K)
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
