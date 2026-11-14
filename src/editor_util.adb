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
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Interfaces; use Interfaces;
with Glib; use Glib;
with Gtk.Dialog; use Gtk.Dialog;
with Gtk.File_Chooser;
with Gtk.File_Chooser_Dialog; use Gtk.File_Chooser_Dialog;
with Gtk.File_Filter; use Gtk.File_Filter;
with Gtk.Message_Dialog; use Gtk.Message_Dialog;
with Gtk.Widget;
with Video;
with Settings;

package body Editor_Util is

   function Choose_File (Parent : Gtk.Window.Gtk_Window; Title : String;
                         Save : Boolean; Kind, Pattern : String;
                         Default_Name : String := "") return String is
      Dlg : Gtk_File_Chooser_Dialog;
      Filter, All_F : Gtk_File_Filter;
      W : Gtk.Widget.Gtk_Widget;
      pragma Unreferenced (W);
      Result : Unbounded_String;
      Last : constant String := Settings.Get ("forge_dir", "");
   begin
      Gtk_New (Dlg, Title, Parent,
               (if Save then Gtk.File_Chooser.Action_Save
                else Gtk.File_Chooser.Action_Open));
      W := Dlg.Add_Button ("_Cancel", Gtk_Response_Cancel);
      W := Dlg.Add_Button ((if Save then "_Save" else "_Open"),
                           Gtk_Response_Accept);
      Gtk_New (Filter);
      Filter.Set_Name (Kind);
      Filter.Add_Pattern (Pattern);
      Filter.Add_Pattern (Ada.Characters.Handling.To_Upper (Pattern));
      Gtk_New (All_F);
      All_F.Set_Name ("All files");
      All_F.Add_Pattern ("*");
      Gtk.File_Chooser.Add_Filter (+Dlg, Filter);
      Gtk.File_Chooser.Add_Filter (+Dlg, All_F);
      if Save then
         Gtk.File_Chooser.Set_Do_Overwrite_Confirmation (+Dlg, True);
         if Default_Name /= "" then
            Gtk.File_Chooser.Set_Current_Name (+Dlg, Default_Name);
         end if;
      end if;
      if Last /= "" then
         declare
            Ok : constant Boolean :=
              Gtk.File_Chooser.Set_Current_Folder (+Dlg, Last);
            pragma Unreferenced (Ok);
         begin
            null;
         end;
      end if;
      if Dlg.Run = Gtk_Response_Accept then
         Result := To_Unbounded_String
           (Gtk.File_Chooser.Get_Filename (+Dlg));
         begin
            Settings.Set ("forge_dir", Ada.Directories.Containing_Directory
                            (To_String (Result)));
         exception
            when others => null;
         end;
      end if;
      Dlg.Destroy;
      return To_String (Result);
   end Choose_File;

   procedure Message (Parent : Gtk.Window.Gtk_Window; Text : String) is
      Dlg : Gtk_Message_Dialog;
      R : Gtk_Response_Type;
      pragma Unreferenced (R);
   begin
      Gtk_New (Dlg, Parent, Modal, Message_Info, Buttons_Ok, Text);
      R := Dlg.Run;
      Dlg.Destroy;
   end Message;

   procedure Set_RGB (Cr : Cairo.Cairo_Context; P : Pixel) is
   begin
      Cairo.Set_Source_Rgb
        (Cr, Gdouble (Shift_Right (P, 16) and 255) / 255.0,
         Gdouble (Shift_Right (P, 8) and 255) / 255.0,
         Gdouble (P and 255) / 255.0);
   end Set_RGB;

   procedure Set_Colour (Cr : Cairo.Cairo_Context; Physical : Byte) is
   begin
      Set_RGB (Cr, Video.Colours (Natural (Physical) mod 16));
   end Set_Colour;

   Hex : constant String := "0123456789ABCDEF";

   function Hex2 (N : Natural) return String is
     (Hex (N / 16 mod 16 + 1) & Hex (N mod 16 + 1));

   function Hex4 (N : Natural) return String is
     (Hex2 (N / 256 mod 256) & Hex2 (N mod 256));

   function Read_Bytes (Path : String; Ok : out Boolean) return Byte_Array is
      use Ada.Streams.Stream_IO;
      F : File_Type;
   begin
      Open (F, In_File, Path);
      declare
         D : Byte_Array (0 .. Natural (Size (F)) - 1);
      begin
         Byte_Array'Read (Stream (F), D);
         Close (F);
         Ok := True;
         return D;
      end;
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
         Ok := False;
         return (1 .. 0 => 0);
   end Read_Bytes;

   procedure Write_Bytes (Path : String; Data : Byte_Array; Ok : out Boolean)
   is
      use Ada.Streams.Stream_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Byte_Array'Write (Stream (F), Data);
      Close (F);
      Ok := True;
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
         Ok := False;
   end Write_Bytes;


   procedure Write_Text (Path, Text : String; Ok : out Boolean) is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put (F, Text);
      Close (F);
      Ok := True;
   exception
      when others =>
         Ok := False;
   end Write_Text;

   function Physical_Name (C : Byte) return String is
     (case C and 7 is
        when 0 => "black", when 1 => "blue", when 2 => "red",
        when 3 => "magenta", when 4 => "green", when 5 => "cyan",
        when 6 => "yellow", when others => "white");

end Editor_Util;
