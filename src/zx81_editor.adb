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

with File_Ext;
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
with Gtk.Drawing_Area; use Gtk.Drawing_Area;
with Gtk.Enums; use Gtk.Enums;
with Gtk.Frame; use Gtk.Frame;
with Gtk.Label; use Gtk.Label;
with Gtk.Radio_Button; use Gtk.Radio_Button;
with Gtk.Separator_Tool_Item; use Gtk.Separator_Tool_Item;
with Gtk.Tool_Button; use Gtk.Tool_Button;
with Gtk.Toggle_Button; use Gtk.Toggle_Button;
with Gtk.Toolbar; use Gtk.Toolbar;
with Gtk.Widget; use Gtk.Widget;
with Gtk.Window; use Gtk.Window;
with Cairo; use Cairo;

with Types; use Types;
with Machine;
with Basic;
with Settings;
with Video;
with Editor_Util; use Editor_Util;

package body ZX81_Editor is

   Z : constant := 3;               --  zoom
   CW : constant := 8 * Z;          --  character cell on screen
   PZ : constant := 2;              --  palette zoom
   PW : constant := 8 * PZ + 4;     --  palette cell

   type Screen is array (0 .. 23, 0 .. 31) of Byte;
   Scr : Screen := (others => (others => 0));

   Font : Byte_Array (0 .. 511) := (others => 0);   --  64 characters

   Win : Gtk_Window := null;
   Canvas, Palette : Gtk_Drawing_Area;
   Status : Gtk_Label;
   File : Unbounded_String;

   type Mode_Type is (Text_Mode, Paint_Mode, Plot_Mode);
   Mode : Mode_Type := Text_Mode;
   Mode_Buttons : array (Mode_Type) of Gtk_Radio_Button;

   Cur_X, Cur_Y : Natural := 0;
   Inverse : Boolean := False;
   Brush : Byte := 128;             --  inverse space: a black square
   Dragging : Boolean := False;
   Plot_On : Boolean := True;

   Max_Undo : constant := 32;
   Undo_Stack : array (1 .. Max_Undo) of Screen;
   Undo_Count : Natural := 0;

   function Is_ZX81_Screen_File (Path : String) return Boolean is
     (Ada.Characters.Handling.To_Lower (File_Ext.Of_Path (Path))
      = "z81s");

   procedure Load_Font is
      Ok : Boolean;
      Path : constant String := Machine.ROM_File ("zx81.rom");
   begin
      if Path = "" then
         return;
      end if;
      declare
         D : constant Byte_Array := Read_Bytes (Path, Ok);
      begin
         if Ok and then D'Length >= 16#2000# then
            Font := D (D'First + 16#1E00# .. D'First + 16#1FFF#);
         end if;
      end;
   end Load_Font;

   ---------------------------------------------------------------------
   --  Block graphics: quadrant bits 0 top left, 1 top right,
   --  2 bottom left, 3 bottom right
   ---------------------------------------------------------------------

   Block_Code : constant array (0 .. 15) of Byte :=
     (0, 1, 2, 3, 4, 5, 6, 7, 135, 134, 133, 132, 131, 130, 129, 128);

   function Quadrants (C : Byte; Ok : out Boolean) return Natural is
   begin
      for Q in Block_Code'Range loop
         if Block_Code (Q) = C then
            Ok := True;
            return Q;
         end if;
      end loop;
      Ok := False;
      return 0;
   end Quadrants;

   ---------------------------------------------------------------------
   --  Emulator link
   ---------------------------------------------------------------------

   function D_File return Word is (Machine.Peek_Word (16#400C#));

   function Expanded return Boolean is
      A : Word := D_File + 1;
   begin
      for Row in 0 .. 23 loop
         for K in 0 .. 31 loop
            if Machine.Peek (A + Word (K)) = 16#76# then
               return False;
            end if;
         end loop;
         if Machine.Peek (A + 32) /= 16#76# then
            return False;
         end if;
         A := A + 33;
      end loop;
      return True;
   end Expanded;

   procedure Send is
   begin
      if not Machine.Is_ZX81 then
         Status.Set_Text ("switch the emulator to the ZX81 first");
         return;
      elsif not Expanded then
         Status.Set_Text ("the display file is collapsed (1K ZX81, or the " &
                          "screen was not cleared since NEW): CLS on a 16K " &
                          "ZX81 expands it");
         return;
      end if;
      for Row in 0 .. 23 loop
         for Col in 0 .. 31 loop
            Machine.Poke (D_File + 1 + Word (Row * 33 + Col), Scr (Row, Col));
         end loop;
      end loop;
      Status.Set_Text ("written to the display file at $" &
                       Hex4 (Natural (D_File)));
   end Send;

   procedure Grab is
      A : Word := D_File + 1;
   begin
      if not Machine.Is_ZX81 then
         Status.Set_Text ("switch the emulator to the ZX81 first");
         return;
      end if;
      Scr := (others => (others => 0));
      for Row in 0 .. 23 loop
         for Col in 0 .. 32 loop
            declare
               C : constant Byte := Machine.Peek (A);
            begin
               A := A + 1;
               exit when C = 16#76#;
               if Col <= 31 then
                  Scr (Row, Col) := C;
               end if;
            end;
         end loop;
      end loop;
      Status.Set_Text ("copied the display file");
   end Grab;

   ---------------------------------------------------------------------
   --  Drawing
   ---------------------------------------------------------------------

   procedure Draw_Char (Cr : Cairo_Context; C : Byte; X0, Y0 : Gdouble;
                        Scale : Gdouble) is
      Inv : constant Boolean := C >= 128;
      Base : constant Natural := Natural (C and 16#3F#) * 8;
   begin
      Set_RGB (Cr, (if Inv then Video.ZX81_Ink else Video.ZX81_Paper));
      Rectangle (Cr, X0, Y0, 8.0 * Scale, 8.0 * Scale);
      Cairo.Fill (Cr);
      Set_RGB (Cr, (if Inv then Video.ZX81_Paper else Video.ZX81_Ink));
      for Y in 0 .. 7 loop
         for X in 0 .. 7 loop
            if (Font (Base + Y) and Shift_Right (Byte'(16#80#), X)) /= 0 then
               Rectangle (Cr, X0 + Gdouble (X) * Scale,
                          Y0 + Gdouble (Y) * Scale, Scale, Scale);
            end if;
         end loop;
      end loop;
      Cairo.Fill (Cr);
   end Draw_Char;

   function On_Canvas_Draw (Self : access Gtk_Widget_Record'Class;
                            Cr : Cairo_Context) return Boolean is
      pragma Unreferenced (Self);
   begin
      for Row in 0 .. 23 loop
         for Col in 0 .. 31 loop
            Draw_Char (Cr, Scr (Row, Col), Gdouble (Col * CW),
                       Gdouble (Row * CW), Gdouble (Z));
         end loop;
      end loop;
      if Mode = Text_Mode then
         Set_Source_Rgb (Cr, 1.0, 0.2, 0.2);
         Set_Line_Width (Cr, 2.0);
         Rectangle (Cr, Gdouble (Cur_X * CW) + 1.0, Gdouble (Cur_Y * CW) + 1.0,
                    Gdouble (CW - 2), Gdouble (CW - 2));
         Stroke (Cr);
      end if;
      return True;
   end On_Canvas_Draw;

   function On_Palette_Draw (Self : access Gtk_Widget_Record'Class;
                             Cr : Cairo_Context) return Boolean is
      pragma Unreferenced (Self);
   begin
      Set_Source_Rgb (Cr, 0.8, 0.8, 0.8);
      Paint (Cr);
      for K in 0 .. 127 loop
         declare
            C : constant Byte := (if K < 64 then Byte (K) else Byte (K + 64));
            X0 : constant Gdouble := Gdouble ((K mod 16) * PW + 2);
            Y0 : constant Gdouble := Gdouble ((K / 16) * PW + 2);
         begin
            if C = Brush then
               Set_Source_Rgb (Cr, 1.0, 0.2, 0.2);
               Rectangle (Cr, X0 - 2.0, Y0 - 2.0, Gdouble (PW), Gdouble (PW));
               Cairo.Fill (Cr);
            end if;
            Draw_Char (Cr, C, X0, Y0, Gdouble (PZ));
         end;
      end loop;
      return True;
   end On_Palette_Draw;

   procedure Show_Status is
   begin
      Status.Set_Text
        ("row" & Cur_Y'Image & " column" & Cur_X'Image &
         (if Inverse then "  INVERSE" else "") &
         "   brush: " & (if Brush >= 128 then "inverse " else "") &
         Basic.From_ZX81 (Brush) & "   " &
         (if File = Null_Unbounded_String then "(not saved)"
          else To_String (File)));
   end Show_Status;

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
         Canvas.Queue_Draw;
      end if;
   end Undo;

   ---------------------------------------------------------------------
   --  Mouse and keys
   ---------------------------------------------------------------------

   procedure Act_At (EX, EY : Gdouble) is
      X : constant Integer := Integer (Gdouble'Floor (EX / Gdouble (CW)));
      Y : constant Integer := Integer (Gdouble'Floor (EY / Gdouble (CW)));
   begin
      if X not in 0 .. 31 or else Y not in 0 .. 23 then
         return;
      end if;
      case Mode is
         when Text_Mode =>
            Cur_X := X;
            Cur_Y := Y;
         when Paint_Mode =>
            Scr (Y, X) := Brush;
         when Plot_Mode =>
            declare
               QX : constant Natural :=
                 Natural (Gdouble'Floor (EX / Gdouble (CW / 2))) mod 2;
               QY : constant Natural :=
                 Natural (Gdouble'Floor (EY / Gdouble (CW / 2))) mod 2;
               Bit : constant Natural := 2 ** (QY * 2 + QX);
               Ok : Boolean;
               Q : Natural := Quadrants (Scr (Y, X), Ok);
            begin
               if not Ok then
                  Q := 0;
               end if;
               if Plot_On then
                  Q := Natural (Unsigned_8 (Q) or Unsigned_8 (Bit));
               else
                  Q := Natural (Unsigned_8 (Q) and not Unsigned_8 (Bit));
               end if;
               Scr (Y, X) := Block_Code (Q);
            end;
      end case;
      Canvas.Queue_Draw;
      Show_Status;
   end Act_At;

   function On_Press (Self : access Gtk_Widget_Record'Class;
                      Event : Gdk_Event_Button) return Boolean is
      pragma Unreferenced (Self);
   begin
      Push_Undo;
      Plot_On := Event.Button /= 3;
      Dragging := True;
      Canvas.Grab_Focus;
      Act_At (Event.X, Event.Y);
      return True;
   end On_Press;

   function On_Motion (Self : access Gtk_Widget_Record'Class;
                       Event : Gdk_Event_Motion) return Boolean is
      pragma Unreferenced (Self);
   begin
      if Dragging and then Mode /= Text_Mode then
         Act_At (Event.X, Event.Y);
      end if;
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
      X : constant Integer := Integer (Gdouble'Floor (Event.X / Gdouble (PW)));
      Y : constant Integer := Integer (Gdouble'Floor (Event.Y / Gdouble (PW)));
      K : constant Integer := Y * 16 + X;
   begin
      if X in 0 .. 15 and then K in 0 .. 127 then
         Brush := (if K < 64 then Byte (K) else Byte (K + 64));
         Mode := Paint_Mode;
         Mode_Buttons (Paint_Mode).Set_Active (True);
         Palette.Queue_Draw;
         Show_Status;
      end if;
      return True;
   end On_Palette_Press;

   procedure Advance is
   begin
      if Cur_X < 31 then
         Cur_X := Cur_X + 1;
      elsif Cur_Y < 23 then
         Cur_X := 0;
         Cur_Y := Cur_Y + 1;
      end if;
   end Advance;

   function On_Key (Self : access Gtk_Widget_Record'Class;
                    Event : Gdk_Event_Key) return Boolean is
      pragma Unreferenced (Self);
      Ctrl : constant Boolean := (Event.State and Control_Mask) /= 0;
      KV : constant Gdk_Key_Type := Event.Keyval;
   begin
      if Ctrl and then KV = GDK_LC_z then
         Undo;
      elsif Ctrl and then KV = GDK_LC_i then
         Inverse := not Inverse;
      elsif Mode /= Text_Mode then
         return False;
      elsif KV = GDK_Left and then Cur_X > 0 then
         Cur_X := Cur_X - 1;
      elsif KV = GDK_Right and then Cur_X < 31 then
         Cur_X := Cur_X + 1;
      elsif KV = GDK_Up and then Cur_Y > 0 then
         Cur_Y := Cur_Y - 1;
      elsif KV = GDK_Down and then Cur_Y < 23 then
         Cur_Y := Cur_Y + 1;
      elsif KV = GDK_Return then
         Cur_X := 0;
         if Cur_Y < 23 then
            Cur_Y := Cur_Y + 1;
         end if;
      elsif KV = GDK_BackSpace then
         if Cur_X > 0 then
            Cur_X := Cur_X - 1;
         end if;
         Push_Undo;
         Scr (Cur_Y, Cur_X) := 0;
      elsif KV in 32 .. 126 and then not Ctrl then
         Push_Undo;
         Scr (Cur_Y, Cur_X) := Basic.To_ZX81 (Character'Val (KV))
           or (if Inverse then 16#80# else 0);
         Advance;
      else
         return False;
      end if;
      Canvas.Queue_Draw;
      Show_Status;
      return True;
   end On_Key;

   ---------------------------------------------------------------------
   --  Files
   ---------------------------------------------------------------------

   procedure Load_File (Path : String) is
      Ok : Boolean;
      D : constant Byte_Array := Read_Bytes (Path, Ok);
   begin
      if not Ok or else D'Length < 768 then
         Message (Win, "Not a ZX81 screen file: " & Path);
         return;
      end if;
      Push_Undo;
      for Row in 0 .. 23 loop
         for Col in 0 .. 31 loop
            Scr (Row, Col) := D (D'First + Row * 32 + Col);
         end loop;
      end loop;
      File := To_Unbounded_String (Path);
      Settings.Set ("z81s_file", Path);
      Canvas.Queue_Draw;
      Show_Status;
   end Load_File;

   procedure Save_File (Ask : Boolean) is
      Ok : Boolean;
      D : Byte_Array (0 .. 767);
   begin
      if Ask or else File = Null_Unbounded_String then
         declare
            P : constant String := Choose_File
              (Win, "Save ZX81 screen", True, "ZX81 screens (.z81s)",
               "*.z81s", "screen.z81s");
         begin
            if P = "" then
               return;
            end if;
            File := To_Unbounded_String (P);
         end;
      end if;
      for Row in 0 .. 23 loop
         for Col in 0 .. 31 loop
            D (Row * 32 + Col) := Scr (Row, Col);
         end loop;
      end loop;
      Write_Bytes (To_String (File), D, Ok);
      if Ok then
         Settings.Set ("z81s_file", To_String (File));
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

   function Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (N'Image, Ada.Strings.Left));

   --  One character as BASIC source text (escapes as in src/basic.ads)
   function Source_Char (C : Byte) return String is
      Ok : Boolean;
      Q : constant Natural := Quadrants (C, Ok);
      Quad : constant String := " '.:";
   begin
      if Ok and then C /= 0 then
         declare
            L : constant Natural :=
              (if Q mod 2 = 1 then 1 else 0) + (if Q / 4 mod 2 = 1 then 2 else 0);
            R : constant Natural :=
              (if Q / 2 mod 2 = 1 then 1 else 0) + (if Q / 8 mod 2 = 1 then 2 else 0);
         begin
            return "\" & Quad (L + 1) & Quad (R + 1);
         end;
      elsif (C and 16#7F#) in 8 .. 10 or else C = 11 or else C = 139 then
         return "\{" & Img (Integer (C)) & "}";
      elsif C >= 128 then
         return "%" & Basic.From_ZX81 (C);
      end if;
      return (1 => Basic.From_ZX81 (C));
   end Source_Char;

   procedure Export_BASIC is
      R : Unbounded_String;
      Ok : Boolean;
      Line : Natural := 1000;
   begin
      for Row in 0 .. 21 loop
         declare
            Last : Integer := -1;
         begin
            for Col in 0 .. 31 loop
               if Scr (Row, Col) /= 0 then
                  Last := Col;
               end if;
            end loop;
            if Last >= 0 then
               Append (R, Img (Line) & " PRINT AT " & Img (Row) & ",0;""");
               for Col in 0 .. Last loop
                  Append (R, Source_Char (Scr (Row, Col)));
               end loop;
               Append (R, """" & ASCII.LF);
               Line := Line + 10;
            end if;
         end;
      end loop;
      Write_Text (Base_Of ("_screen.b81"), To_String (R), Ok);
      Status.Set_Text (if Ok then "wrote " & Base_Of ("_screen.b81") &
                         " (rows 0-21: PRINT cannot reach the last two)"
                       else "cannot write " & Base_Of ("_screen.b81"));
   end Export_BASIC;

   procedure Export_Asm is
      R : Unbounded_String;
      Ok : Boolean;
   begin
      Append (R, "; ZX81 screen laid out like the expanded display file"
              & ASCII.LF & "dfile:      db $76" & ASCII.LF);
      for Row in 0 .. 23 loop
         Append (R, "            db ");
         for Col in 0 .. 31 loop
            Append (R, "$" & Hex2 (Natural (Scr (Row, Col))) & ",");
         end loop;
         Append (R, "$76" & ASCII.LF);
      end loop;
      Write_Text (Base_Of ("_screen.asm"), To_String (R), Ok);
      Status.Set_Text (if Ok then "wrote " & Base_Of ("_screen.asm")
                       else "cannot write " & Base_Of ("_screen.asm"));
   end Export_Asm;

   ---------------------------------------------------------------------
   --  Actions and window
   ---------------------------------------------------------------------

   type Action is (A_New, A_Open, A_Save, A_Save_As, A_Export_BASIC,
                   A_Export_Asm, A_Undo, A_Inverse, A_Show, A_Grab);
   Tool_Items : array (Action) of Gtk_Tool_Button;

   procedure Do_Action (A : Action) is
   begin
      case A is
         when A_New =>
            Push_Undo;
            Scr := (others => (others => 0));
            File := Null_Unbounded_String;
         when A_Open =>
            declare
               P : constant String := Choose_File
                 (Win, "Open ZX81 screen", False, "ZX81 screens (.z81s)",
                  "*.z81s");
            begin
               if P /= "" then
                  Load_File (P);
               end if;
            end;
         when A_Save => Save_File (False);
         when A_Save_As => Save_File (True);
         when A_Export_BASIC => Export_BASIC;
         when A_Export_Asm => Export_Asm;
         when A_Undo => Undo;
         when A_Inverse =>
            Push_Undo;
            for Row in 0 .. 23 loop
               for Col in 0 .. 31 loop
                  Scr (Row, Col) := Scr (Row, Col) xor 16#80#;
               end loop;
            end loop;
         when A_Show => Send;
         when A_Grab =>
            Push_Undo;
            Grab;
      end case;
      Canvas.Queue_Draw;
      if A not in A_Show | A_Grab | A_Export_BASIC | A_Export_Asm then
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

   procedure On_Mode (Self : access Gtk_Toggle_Button_Record'Class) is
   begin
      for M in Mode_Type loop
         if Mode_Buttons (M) = Gtk_Radio_Button (Self) and then Self.Get_Active
         then
            Mode := M;
         end if;
      end loop;
      Canvas.Queue_Draw;
   end On_Mode;

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
      Group : Widget_SList.GSlist := Widget_SList.Null_List;
      Names : constant array (Mode_Type) of Unbounded_String :=
        (To_Unbounded_String ("Type text (Ctrl+I: inverse)"),
         To_Unbounded_String ("Paint the palette character"),
         To_Unbounded_String ("Plot block graphics (64 x 48)"));

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
   begin
      Gtk_New (Win);
      Win.Set_Title ("ZX81 screen editor");
      Win.Set_Default_Size (1160, 640);
      Win.On_Delete_Event (On_Delete'Access);
      Win.On_Key_Press_Event (On_Key'Access);
      Gtk_New_Vbox (VBox);
      Win.Add (VBox);

      Gtk_New (Tools);
      Tools.Set_Style (Toolbar_Both_Horiz);
      Tool ("New", A_New, "Clear the screen", "document-new");
      Tool ("Open", A_Open, "Open a .z81s file", "document-open");
      Tool ("Save", A_Save, "Save as .z81s", "document-save");
      Tool ("Save as", A_Save_As, "Save under a new name");
      Tool ("Export BASIC", A_Export_BASIC, "PRINT AT lines (.b81)");
      Tool ("Export .asm", A_Export_Asm, "db lines like the display file");
      Tool ("Undo", A_Undo, "Undo (Ctrl+Z)", "edit-undo");
      Tool ("Invert all", A_Inverse, "Inverse video everywhere");
      Sep;
      Tool ("Show in emulator", A_Show, "Write into the ZX81's display file");
      Tool ("Grab from emulator", A_Grab, "Copy the ZX81's display file");
      VBox.Pack_Start (Tools, Expand => False, Fill => False);

      Gtk_New_Hbox (HBox, Spacing => 8);
      VBox.Pack_Start (HBox, Expand => True, Fill => True);

      Gtk_New (Canvas);
      Canvas.Set_Size_Request (32 * CW, 24 * CW);
      Canvas.Set_Can_Focus (True);
      Canvas.Add_Events (Button_Press_Mask or Button_Release_Mask
                         or Button_Motion_Mask);
      Canvas.On_Draw (On_Canvas_Draw'Access);
      Canvas.On_Button_Press_Event (On_Press'Access);
      Canvas.On_Button_Release_Event (On_Release'Access);
      Canvas.On_Motion_Notify_Event (On_Motion'Access);
      Gtk_New (Frame, "Screen");
      Frame.Add (Canvas);
      Frame.Set_Valign (Align_Start);
      HBox.Pack_Start (Frame, Expand => False, Fill => False, Padding => 4);

      Gtk_New_Vbox (Side, Spacing => 4);
      HBox.Pack_Start (Side, Expand => True, Fill => True, Padding => 4);
      for M in Mode_Type loop
         Gtk_New (Mode_Buttons (M), Group, To_String (Names (M)));
         Group := Mode_Buttons (M).Get_Group;
         Mode_Buttons (M).On_Toggled (On_Mode'Access);
         Side.Pack_Start (Mode_Buttons (M), Expand => False, Fill => False);
      end loop;
      Gtk_New (Palette);
      Palette.Set_Size_Request (16 * PW + 4, 8 * PW + 4);
      Palette.Add_Events (Button_Press_Mask);
      Palette.On_Draw (On_Palette_Draw'Access);
      Palette.On_Button_Press_Event (On_Palette_Press'Access);
      Gtk_New (Frame, "Characters (click: paint with it)");
      Frame.Add (Palette);
      Side.Pack_Start (Frame, Expand => False, Fill => False, Padding => 6);

      Gtk_New (Status, "");
      Status.Set_Halign (Align_Start);
      Status.Set_Selectable (True);
      VBox.Pack_Start (Status, Expand => False, Fill => False, Padding => 4);
   end Build;

   procedure Open (Parent : Gtk.Window.Gtk_Window; Path : String := "") is
      pragma Unreferenced (Parent);
   begin
      if Win = null then
         Load_Font;
         Build;
         Win.Show_All;
         declare
            Last : constant String := Settings.Get ("z81s_file", "");
         begin
            if Path = "" and then Last /= ""
              and then Ada.Directories.Exists (Last)
            then
               Load_File (Last);
               Undo_Count := 0;
            end if;
         end;
         Show_Status;
      end if;
      if Path /= "" then
         if Ada.Directories.Exists (Path) then
            Load_File (Ada.Directories.Full_Name (Path));
         else
            File := To_Unbounded_String (Path);
         end if;
      end if;
      Canvas.Queue_Draw;
      Win.Show_All;
      Win.Present;
      Canvas.Grab_Focus;
   end Open;

end ZX81_Editor;
