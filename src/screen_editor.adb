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

with File_Ext;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Characters.Handling;
with Ada.Directories;
with Interfaces; use Interfaces;
with System;
with Ada.Numerics.Elementary_Functions;
use Ada.Numerics.Elementary_Functions;

with Glib; use Glib;
with Gdk.Event; use Gdk.Event;
with Gdk.Types; use Gdk.Types;
with Gdk.Types.Keysyms; use Gdk.Types.Keysyms;
with Gtk.Box; use Gtk.Box;
with Gtk.Check_Button; use Gtk.Check_Button;
with Gtk.Drawing_Area; use Gtk.Drawing_Area;
with Gtk.Enums; use Gtk.Enums;
with Gtk.Frame; use Gtk.Frame;
with Gtk.GEntry; use Gtk.GEntry;
with Gtk.Label; use Gtk.Label;
with Gtk.Radio_Button; use Gtk.Radio_Button;
with Gtk.Scrolled_Window; use Gtk.Scrolled_Window;
with Gtk.Separator_Tool_Item; use Gtk.Separator_Tool_Item;
with Gtk.Tool_Button; use Gtk.Tool_Button;
with Gtk.Toggle_Button; use Gtk.Toggle_Button;
with Gtk.Toolbar; use Gtk.Toolbar;
with Gtk.Widget; use Gtk.Widget;
with Gtk.Window; use Gtk.Window;
with Cairo; use Cairo;
with Cairo.Image_Surface;
with Cairo.Pattern;
with Cairo.Png;
with Cairo.Surface;

with Types; use Types;
with Machine;
with Memory;
with Video;
with Settings;
with Editor_Util; use Editor_Util;
with Tap_Files;

