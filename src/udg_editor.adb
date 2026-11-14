-- ***************************************************************************
--                            AdaZX - Udg_Editor
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

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Characters.Handling;
with Ada.Directories;
with Interfaces; use Interfaces;

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
with Gtk.Separator_Tool_Item; use Gtk.Separator_Tool_Item;
with Gtk.Tool_Button; use Gtk.Tool_Button;
with Gtk.Toggle_Button; use Gtk.Toggle_Button;
with Gtk.Toolbar; use Gtk.Toolbar;
with Gtk.Widget; use Gtk.Widget;
with Gtk.Window; use Gtk.Window;
with Cairo; use Cairo;

with Types; use Types;
with Machine;
with Memory;
with Settings;
with Editor_Util; use Editor_Util;

package body UDG_Editor is

   Cell : constant := 40;          --  editor pixel size
   OV : constant := 24;            --  overview cell (3 x 8 pixels)

   type Glyph is array (0 .. 7) of Byte;
   --  0 .. 95: characters 32 .. 127, 96 .. 116: UDGs A .. U
   Glyphs : array (0 .. 116) of Glyph := (others => (others => 0));
   UDG_First : constant := 96;

   type Mode_Type is (UDG_Mode, Font_Mode);
   Mode : Mode_Type := UDG_Mode;

   Win      : Gtk_Window := null;
   Grid, Overview, Text_Area : Gtk_Drawing_Area;
   Status   : Gtk_Label;
   Live     : Gtk_Check_Button;
   Sample   : Gtk_Entry;

   Current  : Natural := UDG_First;
   File     : Unbounded_String;
   Painting : Boolean := False;
   Paint_On : Boolean := True;
   Clip     : Glyph := (others => 0);

   Max_Undo : constant := 64;
   type Undo_Entry is record
      Index : Natural := 0;
      G : Glyph := (others => 0);
   end record;
   Undo_Stack : array (1 .. Max_Undo) of Undo_Entry;
   Undo_Count : Natural := 0;

   function Is_UDG_File (Path : String) return Boolean is
      L : constant String := Ada.Characters.Handling.To_Lower (Path);
   begin
      return L'Length > 4 and then L (L'Last - 3 .. L'Last) = ".udg";
   end Is_UDG_File;

   function First_Glyph return Natural is
     (if Mode = UDG_Mode then UDG_First else 0);
   function Last_Glyph return Natural is
     (if Mode = UDG_Mode then 116 else 95);

   function Glyph_Name (I : Natural) return String is
     (if I >= UDG_First
      then "UDG " & Character'Val (Character'Pos ('A') + I - UDG_First)
      else "character" & Natural'Image (I + 32) &
        (if I + 32 in 33 .. 126
         then " '" & Character'Val (I + 32) & "'" else ""));

   function Pixel (G : Glyph; X, Y : Natural) return Boolean is
     ((G (Y) and Shift_Right (Byte'(16#80#), X)) /= 0);

   procedure Set_Pixel (G : in out Glyph; X, Y : Natural; On : Boolean) is
   begin
      if On then
         G (Y) := G (Y) or Shift_Right (Byte'(16#80#), X);
      else
         G (Y) := G (Y) and not Shift_Right (Byte'(16#80#), X);
      end if;
   end Set_Pixel;

   ---------------------------------------------------------------------
   --  ROM font and the emulator
   ---------------------------------------------------------------------

   function ROM_Glyph (I : Natural) return Glyph is
      --  the 48K BASIC ROM's font at &3D00; UDGs start as copies of A-U
      Code : constant Natural :=
        (if I >= UDG_First then Character'Pos ('A') + I - UDG_First
         else I + 32);
      Base : constant Natural :=
        Memory.ROM_Base (Memory.Basic48_ROM) + 16#3D00# + (Code - 32) * 8;
      G : Glyph;
   begin
      for Y in 0 .. 7 loop
         G (Y) := Memory.Store (Base + Y);
      end loop;
      return G;
   end ROM_Glyph;

   procedure Load_ROM is
   begin
      for I in Glyphs'Range loop
         Glyphs (I) := ROM_Glyph (I);
      end loop;
   end Load_ROM;

   function UDG_Address return Word is (Machine.Peek_Word (23675));
   function Font_Address return Word is (Machine.Peek_Word (23606) + 256);

   procedure Send (Quiet : Boolean := False) is
   begin
      if Machine.Is_ZX81 then
         if not Quiet then
            Status.Set_Text ("the ZX81 has no UDGs (switch to a Spectrum)");
         end if;
         return;
      end if;
      if Mode = UDG_Mode then
         for I in 0 .. 20 loop
            for Y in 0 .. 7 loop
               Machine.Poke (UDG_Address + Word (I * 8 + Y),
                             Glyphs (UDG_First + I) (Y));
            end loop;
         end loop;
         if not Quiet then
            Status.Set_Text ("UDGs written to $" & Hex4 (Natural (UDG_Address))
                             & " (print them with GRAPHICS mode or CHR$ 144-164)");
         end if;
      else
         --  the font goes below the UDGs; CHARS points 256 bytes before it
         declare
            At_Addr : constant Word := UDG_Address - 768;
         begin
            for I in 0 .. 95 loop
               for Y in 0 .. 7 loop
                  Machine.Poke (At_Addr + Word (I * 8 + Y), Glyphs (I) (Y));
               end loop;
            end loop;
            Machine.Poke (23606, Lo (At_Addr - 256));
            Machine.Poke (23607, Hi (At_Addr - 256));
            if not Quiet then
               Status.Set_Text
                 ("font written to $" & Hex4 (Natural (At_Addr)) &
                  " and CHARS set (use CLEAR" &
                  Natural'Image (Natural (At_Addr) - 1) &
                  " in programs to keep it safe)");
            end if;
         end;
      end if;
   end Send;

   procedure Grab is
   begin
      if Machine.Is_ZX81 then
         Status.Set_Text ("the ZX81 has no UDGs");
         return;
      end if;
      if Mode = UDG_Mode then
         for I in 0 .. 20 loop
            for Y in 0 .. 7 loop
               Glyphs (UDG_First + I) (Y) :=
                 Machine.Peek (UDG_Address + Word (I * 8 + Y));
            end loop;
         end loop;
      else
         for I in 0 .. 95 loop
            for Y in 0 .. 7 loop
               Glyphs (I) (Y) := Machine.Peek (Font_Address + Word (I * 8 + Y));
            end loop;
         end loop;
      end if;
      Status.Set_Text ("copied from the emulator");
   end Grab;

   ---------------------------------------------------------------------
   --  Drawing
   ---------------------------------------------------------------------

   procedure Show_Status is
   begin
      Status.Set_Text
        (Glyph_Name (Current) & "   " &
         (if File = Null_Unbounded_String then "(not saved)"
          else To_String (File)));
   end Show_Status;

   procedure Redraw_All is
   begin
      if Win /= null then
         Grid.Queue_Draw;
         Overview.Queue_Draw;
         Text_Area.Queue_Draw;
      end if;
   end Redraw_All;

   procedure Changed_Glyph is
   begin
      if Live.Get_Active then
         Send (Quiet => True);
      end if;
      Redraw_All;
   end Changed_Glyph;

   procedure Draw_Glyph (Cr : Cairo_Context; G : Glyph;
                         X0, Y0 : Gdouble; Scale : Gdouble) is
   begin
      for Y in 0 .. 7 loop
         for X in 0 .. 7 loop
            if Pixel (G, X, Y) then
               Rectangle (Cr, X0 + Gdouble (X) * Scale,
                          Y0 + Gdouble (Y) * Scale, Scale, Scale);
            end if;
         end loop;
      end loop;
      Cairo.Fill (Cr);
   end Draw_Glyph;

   function On_Grid_Draw (Self : access Gtk_Widget_Record'Class;
                          Cr : Cairo_Context) return Boolean is
      pragma Unreferenced (Self);
   begin
      Set_Colour (Cr, 15);
      Paint (Cr);
      Set_Colour (Cr, 0);
      Draw_Glyph (Cr, Glyphs (Current), 0.0, 0.0, Gdouble (Cell));
      Set_Source_Rgb (Cr, 0.7, 0.7, 0.7);
      Set_Line_Width (Cr, 1.0);
      for I in 0 .. 8 loop
         Move_To (Cr, Gdouble (I * Cell) + 0.5, 0.0);
         Line_To (Cr, Gdouble (I * Cell) + 0.5, Gdouble (8 * Cell));
         Move_To (Cr, 0.0, Gdouble (I * Cell) + 0.5);
         Line_To (Cr, Gdouble (8 * Cell), Gdouble (I * Cell) + 0.5);
      end loop;
      Stroke (Cr);
      return True;
   end On_Grid_Draw;

   function Per_Row return Natural is (if Mode = UDG_Mode then 11 else 16);

   function On_Overview_Draw (Self : access Gtk_Widget_Record'Class;
                              Cr : Cairo_Context) return Boolean is
      pragma Unreferenced (Self);
   begin
      Set_Colour (Cr, 7);
      Paint (Cr);
      for I in First_Glyph .. Last_Glyph loop
         declare
            N : constant Natural := I - First_Glyph;
            X0 : constant Gdouble := Gdouble ((N mod Per_Row) * OV);
            Y0 : constant Gdouble := Gdouble ((N / Per_Row) * OV);
         begin
            if I = Current then
               Set_Colour (Cr, 5);
               Rectangle (Cr, X0, Y0, Gdouble (OV), Gdouble (OV));
               Cairo.Fill (Cr);
            end if;
            Set_Colour (Cr, 0);
            Draw_Glyph (Cr, Glyphs (I), X0, Y0, 3.0);
         end;
      end loop;
      return True;
   end On_Overview_Draw;

   --  The sample text: \a .. \u are the UDGs
   function On_Text_Draw (Self : access Gtk_Widget_Record'Class;
                          Cr : Cairo_Context) return Boolean is
      pragma Unreferenced (Self);
      S : constant String := Sample.Get_Text;
      X : Gdouble := 4.0;
      I : Natural := S'First;
   begin
      Set_Colour (Cr, 15);
      Paint (Cr);
      Set_Colour (Cr, 1);
      while I <= S'Last and then X < 1200.0 loop
         declare
            G : Integer := -1;
         begin
            if S (I) = '\' and then I < S'Last and then S (I + 1) in 'a' .. 'u'
            then
               G := UDG_First + Character'Pos (S (I + 1)) - Character'Pos ('a');
               I := I + 2;
            else
               if Character'Pos (S (I)) in 32 .. 127 then
                  G := Character'Pos (S (I)) - 32;
               end if;
               I := I + 1;
            end if;
            if G >= 0 then
               Draw_Glyph (Cr, Glyphs (G), X, 8.0, 3.0);
               X := X + 24.0;
            end if;
         end;
      end loop;
      return True;
   end On_Text_Draw;

   ---------------------------------------------------------------------
   --  Editing
   ---------------------------------------------------------------------

   procedure Push_Undo is
   begin
      if Undo_Count = Max_Undo then
         Undo_Stack (1 .. Max_Undo - 1) := Undo_Stack (2 .. Max_Undo);
         Undo_Count := Max_Undo - 1;
      end if;
      Undo_Count := Undo_Count + 1;
      Undo_Stack (Undo_Count) := (Current, Glyphs (Current));
   end Push_Undo;

   procedure Undo is
   begin
      if Undo_Count > 0 then
         Current := Undo_Stack (Undo_Count).Index;
         Glyphs (Current) := Undo_Stack (Undo_Count).G;
         Undo_Count := Undo_Count - 1;
         if Current not in First_Glyph .. Last_Glyph then
            Mode := (if Current >= UDG_First then UDG_Mode else Font_Mode);
         end if;
         Changed_Glyph;
         Show_Status;
      end if;
   end Undo;

   procedure Flood (G : in out Glyph; X, Y : Integer; On : Boolean) is
   begin
      if X not in 0 .. 7 or else Y not in 0 .. 7
        or else Pixel (G, X, Y) = On
      then
         return;
      end if;
      Set_Pixel (G, X, Y, On);
      Flood (G, X + 1, Y, On);
      Flood (G, X - 1, Y, On);
      Flood (G, X, Y + 1, On);
      Flood (G, X, Y - 1, On);
   end Flood;

   procedure Paint_At (EX, EY : Gdouble; Fill_It : Boolean) is
      PX : constant Integer := Integer (Gdouble'Floor (EX / Gdouble (Cell)));
      PY : constant Integer := Integer (Gdouble'Floor (EY / Gdouble (Cell)));
      G : Glyph := Glyphs (Current);
   begin
      if PX not in 0 .. 7 or else PY not in 0 .. 7 then
         return;
      end if;
      if Fill_It then
         Flood (G, PX, PY, Paint_On);
      elsif Pixel (G, PX, PY) = Paint_On then
         return;
      else
         Set_Pixel (G, PX, PY, Paint_On);
      end if;
      Glyphs (Current) := G;
      Changed_Glyph;
   end Paint_At;

   function On_Grid_Press (Self : access Gtk_Widget_Record'Class;
                           Event : Gdk_Event_Button) return Boolean is
      pragma Unreferenced (Self);
   begin
      Push_Undo;
      Paint_On := Event.Button /= 3;
      Painting := True;
      Paint_At (Event.X, Event.Y, (Event.State and Shift_Mask) /= 0);
      return True;
   end On_Grid_Press;

   function On_Grid_Release (Self : access Gtk_Widget_Record'Class;
                             Event : Gdk_Event_Button) return Boolean is
      pragma Unreferenced (Self, Event);
   begin
      Painting := False;
      return True;
   end On_Grid_Release;

   function On_Grid_Motion (Self : access Gtk_Widget_Record'Class;
                            Event : Gdk_Event_Motion) return Boolean is
      pragma Unreferenced (Self);
   begin
      if Painting then
         Paint_At (Event.X, Event.Y, False);
      end if;
      return True;
   end On_Grid_Motion;

   function On_Overview_Press (Self : access Gtk_Widget_Record'Class;
                               Event : Gdk_Event_Button) return Boolean is
      pragma Unreferenced (Self);
      CX : constant Integer := Integer (Gdouble'Floor (Event.X / Gdouble (OV)));
      CY : constant Integer := Integer (Gdouble'Floor (Event.Y / Gdouble (OV)));
      N : constant Integer := CY * Per_Row + CX;
   begin
      if CX in 0 .. Per_Row - 1 and then N >= 0
        and then First_Glyph + N <= Last_Glyph
      then
         Current := First_Glyph + N;
         Show_Status;
         Redraw_All;
      end if;
      return True;
   end On_Overview_Press;

   procedure Transform (Kind : Character) is
      G : constant Glyph := Glyphs (Current);
      R : Glyph := (others => 0);
   begin
      Push_Undo;
      for Y in 0 .. 7 loop
         for X in 0 .. 7 loop
            declare
               SX, SY : Natural;
               On : Boolean;
            begin
               case Kind is
                  when 'H' => SX := 7 - X; SY := Y;
                  when 'V' => SX := X; SY := 7 - Y;
                  when 'R' => SX := Y; SY := 7 - X;   --  clockwise
                  when '<' => SX := (X + 1) mod 8; SY := Y;
                  when '>' => SX := (X + 7) mod 8; SY := Y;
                  when '^' => SX := X; SY := (Y + 1) mod 8;
                  when 'v' => SX := X; SY := (Y + 7) mod 8;
                  when others => SX := X; SY := Y;
               end case;
               On := Pixel (G, SX, SY);
               if Kind = 'I' then
                  On := not On;
               elsif Kind = 'C' then
                  On := False;
               end if;
               Set_Pixel (R, X, Y, On);
            end;
         end loop;
      end loop;
      Glyphs (Current) := R;
      Changed_Glyph;
   end Transform;

   ---------------------------------------------------------------------
   --  Files
   ---------------------------------------------------------------------

   procedure Load_File (Path : String) is
      Ok : Boolean;
      D : constant Byte_Array := Read_Bytes (Path, Ok);
   begin
      if not Ok then
         Message (Win, "Cannot read " & Path);
         return;
      end if;
      if D'Length = 768 then
         Mode := Font_Mode;
         for I in 0 .. 95 loop
            for Y in 0 .. 7 loop
               Glyphs (I) (Y) := D (D'First + I * 8 + Y);
            end loop;
         end loop;
      else
         Mode := UDG_Mode;
         for I in 0 .. 20 loop
            for Y in 0 .. 7 loop
               if D'First + I * 8 + Y <= D'Last then
                  Glyphs (UDG_First + I) (Y) := D (D'First + I * 8 + Y);
               end if;
            end loop;
         end loop;
      end if;
      Current := First_Glyph;
      File := To_Unbounded_String (Path);
      Settings.Set ("udg_file", Path);
      Undo_Count := 0;
      Show_Status;
      Redraw_All;
   end Load_File;

   procedure Save_File (Ask : Boolean) is
      Ok : Boolean;
   begin
      if Ask or else File = Null_Unbounded_String then
         declare
            P : constant String := Choose_File
              (Win, "Save " & (if Mode = UDG_Mode then "UDGs" else "font"),
               True, "UDG / font files (.udg)", "*.udg",
               (if Mode = UDG_Mode then "graphics.udg" else "font.udg"));
         begin
            if P = "" then
               return;
            end if;
            File := To_Unbounded_String (P);
         end;
      end if;
      declare
         N : constant Natural := Last_Glyph - First_Glyph + 1;
         D : Byte_Array (0 .. N * 8 - 1);
      begin
         for I in 0 .. N - 1 loop
            for Y in 0 .. 7 loop
               D (I * 8 + Y) := Glyphs (First_Glyph + I) (Y);
            end loop;
         end loop;
         Write_Bytes (To_String (File), D, Ok);
      end;
      if Ok then
         Settings.Set ("udg_file", To_String (File));
         Show_Status;
      else
         Message (Win, "Cannot write " & To_String (File));
      end if;
   end Save_File;

   function Base_Of (Ext : String) return String is
      F : constant String :=
        (if File = Null_Unbounded_String then "graphics" else To_String (File));
   begin
      return (if Ada.Directories.Extension (F) = "" then F
              else F (F'First .. F'Last - Ada.Directories.Extension (F)'Length
                      - 1)) & Ext;
   end Base_Of;

   function Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (N'Image, Ada.Strings.Left));

   procedure Export_BASIC is
      R : Unbounded_String;
      Line : Natural := 9000;
      Ok : Boolean;
   begin
      if Mode = UDG_Mode then
         Append (R, Img (Line) & " RESTORE" & Natural'Image (Line + 10) &
                   ": FOR i=0 TO 167: READ a: POKE USR ""a""+i,a: NEXT i"
                   & ASCII.LF);
      else
         Append (R, Img (Line) & " CLEAR 64599: RESTORE" &
                   Natural'Image (Line + 10) &
                   ": FOR i=0 TO 767: READ a: POKE 64600+i,a: NEXT i:" &
                   " POKE 23606,88: POKE 23607,251" & ASCII.LF);
      end if;
      for I in First_Glyph .. Last_Glyph loop
         Line := Line + 10;
         Append (R, Img (Line) & " DATA ");
         for Y in 0 .. 7 loop
            Append (R, Img (Integer (Glyphs (I) (Y))) &
                      (if Y < 7 then "," else ""));
         end loop;
         Append (R, ASCII.LF);
      end loop;
      Write_Text (Base_Of ("_udg.bas"), To_String (R), Ok);
      Status.Set_Text (if Ok then "wrote " & Base_Of ("_udg.bas")
                       else "cannot write " & Base_Of ("_udg.bas"));
   end Export_BASIC;

   procedure Export_Asm is
      R : Unbounded_String;
      Ok : Boolean;
   begin
      Append (R, "; " & (if Mode = UDG_Mode then "UDGs A-U"
                         else "font, characters 32-127 (CHARS = label-256)")
              & ASCII.LF);
      Append (R, (if Mode = UDG_Mode then "udg_data:" else "font_data:")
              & ASCII.LF);
      for I in First_Glyph .. Last_Glyph loop
         Append (R, "            db ");
         for Y in 0 .. 7 loop
            declare
               B : constant Byte := Glyphs (I) (Y);
               Bits : String (1 .. 8);
            begin
               for K in 0 .. 7 loop
                  Bits (K + 1) := (if (B and Shift_Right (Byte'(16#80#), K))
                                   /= 0 then '1' else '0');
               end loop;
               Append (R, "%" & Bits & (if Y < 7 then "," else ""));
            end;
         end loop;
         Append (R, "   ; " & Glyph_Name (I) & ASCII.LF);
      end loop;
      Write_Text (Base_Of ("_udg.asm"), To_String (R), Ok);
      Status.Set_Text (if Ok then "wrote " & Base_Of ("_udg.asm")
                       else "cannot write " & Base_Of ("_udg.asm"));
   end Export_Asm;

   ---------------------------------------------------------------------
   --  Actions and window
   ---------------------------------------------------------------------

   type Action is (A_New, A_Open, A_Save, A_Save_As, A_Export_BASIC,
                   A_Export_Asm, A_UDGs, A_Font,
                   A_Copy, A_Paste, A_Undo, A_Clear, A_Invert, A_Mirror_X,
                   A_Mirror_Y, A_Rotate, A_Left, A_Right, A_Up, A_Down,
                   A_From_ROM, A_Show, A_Grab);
   Tool_Items : array (Action) of Gtk_Tool_Button;

   procedure Do_Action (A : Action) is
   begin
      case A is
         when A_New =>
            Load_ROM;
            File := Null_Unbounded_String;
            Undo_Count := 0;
         when A_Open =>
            declare
               P : constant String := Choose_File
                 (Win, "Open UDGs / font", False, "UDG / font files (.udg)",
                  "*.udg");
            begin
               if P /= "" then
                  Load_File (P);
               end if;
            end;
         when A_Save => Save_File (False);
         when A_Save_As => Save_File (True);
         when A_Export_BASIC => Export_BASIC;
         when A_Export_Asm => Export_Asm;
         when A_UDGs =>
            Mode := UDG_Mode;
            Current := UDG_First;
         when A_Font =>
            Mode := Font_Mode;
            Current := Character'Pos ('A') - 32;
         when A_Copy => Clip := Glyphs (Current);
         when A_Paste =>
            Push_Undo;
            Glyphs (Current) := Clip;
            Changed_Glyph;
         when A_Undo => Undo;
         when A_Clear => Transform ('C');
         when A_Invert => Transform ('I');
         when A_Mirror_X => Transform ('H');
         when A_Mirror_Y => Transform ('V');
         when A_Rotate => Transform ('R');
         when A_Left => Transform ('<');
         when A_Right => Transform ('>');
         when A_Up => Transform ('^');
         when A_Down => Transform ('v');
         when A_From_ROM =>
            Push_Undo;
            Glyphs (Current) := ROM_Glyph (Current);
            Changed_Glyph;
         when A_Show => Send;
         when A_Grab => Grab;
      end case;
      if A not in A_Show | A_Grab | A_Export_BASIC | A_Export_Asm then
         Show_Status;
      end if;
      Redraw_All;
   end Do_Action;

   procedure On_Tool (Item : access Gtk_Tool_Button_Record'Class) is
   begin
      for A in Action loop
         if Tool_Items (A) = Gtk_Tool_Button (Item) then
            Do_Action (A);
         end if;
      end loop;
   end On_Tool;

   procedure On_Live (Self : access Gtk_Toggle_Button_Record'Class) is
   begin
      if Self.Get_Active then
         Send;
      end if;
   end On_Live;

   function On_Sample (Self : access Gtk_Widget_Record'Class;
                       Event : Gdk_Event_Key) return Boolean is
      pragma Unreferenced (Self, Event);
   begin
      Text_Area.Queue_Draw;
      return False;
   end On_Sample;

   function On_Key (Self : access Gtk_Widget_Record'Class;
                    Event : Gdk_Event_Key) return Boolean is
      pragma Unreferenced (Self);
      Ctrl : constant Boolean := (Event.State and Control_Mask) /= 0;
      procedure Move (D : Integer) is
         N : constant Integer := Current + D;
      begin
         if N in First_Glyph .. Last_Glyph then
            Current := N;
            Show_Status;
            Redraw_All;
         end if;
      end Move;
   begin
      if Sample.Has_Focus then
         return False;
      end if;
      if Ctrl and then Event.Keyval = GDK_LC_z then
         Undo;
      elsif Ctrl and then Event.Keyval = GDK_LC_s then
         Save_File (False);
      elsif Ctrl and then Event.Keyval = GDK_LC_c then
         Do_Action (A_Copy);
      elsif Ctrl and then Event.Keyval = GDK_LC_v then
         Do_Action (A_Paste);
      elsif Event.Keyval = GDK_Page_Down or else Event.Keyval = GDK_plus then
         Move (1);
      elsif Event.Keyval = GDK_Page_Up or else Event.Keyval = GDK_minus then
         Move (-1);
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
      VBox, HBox, Right : Gtk_Box;
      Tools : Gtk_Toolbar;
      Frame : Gtk_Frame;

      procedure Tool (Label : String; A : Action; Tip : String;
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
      end Tool;

      procedure Sep is
         S : Gtk_Separator_Tool_Item;
      begin
         Gtk_New (S);
         Tools.Insert (S);
      end Sep;

      function Area (W, H : Gint) return Gtk_Drawing_Area is
         A : Gtk_Drawing_Area;
      begin
         Gtk_New (A);
         A.Set_Size_Request (W, H);
         A.Add_Events (Button_Press_Mask or Button_Release_Mask
                       or Button_Motion_Mask);
         return A;
      end Area;
   begin
      Gtk_New (Win);
      Win.Set_Title ("UDG / character set editor");
      Win.Set_Default_Size (920, 600);
      Win.On_Delete_Event (On_Delete'Access);
      Win.On_Key_Press_Event (On_Key'Access);
      Gtk_New_Vbox (VBox);
      Win.Add (VBox);

      Gtk_New (Tools);
      Tools.Set_Style (Toolbar_Both_Horiz);
      Tool ("ROM font", A_New, "Start again from the ROM font",
            "document-new");
      Tool ("Open", A_Open, "Open a .udg file", "document-open");
      Tool ("Save", A_Save, "Save (Ctrl+S)", "document-save");
      Tool ("Save as", A_Save_As, "Save under a new name");
      Tool ("Export BASIC", A_Export_BASIC,
            "Write DATA lines and a POKE loop (name_udg.bas)");
      Tool ("Export .asm", A_Export_Asm, "Write db lines (name_udg.asm)");
      Sep;
      Tool ("UDGs A-U", A_UDGs, "Edit the 21 user-defined graphics");
      Tool ("Font 32-127", A_Font, "Edit the whole character set");
      VBox.Pack_Start (Tools, Expand => False, Fill => False);

      Gtk_New (Tools);
      Tools.Set_Style (Toolbar_Text);
      Tool ("Clear", A_Clear, "Clear the character");
      Tool ("Invert", A_Invert, "Invert");
      Tool ("Flip H", A_Mirror_X, "Mirror left-right");
      Tool ("Flip V", A_Mirror_Y, "Mirror top-bottom");
      Tool ("Rotate", A_Rotate, "Rotate 90 degrees clockwise");
      Tool ("<", A_Left, "Scroll left (wraps)");
      Tool (">", A_Right, "Scroll right (wraps)");
      Tool ("^", A_Up, "Scroll up (wraps)");
      Tool ("v", A_Down, "Scroll down (wraps)");
      Tool ("From ROM", A_From_ROM, "Restore the ROM's shape");
      Tool ("Copy", A_Copy, "Copy (Ctrl+C)");
      Tool ("Paste", A_Paste, "Paste (Ctrl+V)");
      Tool ("Undo", A_Undo, "Undo (Ctrl+Z)");
      Sep;
      Tool ("Show in emulator", A_Show,
            "Write the UDGs (or the font) into the running Spectrum");
      Tool ("Grab from emulator", A_Grab,
            "Copy the UDGs (or the font) from the running Spectrum");
      VBox.Pack_Start (Tools, Expand => False, Fill => False);

      Gtk_New_Hbox (HBox, Spacing => 8);
      VBox.Pack_Start (HBox, Expand => True, Fill => True);

      Grid := Area (8 * Cell + 1, 8 * Cell + 1);
      Grid.On_Draw (On_Grid_Draw'Access);
      Grid.On_Button_Press_Event (On_Grid_Press'Access);
      Grid.On_Button_Release_Event (On_Grid_Release'Access);
      Grid.On_Motion_Notify_Event (On_Grid_Motion'Access);
      Gtk_New (Frame, "Character (left: draw, right: erase, shift: fill)");
      Frame.Add (Grid);
      Frame.Set_Valign (Align_Start);
      HBox.Pack_Start (Frame, Expand => False, Fill => False, Padding => 6);

      Gtk_New_Vbox (Right, Spacing => 6);
      HBox.Pack_Start (Right, Expand => True, Fill => True);

      Overview := Area (16 * OV, 6 * OV);
      Overview.On_Draw (On_Overview_Draw'Access);
      Overview.On_Button_Press_Event (On_Overview_Press'Access);
      Gtk_New (Frame, "Characters (click to edit, PgUp / PgDn)");
      Frame.Add (Overview);
      Right.Pack_Start (Frame, Expand => False, Fill => False);

      Gtk_New (Sample);
      Sample.Set_Text ("Hello \a\b\c AdaZX");
      Sample.Set_Tooltip_Text ("Sample text; \a .. \u are the UDGs");
      Sample.On_Key_Release_Event (On_Sample'Access);
      Right.Pack_Start (Sample, Expand => False, Fill => False);
      Text_Area := Area (400, 40);
      Text_Area.On_Draw (On_Text_Draw'Access);
      Right.Pack_Start (Text_Area, Expand => False, Fill => False);

      Gtk_New (Live, "Live in emulator (every change goes to the Spectrum)");
      Live.On_Toggled (On_Live'Access);
      Right.Pack_Start (Live, Expand => False, Fill => False);

      Gtk_New (Status, "");
      Status.Set_Halign (Align_Start);
      Status.Set_Selectable (True);
      VBox.Pack_Start (Status, Expand => False, Fill => False, Padding => 4);
   end Build;

   procedure Open (Parent : Gtk.Window.Gtk_Window; Path : String := "") is
      pragma Unreferenced (Parent);
   begin
      if Win = null then
         Build;
         Win.Show_All;
         Load_ROM;
         declare
            Last : constant String := Settings.Get ("udg_file", "");
         begin
            if Path = "" and then Last /= ""
              and then Ada.Directories.Exists (Last)
            then
               Load_File (Last);
            end if;
         end;
         Show_Status;
      end if;
      if Path /= "" then
         if Ada.Directories.Exists (Path) then
            Load_File (Ada.Directories.Full_Name (Path));
         else
            Load_ROM;
            File := To_Unbounded_String (Path);
         end if;
      end if;
      Redraw_All;
      Win.Show_All;
      Win.Present;
   end Open;

end UDG_Editor;