package body Screen_Editor is

   Zoom : constant := 3;

   subtype Screen is Byte_Array (0 .. 6911);
   Scr : Screen := (others => 0);

   Win : Gtk_Window := null;
   Canvas, Palette : Gtk_Drawing_Area;
   Status : Gtk_Label;
   Live, Set_Attr, Show_Grid, Bright_B, Flash_B, Dither_B : Gtk_Check_Button;
   Surf : Cairo_Surface;
   File : Unbounded_String;

   Ink : Natural := 0;
   Paper : Natural := 7;

   type Tool_Kind is (Pencil, Line, Rect, Box, Circle, Fill, Attribute,
                      Text);
   Tool : Tool_Kind := Pencil;
   Tool_Buttons : array (Tool_Kind) of Gtk_Radio_Button;

   Text_Entry : Gtk_GEntry;
   Snap : Boolean := True;          --  text on character cells
   Dragging : Boolean := False;
   Draw_Ink : Boolean := True;
   Start_X, Start_Y, Last_X, Last_Y : Integer := 0;
   Base : Screen;                    --  before the current shape

   Max_Undo : constant := 32;
   Undo_Stack : array (1 .. Max_Undo) of Screen;
   Undo_Count : Natural := 0;

   function Is_Screen_File (Path : String) return Boolean is
      E : constant String := Ada.Characters.Handling.To_Lower
        (File_Ext.Of_Path (Path));
   begin
      return E = "scr" or else E = "png";
   end Is_Screen_File;

   ---------------------------------------------------------------------
   --  Screen memory
   ---------------------------------------------------------------------

   function Pixel_Offset (X, Y : Natural) return Natural is
     ((Y / 64) * 2048 + (Y mod 8) * 256 + ((Y / 8) mod 8) * 32 + X / 8);
   function Attr_Offset (X, Y : Natural) return Natural is
     (6144 + (Y / 8) * 32 + X / 8);

   function Get (X, Y : Natural) return Boolean is
     ((Scr (Pixel_Offset (X, Y)) and Shift_Right (Byte'(16#80#), X mod 8))
      /= 0);

   function Current_Attr return Byte is
     (Byte (Ink) or Shift_Left (Byte (Paper), 3)
      or (if Bright_B.Get_Active then 16#40# else 0)
      or (if Flash_B.Get_Active then 16#80# else 0));

   procedure Put (X, Y : Integer; On : Boolean) is
   begin
      if X not in 0 .. 255 or else Y not in 0 .. 191 then
         return;
      end if;
      declare
         O : constant Natural := Pixel_Offset (X, Y);
         M : constant Byte := Shift_Right (Byte'(16#80#), X mod 8);
      begin
         Scr (O) := (if On then Scr (O) or M else Scr (O) and not M);
         if Set_Attr.Get_Active then
            Scr (Attr_Offset (X, Y)) := Current_Attr;
         end if;
      end;
   end Put;

   procedure Put_Attr (X, Y : Integer) is
   begin
      if X in 0 .. 255 and then Y in 0 .. 191 then
         Scr (Attr_Offset (X, Y)) := Current_Attr;
      end if;
   end Put_Attr;

   procedure Draw_Line (X0, Y0, X1, Y1 : Integer; On : Boolean) is
      DX : constant Integer := abs (X1 - X0);
      DY : constant Integer := -abs (Y1 - Y0);
      SX : constant Integer := (if X0 < X1 then 1 else -1);
      SY : constant Integer := (if Y0 < Y1 then 1 else -1);
      Err : Integer := DX + DY;
      X : Integer := X0;
      Y : Integer := Y0;
   begin
      loop
         if Tool = Attribute then
            Put_Attr (X, Y);
         else
            Put (X, Y, On);
         end if;
         exit when X = X1 and then Y = Y1;
         declare
            E2 : constant Integer := 2 * Err;
         begin
            if E2 >= DY then
               Err := Err + DY;
               X := X + SX;
            end if;
            if E2 <= DX then
               Err := Err + DX;
               Y := Y + SY;
            end if;
         end;
      end loop;
   end Draw_Line;

   procedure Draw_Circle (CX, CY, R : Integer; On : Boolean) is
      X : Integer := R;
      Y : Integer := 0;
      Err : Integer := 1 - R;
   begin
      while X >= Y loop
         Put (CX + X, CY + Y, On); Put (CX - X, CY + Y, On);
         Put (CX + X, CY - Y, On); Put (CX - X, CY - Y, On);
         Put (CX + Y, CY + X, On); Put (CX - Y, CY + X, On);
         Put (CX + Y, CY - X, On); Put (CX - Y, CY - X, On);
         Y := Y + 1;
         if Err < 0 then
            Err := Err + 2 * Y + 1;
         else
            X := X - 1;
            Err := Err + 2 * (Y - X) + 1;
         end if;
      end loop;
   end Draw_Circle;

   procedure Flood (X0, Y0 : Integer; On : Boolean) is
      Stack_X, Stack_Y : array (1 .. 256 * 192) of Integer;
      N : Natural := 0;
      Target : Boolean;
   begin
      if X0 not in 0 .. 255 or else Y0 not in 0 .. 191 then
         return;
      end if;
      Target := Get (X0, Y0);
      if Target = On then
         return;
      end if;
      N := 1;
      Stack_X (1) := X0;
      Stack_Y (1) := Y0;
      while N > 0 loop
         declare
            X : constant Integer := Stack_X (N);
            Y : constant Integer := Stack_Y (N);
         begin
            N := N - 1;
            if X in 0 .. 255 and then Y in 0 .. 191
              and then Get (X, Y) = Target
            then
               Put (X, Y, On);
               if N + 4 <= Stack_X'Last then
                  Stack_X (N + 1) := X + 1; Stack_Y (N + 1) := Y;
                  Stack_X (N + 2) := X - 1; Stack_Y (N + 2) := Y;
                  Stack_X (N + 3) := X;     Stack_Y (N + 3) := Y + 1;
                  Stack_X (N + 4) := X;     Stack_Y (N + 4) := Y - 1;
                  N := N + 4;
               end if;
            end if;
         end;
      end loop;
   end Flood;

   ---------------------------------------------------------------------
   --  Emulator link
   ---------------------------------------------------------------------

   procedure Send (Quiet : Boolean := False) is
   begin
      if Machine.Is_ZX81 then
         if not Quiet then
            Status.Set_Text ("switch to a Spectrum to show the screen");
         end if;
         return;
      end if;
      for K in Scr'Range loop
         Machine.Bank_Poke (Machine.Screen_Bank, K, Scr (K));
      end loop;
      if not Quiet then
         Status.Set_Text ("written to the emulator's screen");
      end if;
   end Send;

   procedure Grab is
   begin
      for K in Scr'Range loop
         Scr (K) := Machine.Bank_Peek (Machine.Screen_Bank, K);
      end loop;
      Status.Set_Text ("copied the emulator's screen");
   end Grab;

   ---------------------------------------------------------------------
   --  Drawing
   ---------------------------------------------------------------------

   Flash_Phase : Boolean := False;

   procedure Render is
      Stride : constant Natural :=
        Natural (Cairo.Image_Surface.Get_Stride (Surf)) / 4;
      Addr : constant System.Address :=
        Cairo.Image_Surface.Get_Data_Generic (Surf);
      type Pixels is array (0 .. 191, 0 .. Stride - 1) of Pixel;
      Dst : Pixels;
      for Dst'Address use Addr;
      pragma Import (Ada, Dst);
   begin
      Cairo.Surface.Flush (Surf);
      for Y in 0 .. 191 loop
         for X in 0 .. 255 loop
            declare
               A : constant Byte := Scr (Attr_Offset (X, Y));
               B : constant Natural := (if (A and 16#40#) /= 0 then 8 else 0);
               On : Boolean := Get (X, Y);
            begin
               if (A and 16#80#) /= 0 and then Flash_Phase then
                  On := not On;
               end if;
               Dst (Y, X) := Video.Colours
                 ((if On then Natural (A and 7)
                   else Natural (Shift_Right (A, 3) and 7)) + B);
            end;
         end loop;
      end loop;
      Cairo.Surface.Mark_Dirty (Surf);
   end Render;

   function On_Canvas_Draw (Self : access Gtk_Widget_Record'Class;
                            Cr : Cairo_Context) return Boolean is
      pragma Unreferenced (Self);
   begin
      Render;
      Save (Cr);
      Cairo.Scale (Cr, Gdouble (Zoom), Gdouble (Zoom));
      Set_Source_Surface (Cr, Surf, 0.0, 0.0);
      Cairo.Pattern.Set_Filter (Get_Source (Cr),
                                Cairo.Pattern.Cairo_Filter_Nearest);
      Paint (Cr);
      Restore (Cr);
      if Show_Grid.Get_Active then
         Set_Source_Rgba (Cr, 0.5, 0.5, 0.5, 0.5);
         Set_Line_Width (Cr, 1.0);
         for I in 0 .. 32 loop
            Move_To (Cr, Gdouble (I * 8 * Zoom) + 0.5, 0.0);
            Line_To (Cr, Gdouble (I * 8 * Zoom) + 0.5, Gdouble (192 * Zoom));
         end loop;
         for I in 0 .. 24 loop
            Move_To (Cr, 0.0, Gdouble (I * 8 * Zoom) + 0.5);
            Line_To (Cr, Gdouble (256 * Zoom), Gdouble (I * 8 * Zoom) + 0.5);
         end loop;
         Stroke (Cr);
      end if;
      return True;
   end On_Canvas_Draw;

   Swatch : constant := 36;

   function On_Palette_Draw (Self : access Gtk_Widget_Record'Class;
                             Cr : Cairo_Context) return Boolean is
      pragma Unreferenced (Self);
      B : constant Natural := (if Bright_B.Get_Active then 8 else 0);
   begin
      for C in 0 .. 7 loop
         Set_Colour (Cr, Byte (C + B));
         Rectangle (Cr, Gdouble (C * Swatch), 0.0, Gdouble (Swatch - 2),
                    Gdouble (Swatch - 2));
         Cairo.Fill (Cr);
         if C = Ink or else C = Paper then
            Set_Source_Rgb (Cr, 1.0, 0.3, 0.3);
            Set_Line_Width (Cr, 3.0);
            Rectangle (Cr, Gdouble (C * Swatch) + 1.5, 1.5,
                       Gdouble (Swatch - 5), Gdouble (Swatch - 5));
            Stroke (Cr);
            Set_Source_Rgb (Cr, 1.0, 0.3, 0.3);
            Move_To (Cr, Gdouble (C * Swatch) + 4.0, Gdouble (Swatch) + 12.0);
            Show_Text (Cr, (if C = Ink and then C = Paper then "I+P"
                            elsif C = Ink then "ink" else "paper"));
         end if;
      end loop;
      return True;
   end On_Palette_Draw;

   procedure Show_Status (X, Y : Integer := -1) is
   begin
      Status.Set_Text
        ((if X >= 0 then "x" & X'Image & " y" & Y'Image &
            "  (PLOT" & Integer'Image (X) & "," & Integer'Image (175 - Y) &
            ")  cell" & Integer'Image (X / 8) & "," & Integer'Image (Y / 8) &
            "   " else "") &
         "ink " & Physical_Name (Byte (Ink)) & ", paper " &
         Physical_Name (Byte (Paper)) & "   " &
         (if File = Null_Unbounded_String then "(not saved)"
          else To_String (File)));
   end Show_Status;

   procedure Changed is
   begin
      if Live.Get_Active then
         Send (Quiet => True);
      end if;
      Canvas.Queue_Draw;
   end Changed;

   procedure Push_Undo is
   begin
      if Undo_Count = Max_Undo then
         Undo_Stack (1 .. Max_Undo - 1) := Undo_Stack (2 .. Max_Undo);
         Undo_Count := Max_Undo - 1;
      end if;
      Undo_Count := Undo_Count + 1;
      Undo_Stack (Undo_Count) := Scr;
   end Push_Undo;

   procedure Undo is
   begin
      if Undo_Count > 0 then
         Scr := Undo_Stack (Undo_Count);
         Undo_Count := Undo_Count - 1;
         Changed;
      end if;
   end Undo;

   ---------------------------------------------------------------------
   --  Mouse
   ---------------------------------------------------------------------

   function PX (V : Gdouble) return Integer is
     (Integer (Gdouble'Floor (V / Gdouble (Zoom))));

   --  The entry's text in the 48K ROM's font, like PRINT (ink on paper;
   --  On = False: inverse), at the pixel X, Y
   procedure Stamp_Text (X, Y : Integer; On : Boolean) is
      T : constant String := Text_Entry.Get_Text;
      Font : constant Natural :=
        Memory.ROM_Base (Memory.Basic48_ROM) + 16#3D00#;
      X0 : constant Integer := (if Snap then X - X mod 8 else X);
      Y0 : constant Integer := (if Snap then Y - Y mod 8 else Y);
   begin
      for I in T'Range loop
         declare
            Code : constant Natural :=
              (if Character'Pos (T (I)) in 32 .. 127
               then Character'Pos (T (I)) else 63);
            CX : constant Integer := X0 + (I - T'First) * 8;
         begin
            for R in 0 .. 7 loop
               declare
                  G : constant Byte := Memory.Store (Font + (Code - 32) * 8 + R);
               begin
                  for B in 0 .. 7 loop
                     Put (CX + B, Y0 + R,
                          ((G and Shift_Right (Byte'(16#80#), B)) /= 0) = On);
                  end loop;
               end;
            end loop;
         end;
      end loop;
   end Stamp_Text;

   procedure Apply_Shape (X, Y : Integer) is
   begin
      Scr := Base;
      case Tool is
         when Line =>
            Draw_Line (Start_X, Start_Y, X, Y, Draw_Ink);
         when Rect =>
            Draw_Line (Start_X, Start_Y, X, Start_Y, Draw_Ink);
            Draw_Line (X, Start_Y, X, Y, Draw_Ink);
            Draw_Line (X, Y, Start_X, Y, Draw_Ink);
            Draw_Line (Start_X, Y, Start_X, Start_Y, Draw_Ink);
         when Box =>
            for YY in Integer'Min (Start_Y, Y) .. Integer'Max (Start_Y, Y) loop
               Draw_Line (Start_X, YY, X, YY, Draw_Ink);
            end loop;
         when Circle =>
            Draw_Circle (Start_X, Start_Y,
                         Integer (Float'Rounding (Sqrt
                           (Float ((X - Start_X) ** 2
                                   + (Y - Start_Y) ** 2)))),
                         Draw_Ink);
         when Text =>
            Stamp_Text (X, Y, Draw_Ink);
         when others => null;
      end case;
   end Apply_Shape;

   function On_Press (Self : access Gtk_Widget_Record'Class;
                      Event : Gdk_Event_Button) return Boolean is
      pragma Unreferenced (Self);
      X : constant Integer := PX (Event.X);
      Y : constant Integer := PX (Event.Y);
   begin
      if X not in 0 .. 255 or else Y not in 0 .. 191 then
         return True;
      end if;
      Push_Undo;
      Draw_Ink := Event.Button /= 3;
      Snap := (Event.State and Shift_Mask) = 0;
      Dragging := True;
      Start_X := X;
      Start_Y := Y;
      Last_X := X;
      Last_Y := Y;
      Base := Scr;
      case Tool is
         when Pencil => Put (X, Y, Draw_Ink);
         when Attribute => Put_Attr (X, Y);
         when Fill =>
            Flood (X, Y, Draw_Ink);
            Dragging := False;
         when others => Apply_Shape (X, Y);
      end case;
      Changed;
      return True;
   end On_Press;

   function On_Motion (Self : access Gtk_Widget_Record'Class;
                       Event : Gdk_Event_Motion) return Boolean is
      pragma Unreferenced (Self);
      X : constant Integer := Integer'Max (0, Integer'Min (255, PX (Event.X)));
      Y : constant Integer := Integer'Max (0, Integer'Min (191, PX (Event.Y)));
   begin
      Show_Status (X, Y);
      if not Dragging then
         return True;
      end if;
      case Tool is
         when Pencil | Attribute =>
            Draw_Line (Last_X, Last_Y, X, Y, Draw_Ink);
         when Fill => null;
         when others => Apply_Shape (X, Y);
      end case;
      Last_X := X;
      Last_Y := Y;
      Changed;
      return True;
   end On_Motion;

   function On_Release (Self : access Gtk_Widget_Record'Class;
                        Event : Gdk_Event_Button) return Boolean is
      pragma Unreferenced (Self, Event);
   begin
      Dragging := False;
      return True;
   end On_Release;

   function On_Palette_Press (Self : access Gtk_Widget_Record'Class;
                              Event : Gdk_Event_Button) return Boolean is
      pragma Unreferenced (Self);
      C : constant Integer := Integer (Gdouble'Floor (Event.X / Gdouble (Swatch)));
   begin
      if C in 0 .. 7 then
         if Event.Button = 3 then
            Paper := C;
         else
            Ink := C;
         end if;
         Palette.Queue_Draw;
         Show_Status;
      end if;
      return True;
   end On_Palette_Press;

   ---------------------------------------------------------------------
   --  Files and conversion
   ---------------------------------------------------------------------

   procedure Load_Scr (Path : String) is
      Ok : Boolean;
      D : constant Byte_Array := Read_Bytes (Path, Ok);
   begin
      if not Ok or else D'Length < 6144 then
         Message (Win, "Not a screen file: " & Path);
         return;
      end if;
      Push_Undo;
      Scr := (others => 16#38#);
      Scr (0 .. 6143) := (others => 0);
      for K in 0 .. Natural'Min (6912, D'Length) - 1 loop
         Scr (K) := D (D'First + K);
      end loop;
      File := To_Unbounded_String (Path);
      Settings.Set ("scr_file", Path);
      Changed;
      Show_Status;
   end Load_Scr;

   --  Convert an image: each 8 x 8 cell gets the ink / paper pair (and
   --  BRIGHT) that matches its pixels best
   procedure Import_PNG (Path : String) is
      Img : Cairo_Surface := Cairo.Png.Create_From_Png (Path);
      use type Cairo_Status;
   begin
      if Cairo.Surface.Status (Img) /= Cairo_Status_Success then
         Message (Win, "Cannot read the PNG image " & Path);
         return;
      end if;
      Push_Undo;
      declare
         IW : constant Natural := Natural (Cairo.Image_Surface.Get_Width (Img));
         IH : constant Natural :=
           Natural (Cairo.Image_Surface.Get_Height (Img));
         Stride : constant Natural :=
           Natural (Cairo.Image_Surface.Get_Stride (Img)) / 4;
         Addr : constant System.Address :=
           Cairo.Image_Surface.Get_Data_Generic (Img);
         type Pixels is array (0 .. IH - 1, 0 .. Stride - 1) of U32;
         Src : Pixels;
         for Src'Address use Addr;
         pragma Import (Ada, Src);
         type RGB is record
            R, G, B : Float;
         end record;
         Target : array (0 .. 191, 0 .. 255) of RGB;
         Scale : constant Float :=
           Float'Max (Float (IW) / 256.0, Float (IH) / 192.0);
         Dither : constant Boolean := Dither_B.Get_Active;
         Bayer : constant array (0 .. 3, 0 .. 3) of Float :=
           ((0.0, 8.0, 2.0, 10.0), (12.0, 4.0, 14.0, 6.0),
            (3.0, 11.0, 1.0, 9.0), (15.0, 7.0, 13.0, 5.0));
         function Pal (C : Natural) return RGB is
            P : constant Pixel := Video.Colours (C);
         begin
            return (Float (Shift_Right (P, 16) and 255),
                    Float (Shift_Right (P, 8) and 255), Float (P and 255));
         end Pal;
         function Dist (A, B : RGB) return Float is
           ((A.R - B.R) ** 2 * 0.3 + (A.G - B.G) ** 2 * 0.59
            + (A.B - B.B) ** 2 * 0.11);
      begin
         Cairo.Surface.Flush (Img);
         --  box-filter the image into 256 x 192 (aspect kept, centred)
         for Y in 0 .. 191 loop
            for X in 0 .. 255 loop
               declare
                  OX : constant Float := (256.0 * Scale - Float (IW)) / 2.0;
                  OY : constant Float := (192.0 * Scale - Float (IH)) / 2.0;
                  X0 : constant Integer := Integer (Float'Floor (Float (X) * Scale - OX));
                  Y0 : constant Integer := Integer (Float'Floor (Float (Y) * Scale - OY));
                  X1 : constant Integer :=
                    Integer'Max (X0 + 1, Integer (Float'Floor (Float (X + 1) * Scale - OX)));
                  Y1 : constant Integer :=
                    Integer'Max (Y0 + 1, Integer (Float'Floor (Float (Y + 1) * Scale - OY)));
                  Sum : RGB := (0.0, 0.0, 0.0);
                  N : Natural := 0;
               begin
                  for SY in Y0 .. Y1 - 1 loop
                     for SX in X0 .. X1 - 1 loop
                        if SX in 0 .. IW - 1 and then SY in 0 .. IH - 1 then
                           declare
                              P : constant U32 := Src (SY, SX);
                           begin
                              Sum.R := Sum.R + Float (Shift_Right (P, 16) and 255);
                              Sum.G := Sum.G + Float (Shift_Right (P, 8) and 255);
                              Sum.B := Sum.B + Float (P and 255);
                              N := N + 1;
                           end;
                        end if;
                     end loop;
                  end loop;
                  Target (Y, X) :=
                    (if N = 0 then (0.0, 0.0, 0.0)
                     else (Sum.R / Float (N), Sum.G / Float (N),
                           Sum.B / Float (N)));
               end;
            end loop;
         end loop;
         --  per cell: best pair
         for CY in 0 .. 23 loop
            for CX in 0 .. 31 loop
               declare
                  Best_E : Float := Float'Last;
                  Best_I, Best_P, Best_B : Natural := 0;
               begin
                  for Br in 0 .. 1 loop
                     for I in 0 .. 7 loop
                        for P in I .. 7 loop
                           declare
                              E : Float := 0.0;
                              CI : constant RGB := Pal (I + 8 * Br);
                              CP : constant RGB := Pal (P + 8 * Br);
                           begin
                              for Y in CY * 8 .. CY * 8 + 7 loop
                                 for X in CX * 8 .. CX * 8 + 7 loop
                                    E := E + Float'Min
                                      (Dist (Target (Y, X), CI),
                                       Dist (Target (Y, X), CP));
                                 end loop;
                              end loop;
                              if E < Best_E then
                                 Best_E := E;
                                 Best_I := I;
                                 Best_P := P;
                                 Best_B := Br;
                              end if;
                           end;
                        end loop;
                     end loop;
                  end loop;
                  Scr (6144 + CY * 32 + CX) :=
                    Byte (Best_I) or Shift_Left (Byte (Best_P), 3)
                    or (if Best_B = 1 then 16#40# else 0);
                  declare
                     CI : constant RGB := Pal (Best_I + 8 * Best_B);
                     CP : constant RGB := Pal (Best_P + 8 * Best_B);
                     Span : constant Float := Float'Max (1.0, Dist (CI, CP));
                  begin
                     for Y in CY * 8 .. CY * 8 + 7 loop
                        for X in CX * 8 .. CX * 8 + 7 loop
                           declare
                              DI : constant Float := Dist (Target (Y, X), CI);
                              DP : constant Float := Dist (Target (Y, X), CP);
                              On : Boolean;
                           begin
                              if Dither and then Best_I /= Best_P then
                                 --  position between paper (0) and ink (1)
                                 declare
                                    T : constant Float :=
                                      Float'Max (0.0, Float'Min (1.0,
                                        0.5 + (DP - DI) / (2.0 * Span)));
                                 begin
                                    On := T > (Bayer (Y mod 4, X mod 4) + 0.5)
                                      / 16.0;
                                 end;
                              else
                                 On := DI < DP;
                              end if;
                              declare
                                 O : constant Natural := Pixel_Offset (X, Y);
                                 Msk : constant Byte :=
                                   Shift_Right (Byte'(16#80#), X mod 8);
                              begin
                                 Scr (O) := (if On then Scr (O) or Msk
                                             else Scr (O) and not Msk);
                              end;
                           end;
                        end loop;
                     end loop;
                  end;
               end;
            end loop;
         end loop;
      end;
      Cairo.Surface.Destroy (Img);
      File := Null_Unbounded_String;
      Changed;
      Status.Set_Text ("imported " & Path & " (save it as .scr)");
   end Import_PNG;

   procedure Open_File (Path : String) is
   begin
      if Ada.Characters.Handling.To_Lower (File_Ext.Of_Path (Path))
        = "png"
      then
         Import_PNG (Path);
      else
         Load_Scr (Path);
      end if;
   end Open_File;

   procedure Save_File (Ask : Boolean) is
      Ok : Boolean;
   begin
      if Ask or else File = Null_Unbounded_String then
         declare
            P : constant String := Choose_File
              (Win, "Save screen", True, "Spectrum screens (.scr)", "*.scr",
               "screen.scr");
         begin
            if P = "" then
               return;
            end if;
            File := To_Unbounded_String (P);
         end;
      end if;
      Write_Bytes (To_String (File), Scr, Ok);
      if Ok then
         Settings.Set ("scr_file", To_String (File));
         Show_Status;
      else
         Message (Win, "Cannot write " & To_String (File));
      end if;
   end Save_File;

   function Base_Of (Ext : String) return String is
      F : constant String :=
        (if File = Null_Unbounded_String then "screen" else To_String (File));
   begin
      return (if Ada.Directories.Extension (F) = "" then F
              else F (F'First .. F'Last - Ada.Directories.Extension (F)'Length
                      - 1)) & Ext;
   end Base_Of;

   procedure Export_Asm is
      R : Unbounded_String;
      Ok : Boolean;
   begin
      Append (R, "; Spectrum screen: 6144 bytes of bitmap, 768 attributes"
              & ASCII.LF & "screen_data:" & ASCII.LF);
      for Row in 0 .. 6911 / 16 loop
         Append (R, "            db ");
         for K in 0 .. 15 loop
            Append (R, "$" & Hex2 (Natural (Scr (Row * 16 + K))) &
                      (if K < 15 then "," else ""));
         end loop;
         Append (R, ASCII.LF);
      end loop;
      Write_Text (Base_Of ("_scr.asm"), To_String (R), Ok);
      Status.Set_Text (if Ok then "wrote " & Base_Of ("_scr.asm")
                       else "cannot write " & Base_Of ("_scr.asm"));
   end Export_Asm;

   procedure Export_Tape is
      Ok : Boolean;
      Name : constant String := Ada.Directories.Base_Name (Base_Of (".scr"));
   begin
      Write_Bytes
        (Base_Of (".tap"),
         Tap_Files.Program ("loader",
                            "10 LOAD """"SCREEN$ : PAUSE 0") &
         Tap_Files.Code (Name, Scr, 16384), Ok);
      Status.Set_Text (if Ok then "wrote " & Base_Of (".tap") &
                         " (LOAD """" shows the screen)"
                       else "cannot write " & Base_Of (".tap"));
   end Export_Tape;

   ---------------------------------------------------------------------
   --  Actions and window
   ---------------------------------------------------------------------

   type Action is (A_New, A_Open, A_Save, A_Save_As, A_Export_Asm,
                   A_Export_Tape, A_Undo, A_Clear_Cells, A_Invert,
                   A_Show, A_Grab);
   Tool_Items : array (Action) of Gtk_Tool_Button;

   procedure Do_Action (A : Action) is
   begin
      case A is
         when A_New =>
            Push_Undo;
            Scr := (others => 0);
            Scr (6144 .. 6911) := (others => Current_Attr);
            File := Null_Unbounded_String;
         when A_Open =>
            declare
               P : constant String := Choose_File
                 (Win, "Open screen or image", False,
                  "Screens and images (.scr, .png)", "*.*");
            begin
               if P /= "" then
                  Open_File (P);
               end if;
            end;
         when A_Save => Save_File (False);
         when A_Save_As => Save_File (True);
         when A_Export_Asm => Export_Asm;
         when A_Export_Tape => Export_Tape;
         when A_Undo => Undo;
         when A_Clear_Cells =>
            Push_Undo;
            Scr (6144 .. 6911) := (others => Current_Attr);
         when A_Invert =>
            Push_Undo;
            for K in 0 .. 6143 loop
               Scr (K) := not Scr (K);
            end loop;
         when A_Show => Send;
         when A_Grab =>
            Push_Undo;
            Grab;
      end case;
      Changed;
      if A in A_New | A_Open | A_Save | A_Save_As | A_Undo then
         Show_Status;
      end if;
   end Do_Action;

   procedure On_Tool (Item : access Gtk_Tool_Button_Record'Class) is
   begin
      for A in Action loop
         if Tool_Items (A) = Gtk_Tool_Button (Item) then
            Do_Action (A);
         end if;
      end loop;
   end On_Tool;

   procedure On_Tool_Kind (Self : access Gtk_Toggle_Button_Record'Class) is
   begin
      for T in Tool_Kind loop
         if Tool_Buttons (T) = Gtk_Radio_Button (Self)
           and then Self.Get_Active
         then
            Tool := T;
         end if;
      end loop;
   end On_Tool_Kind;

   procedure On_Option (Self : access Gtk_Toggle_Button_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Canvas.Queue_Draw;
      Palette.Queue_Draw;
   end On_Option;

   procedure On_Live (Self : access Gtk_Toggle_Button_Record'Class) is
   begin
      if Self.Get_Active then
         Send;
      end if;
   end On_Live;

   function On_Key (Self : access Gtk_Widget_Record'Class;
                    Event : Gdk_Event_Key) return Boolean is
      pragma Unreferenced (Self);
      Ctrl : constant Boolean := (Event.State and Control_Mask) /= 0;
   begin
      if Ctrl and then Event.Keyval = GDK_LC_z then
         Undo;
      elsif Ctrl and then Event.Keyval = GDK_LC_s then
         Save_File (False);
      else
         return False;
      end if;
      return True;
   end On_Key;

   function On_Delete (Self : access Gtk_Widget_Record'Class;
                       Event : Gdk_Event) return Boolean is
      pragma Unreferenced (Self, Event);
   begin
      Win.Hide;
      return True;
   end On_Delete;

   procedure Build is
      VBox, HBox, Side : Gtk_Box;
      Tools : Gtk_Toolbar;
      Frame : Gtk_Frame;
      Scroll : Gtk_Scrolled_Window;
      Group : Widget_SList.GSlist := Widget_SList.Null_List;

      procedure Tool_Button (Label : String; A : Action; Tip : String;
                             Icon : String := "") is
      begin
         Gtk_New (Tool_Items (A), Label => Label);
         if Icon /= "" then
            Tool_Items (A).Set_Icon_Name (Icon);
         end if;
         Tool_Items (A).Set_Tooltip_Text (Tip);
         Tool_Items (A).Set_Is_Important (True);
         Tool_Items (A).On_Clicked (On_Tool'Access);
         Tools.Insert (Tool_Items (A));
      end Tool_Button;

      procedure Sep is
         S : Gtk_Separator_Tool_Item;
      begin
         Gtk_New (S);
         Tools.Insert (S);
      end Sep;

      procedure Check (B : out Gtk_Check_Button; Label : String;
                       Active : Boolean := False) is
      begin
         Gtk_New (B, Label);
         B.Set_Active (Active);
         B.On_Toggled (On_Option'Access);
         Side.Pack_Start (B, Expand => False, Fill => False);
      end Check;

      Names : constant array (Tool_Kind) of Unbounded_String :=
        (To_Unbounded_String ("Pencil"), To_Unbounded_String ("Line"),
         To_Unbounded_String ("Rectangle"),
         To_Unbounded_String ("Filled rectangle"),
         To_Unbounded_String ("Circle"), To_Unbounded_String ("Fill"),
         To_Unbounded_String ("Attribute brush"),
         To_Unbounded_String ("Text (drag to place)"));
   begin
      Gtk_New (Win);
      Win.Set_Title ("Spectrum screen editor");
      Win.Set_Default_Size (1080, 700);
      Win.On_Delete_Event (On_Delete'Access);
      Win.On_Key_Press_Event (On_Key'Access);
      Gtk_New_Vbox (VBox);
      Win.Add (VBox);

      Gtk_New (Tools);
      Tools.Set_Style (Toolbar_Both_Horiz);
      Tool_Button ("New", A_New, "Clear to the current colours",
                   "document-new");
      Tool_Button ("Open", A_Open, "Open a .scr, or import a .png",
                   "document-open");
      Tool_Button ("Save", A_Save, "Save as .scr (Ctrl+S)", "document-save");
      Tool_Button ("Save as", A_Save_As, "Save under a new name");
      Tool_Button ("Export .asm", A_Export_Asm, "Write db lines");
      Tool_Button ("Export .tap", A_Export_Tape,
                   "A tape with LOAD """"SCREEN$ and the screen");
      Tool_Button ("Undo", A_Undo, "Undo (Ctrl+Z)", "edit-undo");
      Sep;
      Tool_Button ("Colour all cells", A_Clear_Cells,
                   "Give every cell the current ink / paper");
      Tool_Button ("Invert", A_Invert, "Invert all pixels");
      Sep;
      Tool_Button ("Show in emulator", A_Show, "Copy into the screen memory");
      Tool_Button ("Grab from emulator", A_Grab,
                   "Copy the emulator's screen");
      VBox.Pack_Start (Tools, Expand => False, Fill => False);

      Gtk_New_Hbox (HBox, Spacing => 8);
      VBox.Pack_Start (HBox, Expand => True, Fill => True);

      Gtk_New (Canvas);
      Canvas.Set_Size_Request (256 * Zoom, 192 * Zoom);
      Canvas.Add_Events (Button_Press_Mask or Button_Release_Mask
                         or Pointer_Motion_Mask);
      Canvas.On_Draw (On_Canvas_Draw'Access);
      Canvas.On_Button_Press_Event (On_Press'Access);
      Canvas.On_Button_Release_Event (On_Release'Access);
      Canvas.On_Motion_Notify_Event (On_Motion'Access);
      Gtk_New (Scroll);
      Scroll.Add (Canvas);
      Gtk_New (Frame, "Screen (left: ink, right: paper)");
      Frame.Add (Scroll);
      HBox.Pack_Start (Frame, Expand => True, Fill => True, Padding => 4);

      Gtk_New_Vbox (Side, Spacing => 4);
      HBox.Pack_Start (Side, Expand => False, Fill => False, Padding => 4);
      for T in Tool_Kind loop
         Gtk_New (Tool_Buttons (T), Group, To_String (Names (T)));
         Group := Tool_Buttons (T).Get_Group;
         Tool_Buttons (T).On_Toggled (On_Tool_Kind'Access);
         Side.Pack_Start (Tool_Buttons (T), Expand => False, Fill => False);
      end loop;
      Gtk_New (Text_Entry);
      Text_Entry.Set_Text ("HELLO");
      Text_Entry.Set_Tooltip_Text
        ("Text for the Text tool, in the ROM font: on character cells " &
         "(Shift: anywhere); right button: inverse");
      Side.Pack_Start (Text_Entry, Expand => False, Fill => False);

      Gtk_New (Palette);
      Palette.Set_Size_Request (8 * Swatch, Swatch + 18);
      Palette.Add_Events (Button_Press_Mask);
      Palette.On_Draw (On_Palette_Draw'Access);
      Palette.On_Button_Press_Event (On_Palette_Press'Access);
      Gtk_New (Frame, "Colour (left: ink, right: paper)");
      Frame.Add (Palette);
      Side.Pack_Start (Frame, Expand => False, Fill => False, Padding => 6);
      Check (Bright_B, "BRIGHT");
      Check (Flash_B, "FLASH");
      Check (Set_Attr, "Drawing sets the cell colours", True);
      Check (Show_Grid, "Show the 8 x 8 cell grid", True);
      Check (Dither_B, "Dither when importing PNG images", True);
      Gtk_New (Live, "Live in emulator");
      Live.On_Toggled (On_Live'Access);
      Side.Pack_Start (Live, Expand => False, Fill => False);

      Gtk_New (Status, "");
      Status.Set_Halign (Align_Start);
      Status.Set_Selectable (True);
      VBox.Pack_Start (Status, Expand => False, Fill => False, Padding => 4);

      Surf := Cairo.Image_Surface.Create
        (Cairo.Image_Surface.Cairo_Format_RGB24, 256, 192);
   end Build;

   procedure Open (Parent : Gtk.Window.Gtk_Window; Path : String := "") is
      pragma Unreferenced (Parent);
   begin
      if Win = null then
         Build;
         Win.Show_All;
         Scr (6144 .. 6911) := (others => 16#38#);
         declare
            Last : constant String := Settings.Get ("scr_file", "");
         begin
            if Path = "" and then Last /= ""
              and then Ada.Directories.Exists (Last)
            then
               Load_Scr (Last);
               Undo_Count := 0;
            end if;
         end;
         Show_Status;
      end if;
      if Path /= "" then
         if Ada.Directories.Exists (Path) then
            Open_File (Ada.Directories.Full_Name (Path));
         else
            File := To_Unbounded_String (Path);
         end if;
      end if;
      Canvas.Queue_Draw;
      Win.Show_All;
      Win.Present;
   end Open;


end Screen_Editor;
