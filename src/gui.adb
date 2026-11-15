-- ***************************************************************************
--                                AdaZX - Gui
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

with Ada.Real_Time; use Ada.Real_Time;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Environment_Variables;
with Gdk.Types; use type Gdk.Types.Gdk_Modifier_Type;
with Interfaces; use Interfaces;

with Glib; use Glib;
with Glib.Main;
with Gdk.Event; use Gdk.Event;
with Gtk.Main;
with Gtk.Window; use Gtk.Window;
with Gtk.Box; use Gtk.Box;
with Gtk.Widget; use Gtk.Widget;
with Gtk.Menu; use Gtk.Menu;
with Gtk.Menu_Bar; use Gtk.Menu_Bar;
with Gtk.Menu_Item; use Gtk.Menu_Item;
with Gtk.Check_Menu_Item; use Gtk.Check_Menu_Item;
with Gtk.Radio_Menu_Item; use Gtk.Radio_Menu_Item;
with Gtk.Separator_Menu_Item; use Gtk.Separator_Menu_Item;
with Gtk.Drawing_Area; use Gtk.Drawing_Area;
with Gtk.Label; use Gtk.Label;
with Gtk.Dialog; use Gtk.Dialog;
with Gtk.File_Chooser;
with Gtk.File_Chooser_Dialog; use Gtk.File_Chooser_Dialog;
with Gtk.File_Filter; use Gtk.File_Filter;
with Gtk.Message_Dialog; use Gtk.Message_Dialog;
with Gtk.Dnd;
with Gtk.Selection_Data;
with Gdk.Drag_Contexts;
with Glib.Convert;
with GNAT.Strings;
with Cairo; use Cairo;
with Cairo.Image_Surface;
with Cairo.Pattern;
with Gtk.Clipboard;
with Gdk.Property;
with Pango.Layout;

with Config;
use type Config.Model_Type;
with Machine; use Machine;
with Keyboard;
use type Keyboard.Joy_Keyset;
use type Keyboard.Joy_Type;
with Audio;
with Sound;
with Blit;
with Video;
with Monitor;
with Forge;
with Settings;
with Host_Joystick;
with Tape;
with Interface_1;
with DivMMC;
with Peripherals;
with Types;
with ULA;

package body GUI is

   Win      : Gtk_Window;
   Bar      : Gtk_Menu_Bar;
   Is_Fullscreen : Boolean := False;
   Integer_Scale : Boolean := False;
   Last_Dir      : Unbounded_String;
   Area     : Gtk_Drawing_Area;
   Status   : Gtk_Label;
   Surf     : Cairo_Surface;

   ROMs        : Unbounded_String;
   Warp        : Boolean := False;
   Paused      : Boolean := False;
   Last_Spectrum : Model_Type := Config.ZX48;

   Item_Warp    : Gtk_Check_Menu_Item;
   Item_Pause   : Gtk_Check_Menu_Item;
   Item_Flash   : Gtk_Check_Menu_Item;
   Item_Auto_Play : Gtk_Check_Menu_Item;
   Item_Tape_Sound : Gtk_Check_Menu_Item;
   Item_16K, Item_2000, Item_Issue2, Item_IF1 : Gtk_Check_Menu_Item;
   Item_ZONX, Item_QS, Item_DivMMC, Item_ULAplus, Item_Beta, Item_Mouse,
   Item_Printer, Item_MF :
     Gtk_Check_Menu_Item;
   Model_Items : array (Model_Type) of Gtk_Radio_Menu_Item;
   Updating_Menu : Boolean := False;

   Start_Time   : Time := Clock;
   Frames_Run   : Natural := 0;
   FPS_Time     : Time := Clock;
   FPS_Frames   : Natural := 0;
   LED_Time     : Time := Clock;
   FPS          : Natural := 0;

   Audio_Target : constant := 2 * 882 + 441;    --  ~50 ms of samples

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   procedure Message (Text : String) is
      Dlg : Gtk_Message_Dialog;
      R : Gtk_Response_Type;
      pragma Unreferenced (R);
   begin
      Gtk_New (Dlg, Win, Modal, Message_Info, Buttons_Ok, Text);
      R := Dlg.Run;
      Dlg.Destroy;
      Keyboard.Release_All;
   end Message;

   function Short (S : String) return String is
     (if S'Length > 24 then S (S'First .. S'First + 21) & ".." else S);

   function Joystick_Name return String is
     (case Keyboard.Joystick is
         when Keyboard.No_Joystick => "off",
         when Keyboard.Kempston => "Kempston",
         when Keyboard.Sinclair_1 => "Sinclair 1",
         when Keyboard.Sinclair_2 => "Sinclair 2",
         when Keyboard.Cursor_Joystick => "Cursor");

   procedure Update_Status is
      T : constant String := Machine.Tape_Name;
   begin
      Status.Set_Text
        (Config.Model_Name (Machine.Model) &
         (if Machine.Is_ZX81
          then (if Machine.ZX81_16K then " 16K" else " 1K") else "") &
         (if T /= "" then "  |  tape: " & Short (T) &
            (if Machine.Tape_Motor
             then " (playing, block" & Tape.Current_Block'Image & "/" &
               Tape.Block_Count'Image & ")"
             else "") else "") &
         (if Machine.Model = Config.Plus3
          then "  |  A: " & (if Machine.Disc_Name (0) = "" then "-"
                             else Short (Machine.Disc_Name (0))) &
            (if Machine.Disc_Name (1) /= ""
             then "  B: " & Short (Machine.Disc_Name (1)) else "") &
            (if Machine.Disc_Active then " [*]" else " [ ]")
          else "") &
         (if Machine.Interface_1_Fitted
          then "  |  IF1 M1: " & (if Machine.Microdrive_Name (1) = "" then "-"
                                  else Short (Machine.Microdrive_Name (1))) &
            (if Machine.Microdrive_Name (2) /= ""
             then " M2: " & Short (Machine.Microdrive_Name (2)) else "") &
            (if Machine.Microdrive_Active then " [*]" else " [ ]")
          else "") &
         (if Machine.Beta_Fitted
          then "  |  TR-DOS A: " & (if Machine.TRD_Name (0) = "" then "-"
                                    else Short (Machine.TRD_Name (0))) &
            (if Machine.TRD_Name (1) /= ""
             then " B: " & Short (Machine.TRD_Name (1)) else "") &
            (if Machine.TRD_Active then " [*]" else " [ ]")
          else "") &
         (if Machine.DivMMC_Fitted
          then "  |  SD: " & (if Machine.SD_Name = "" then "-"
                              else Short (Machine.SD_Name)) &
            (if Machine.SD_Active then " [*]" else " [ ]")
          else "") &
         (if not Machine.Is_ZX81
          then "  |  joystick " & Joystick_Name else "") &
         (if Machine.RZX_Status /= "" then "  |  " & Machine.RZX_Status
          else "") &
         (if Warp then "  |  WARP" else "") &
         (if Paused then "  |  PAUSED" else "") &
         "  |" & FPS'Image & " fps");
   end Update_Status;

   procedure Sync_Menu is
   begin
      Updating_Menu := True;
      Item_Warp.Set_Active (Warp);
      Item_Pause.Set_Active (Paused);
      Item_Flash.Set_Active (Machine.Flash_Load);
      Item_Auto_Play.Set_Active (Machine.Auto_Play);
      Item_Tape_Sound.Set_Active (Sound.Tape_Noise);
      Item_16K.Set_Active (Machine.ZX81_16K);
      Item_2000.Set_Active (Machine.ZX81_RAM_2000);
      Item_ZONX.Set_Active (Config."=" (Config.ZX81_Sound, Config.ZON_X));
      Item_QS.Set_Active (Config."=" (Config.ZX81_Sound, Config.Quicksilva));
      Item_Issue2.Set_Active (Machine.Issue_2);
      Item_IF1.Set_Active (Machine.Interface_1_Fitted);
      Item_DivMMC.Set_Active (Machine.DivMMC_Fitted);
      Item_Beta.Set_Active (Machine.Beta_Fitted);
      Item_Mouse.Set_Active (Peripherals.Mouse_On);
      Item_Printer.Set_Active (Peripherals.Printer_On);
      Item_MF.Set_Active (Peripherals.MF_Enabled);
      Item_ULAplus.Set_Active (Config.ULAplus);
      Model_Items (Machine.Model).Set_Active (True);
      Updating_Menu := False;
      if not Machine.Is_ZX81 then
         Last_Spectrum := Machine.Model;
      end if;
      Update_Status;
   end Sync_Menu;

   procedure Start_Machine (M : Model_Type) is
      Ok : Boolean;
   begin
      Machine.Power_On (M, To_String (ROMs), Ok);
      if not Ok then
         Message ("Could not load ROMs:" & ASCII.LF & Machine.Error_Message &
                  ASCII.LF & "(see README: ROMs)");
      end if;
      Keyboard.Release_All;
   end Start_Machine;

   function Choose_Save_File (Title, Default_Name : String) return String is
      Dlg : Gtk_File_Chooser_Dialog;
      W : Gtk_Widget;
      pragma Unreferenced (W);
      Result : Unbounded_String;
   begin
      Gtk_New (Dlg, Title, Win, Gtk.File_Chooser.Action_Save);
      W := Dlg.Add_Button ("_Cancel", Gtk_Response_Cancel);
      W := Dlg.Add_Button ("_Save", Gtk_Response_Accept);
      Gtk.File_Chooser.Set_Do_Overwrite_Confirmation (+Dlg, True);
      Gtk.File_Chooser.Set_Current_Name (+Dlg, Default_Name);
      if Length (Last_Dir) > 0 then
         declare
            Ok : constant Boolean :=
              Gtk.File_Chooser.Set_Current_Folder (+Dlg, To_String (Last_Dir));
            pragma Unreferenced (Ok);
         begin
            null;
         end;
      end if;
      if Dlg.Run = Gtk_Response_Accept then
         Result := To_Unbounded_String
           (Gtk.File_Chooser.Get_Filename (+Dlg));
      end if;
      Dlg.Destroy;
      Keyboard.Release_All;
      return To_String (Result);
   end Choose_Save_File;

   function Data_Dir return String is
      Home : constant String :=
        (if Ada.Environment_Variables.Exists ("HOME")
         then Ada.Environment_Variables.Value ("HOME") else ".");
      Dir : constant String := Home & "/.local/share/adazx";
   begin
      if not Ada.Directories.Exists (Dir) then
         Ada.Directories.Create_Path (Dir);
      end if;
      return Dir;
   exception
      when others => return ".";
   end Data_Dir;

   function Quick_Snapshot_Path return String is
     (Data_Dir & "/quick.azx");

   procedure Snapshot_Save (Path : String) is
      Ok : Boolean;
   begin
      if Path /= "" then
         Machine.Save_Snapshot (Path, Ok);
         if not Ok then
            Message ("Could not write snapshot " & Path & ASCII.LF &
                     Machine.Error_Message);
         end if;
      end if;
   end Snapshot_Save;

   procedure Snapshot_Load (Path : String) is
      Ok : Boolean;
   begin
      if Path /= "" then
         if not Ada.Directories.Exists (Path) then
            Message ("No snapshot " & Path);
            return;
         end if;
         Machine.Load_Snapshot (Path, Ok);
         if not Ok then
            Message ("Could not load snapshot " & Path & ASCII.LF &
                     Machine.Error_Message);
         end if;
         Sync_Menu;
      end if;
   end Snapshot_Load;

   type Ext_List is array (Positive range <>) of String (1 .. 3);

   function Choose_File (Title : String; Exts : Ext_List;
                         Kind : String) return String is
      Dlg : Gtk_File_Chooser_Dialog;
      Filter_Own, Filter_All : Gtk_File_Filter;
      W : Gtk_Widget;
      pragma Unreferenced (W);
      Result : Unbounded_String;
      function Trim (E : String) return String is
        (if E (E'Last) = ' ' then Trim (E (E'First .. E'Last - 1)) else E);
   begin
      Gtk_New (Dlg, Title, Win, Gtk.File_Chooser.Action_Open);
      W := Dlg.Add_Button ("_Cancel", Gtk_Response_Cancel);
      W := Dlg.Add_Button ("_Open", Gtk_Response_Accept);
      Gtk_New (Filter_Own);
      Filter_Own.Set_Name (Kind);
      for Ext of Exts loop
         Filter_Own.Add_Pattern ("*." & Trim (Ext));
         Filter_Own.Add_Pattern
           ("*." & Ada.Characters.Handling.To_Upper (Trim (Ext)));
      end loop;
      Gtk_New (Filter_All);
      Filter_All.Set_Name ("All files");
      Filter_All.Add_Pattern ("*");
      Gtk.File_Chooser.Add_Filter (+Dlg, Filter_Own);
      Gtk.File_Chooser.Add_Filter (+Dlg, Filter_All);
      if Length (Last_Dir) > 0 then
         declare
            Ok : constant Boolean :=
              Gtk.File_Chooser.Set_Current_Folder
                (+Dlg, To_String (Last_Dir));
            pragma Unreferenced (Ok);
         begin
            null;
         end;
      end if;
      if Dlg.Run = Gtk_Response_Accept then
         Result := To_Unbounded_String
           (Gtk.File_Chooser.Get_Filename (+Dlg));
         begin
            Last_Dir := To_Unbounded_String
              (Ada.Directories.Containing_Directory (To_String (Result)));
         exception
            when others => null;
         end;
      end if;
      Dlg.Destroy;
      Keyboard.Release_All;
      return To_String (Result);
   end Choose_File;

   All_Types : constant Ext_List :=
     ("tap", "tzx", "dsk", "trd", "scl", "mdr", "z80", "szx", "sna", "azx", "rzx", "p  ", "81 ", "o  ", "80 ",
      "scr", "bas", "asm");
   Tape_Types : constant Ext_List := ("tap", "tzx", "p  ", "81 ", "o  ");
   Snap_Types : constant Ext_List := ("z80", "szx", "sna", "azx", "rzx");

   procedure Do_Autostart (Path : String) is
      Ok : Boolean;
   begin
      if Path = "" then
         return;
      end if;
      begin
         Machine.Autostart (Path, Ok);
      exception
         when others => Ok := False;
      end;
      if not Ok then
         Message ("Cannot start " & Path & ASCII.LF & Machine.Error_Message);
      end if;
      Sync_Menu;
   end Do_Autostart;

   ---------------------------------------------------------------------
   --  Menu callbacks
   ---------------------------------------------------------------------

   procedure On_Autostart (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Do_Autostart (Choose_File
                      ("Autostart tape / snapshot / program", All_Types,
                       "Spectrum / ZX81 / ZX80 files (tap, tzx, dsk, z80, p, o, ...)"));
   end On_Autostart;

   procedure On_Attach_Tape (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
      Path : constant String :=
        Choose_File ("Insert tape", Tape_Types, "Tapes (tap, tzx, p, 81, o)");
      Ok : Boolean;
   begin
      if Path /= "" then
         Machine.Attach_Tape (Path, Ok);
         if not Ok then
            Message ("Cannot use " & Path & ASCII.LF & Machine.Error_Message);
         end if;
         Update_Status;
      end if;
   end On_Attach_Tape;

   procedure Insert_Disc (Drive : Natural) is
      Path : constant String :=
        Choose_File ("Insert disc in drive " & (if Drive = 0 then "A" else "B"),
                     (1 => "dsk"), "+3 discs (.dsk)");
      Ok : Boolean;
   begin
      if Path /= "" then
         if Machine.Model /= Config.Plus3 then
            Message ("Discs are used by the Spectrum +3 (Machine menu).");
         end if;
         Machine.Insert_Disc (Path, Ok, Drive);
         if not Ok then
            Message ("Cannot use " & Path & ASCII.LF & Machine.Error_Message);
         end if;
         Update_Status;
      end if;
   end Insert_Disc;

   procedure On_Disc_A (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Insert_Disc (0);
   end On_Disc_A;

   procedure On_Disc_B (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Insert_Disc (1);
   end On_Disc_B;

   procedure On_Eject_A (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Machine.Eject_Disc (0);
      Update_Status;
   end On_Eject_A;

   procedure On_Eject_B (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Machine.Eject_Disc (1);
      Update_Status;
   end On_Eject_B;

   procedure On_New_Disc (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
      Path : constant String :=
        Choose_Save_File ("Create a blank +3 disc", "blank.dsk");
      Ok : Boolean;
   begin
      if Path /= "" then
         Machine.Create_Disc (Path, Ok);
         if Ok then
            Machine.Insert_Disc (Path, Ok, 0);
         end if;
         if not Ok then
            Message ("Could not create " & Path);
         end if;
         Update_Status;
      end if;
   end On_New_Disc;

   procedure Insert_MDR (Drive : Positive) is
      Path : constant String :=
        Choose_File ("Insert cartridge in Microdrive" & Drive'Image,
                     (1 => "mdr"), "Microdrive cartridges (.mdr)");
      Ok : Boolean;
   begin
      if Path /= "" then
         if not Machine.Interface_1_Fitted then
            Message ("Fit the Interface 1 first (Machine menu; 48K / 128K).");
            return;
         end if;
         Machine.Insert_Microdrive (Drive, Path, Ok);
         if not Ok then
            Message ("Cannot use " & Path & ASCII.LF & Machine.Error_Message);
         end if;
         Update_Status;
      end if;
   end Insert_MDR;

   procedure On_MDR_1 (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Insert_MDR (1);
   end On_MDR_1;

   procedure On_MDR_2 (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Insert_MDR (2);
   end On_MDR_2;

   procedure On_MDR_Eject (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Machine.Eject_Microdrive (1);
      Machine.Eject_Microdrive (2);
      Update_Status;
   end On_MDR_Eject;

   procedure On_New_MDR (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
      Path : constant String :=
        Choose_Save_File ("Create a blank Microdrive cartridge", "blank.mdr");
      Ok : Boolean;
   begin
      if Path /= "" then
         Machine.Create_Microdrive (Path, Ok);
         if not Ok then
            Message ("Could not create " & Path);
         elsif Machine.Interface_1_Fitted then
            Machine.Insert_Microdrive (1, Path, Ok);
            Message ("Blank cartridge in Microdrive 1: FORMAT ""m"";1;""name"" "
                     & "prepares it.");
         end if;
         Update_Status;
      end if;
   end On_New_MDR;

   function Choose_Folder (Title : String) return String is
      Dlg : Gtk_File_Chooser_Dialog;
      W : Gtk_Widget;
      pragma Unreferenced (W);
      Result : Unbounded_String;
   begin
      Gtk_New (Dlg, Title, Win, Gtk.File_Chooser.Action_Select_Folder);
      W := Dlg.Add_Button ("_Cancel", Gtk_Response_Cancel);
      W := Dlg.Add_Button ("_Select", Gtk_Response_Accept);
      if Length (Last_Dir) > 0 then
         declare
            Ok : constant Boolean :=
              Gtk.File_Chooser.Set_Current_Folder
                (+Dlg, To_String (Last_Dir));
            pragma Unreferenced (Ok);
         begin
            null;
         end;
      end if;
      if Dlg.Run = Gtk_Response_Accept then
         Result := To_Unbounded_String
           (Gtk.File_Chooser.Get_Filename (+Dlg));
      end if;
      Dlg.Destroy;
      Keyboard.Release_All;
      return To_String (Result);
   end Choose_Folder;

   procedure SD_Result (Ok : Boolean) is
   begin
      if not Ok then
         Message ("SD card: " & Machine.Error_Message);
      elsif not Machine.DivMMC_Fitted then
         Message ("Fit the DivMMC (Machine menu) to use the card.");
      end if;
      Sync_Menu;
      Update_Status;
   end SD_Result;

   procedure On_SD_Insert (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
      Path : constant String :=
        Choose_File ("Insert SD card image", ("img", "mmc", "hdf"),
                     "SD card images (img, mmc, hdf)");
      Ok : Boolean;
   begin
      if Path /= "" then
         Machine.Insert_SD (Path, Ok);
         SD_Result (Ok);
      end if;
   end On_SD_Insert;

   procedure On_SD_Folder (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
      Dir : constant String := Choose_Folder ("SD card from a folder");
      Ok : Boolean;
   begin
      if Dir /= "" then
         Machine.SD_From_Folder (Dir, Ok);
         if Ok and then not Machine.DivMMC_Fitted then
            Machine.Set_DivMMC (True);
         end if;
         SD_Result (Ok);
      end if;
   end On_SD_Folder;

   procedure On_SD_New (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
      Path : constant String :=
        Choose_Save_File ("Create an SD card image", "sdcard.img");
      Ok : Boolean;
   begin
      if Path /= "" then
         Machine.New_SD (Path, Ok);
         SD_Result (Ok);
      end if;
   end On_SD_New;

   procedure On_SD_Eject (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Machine.Eject_SD;
      Update_Status;
   end On_SD_Eject;

   procedure On_DivMMC (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      if not Updating_Menu then
         Machine.Set_DivMMC (Item.Get_Active);
         if Item.Get_Active and then not Machine.DivMMC_Fitted
           and then not Machine.Is_ZX81
         then
            Message ("Cannot fit the DivMMC:" & ASCII.LF &
                     Machine.Error_Message);
         end if;
         Sync_Menu;
         Update_Status;
      end if;
   end On_DivMMC;

   procedure Insert_TRD (Drive : Natural) is
      Path : constant String :=
        Choose_File ("Insert TR-DOS disc in drive " &
                     (if Drive = 0 then "A" else "B"), ("trd", "scl"),
                     "TR-DOS discs (trd, scl)");
      Ok : Boolean;
   begin
      if Path /= "" then
         if not Machine.Beta_Fitted then
            Message ("Fit the Beta 128 interface first (Machine menu; " &
                     "the Pentagon has it built in).");
            return;
         end if;
         Machine.Insert_TRD (Drive, Path, Ok);
         if not Ok then
            Message ("Cannot use " & Path & ASCII.LF & Machine.Error_Message);
         end if;
         Update_Status;
      end if;
   end Insert_TRD;

   procedure On_TRD_A (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Insert_TRD (0);
   end On_TRD_A;

   procedure On_TRD_B (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Insert_TRD (1);
   end On_TRD_B;

   procedure On_TRD_Eject (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Machine.Eject_TRD (0);
      Machine.Eject_TRD (1);
      Update_Status;
   end On_TRD_Eject;

   procedure On_New_TRD (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
      Path : constant String :=
        Choose_Save_File ("Create a blank TR-DOS disc", "blank.trd");
      Ok : Boolean;
   begin
      if Path /= "" then
         Machine.Create_TRD (Path, Ok);
         if Ok and then Machine.Beta_Fitted then
            Machine.Insert_TRD (0, Path, Ok);
         end if;
         if not Ok then
            Message ("Could not create " & Path);
         end if;
         Update_Status;
      end if;
   end On_New_TRD;

   procedure On_Beta (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      if not Updating_Menu then
         Machine.Set_Beta (Item.Get_Active);
         if Item.Get_Active and then not Machine.Beta_Fitted
           and then Machine.Model in Config.ZX48 .. Config.Plus2
         then
            Message ("Cannot fit the Beta 128:" & ASCII.LF &
                     Machine.Error_Message);
         end if;
         Sync_Menu;
         Update_Status;
      end if;
   end On_Beta;

   procedure On_Peripheral (Item : access Gtk_Check_Menu_Item_Record'Class)
   is
   begin
      if Updating_Menu then
         return;
      end if;
      if Gtk_Check_Menu_Item (Item) = Item_Mouse then
         Peripherals.Mouse_On := Item.Get_Active;
      elsif Gtk_Check_Menu_Item (Item) = Item_Printer then
         Peripherals.Printer_On := Item.Get_Active;
      elsif Gtk_Check_Menu_Item (Item) = Item_MF then
         Machine.Set_Multiface (Item.Get_Active);
         if Item.Get_Active and then not Peripherals.MF_Enabled then
            Message ("Cannot fit the Multiface 128:" & ASCII.LF &
                     Machine.Error_Message);
         end if;
         Sync_Menu;
      end if;
   end On_Peripheral;

   procedure On_Save_Paper (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
      Path : constant String :=
        Choose_Save_File ("Save the ZX Printer paper (PNG)", "printout.png");
      Ok : Boolean;
   begin
      if Path /= "" then
         Peripherals.Save_Printout (Path, Ok);
         if not Ok then
            Message ("Could not write " & Path);
         end if;
      end if;
   end On_Save_Paper;

   procedure On_Clear_Paper (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Peripherals.Clear_Printout;
   end On_Clear_Paper;

   procedure On_ULAplus (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      if not Updating_Menu then
         Config.ULAplus := Item.Get_Active;
         if not Config.ULAplus then
            ULA.Plus_On := False;          --  back to the normal colours
         end if;
      end if;
   end On_ULAplus;

   procedure On_IF1 (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      if not Updating_Menu then
         Machine.Set_Interface_1 (Item.Get_Active);
         if Item.Get_Active and then not Machine.Interface_1_Fitted
           and then Machine.Model in Config.ZX48 .. Config.Plus2
         then
            Message ("Cannot fit the Interface 1:" & ASCII.LF &
                     Machine.Error_Message);
         end if;
         Sync_Menu;
      end if;
   end On_IF1;

   procedure On_Play (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Machine.Tape_Play;
      Update_Status;
   end On_Play;

   procedure On_Stop (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Machine.Tape_Stop;
      Update_Status;
   end On_Stop;

   procedure On_Tape_Rewind (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Machine.Tape_Rewind;
      Update_Status;
   end On_Tape_Rewind;

   procedure On_Eject (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Machine.Eject_Tape;
      Update_Status;
   end On_Eject;

   procedure On_Save_Tape (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      if Machine.Tape_Recorded = 0 then
         Message ("Nothing was saved to tape yet (use SAVE).");
         return;
      end if;
      declare
         Path : constant String :=
           Choose_Save_File ("Save the tape recording",
                             (if Machine.Is_ZX80 then "recording.o"
                              elsif Machine.Is_ZX81 then "recording.p"
                              else "recording.tap"));
         Ok : Boolean;
      begin
         if Path /= "" then
            Machine.Save_Tape_Recording (Path, Ok);
            if not Ok then
               Message ("Could not write " & Path);
            end if;
         end if;
      end;
   end On_Save_Tape;

   procedure On_Flash (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      if not Updating_Menu then
         Machine.Flash_Load := Item.Get_Active;
      end if;
   end On_Flash;

   procedure On_Auto_Play (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      if not Updating_Menu then
         Machine.Auto_Play := Item.Get_Active;
      end if;
   end On_Auto_Play;

   procedure On_Tape_Sound (Item : access Gtk_Check_Menu_Item_Record'Class)
   is
   begin
      if not Updating_Menu then
         Sound.Tape_Noise := Item.Get_Active;
      end if;
   end On_Tape_Sound;

   procedure On_ZX81_Option (Item : access Gtk_Check_Menu_Item_Record'Class)
   is
   begin
      if Updating_Menu then
         return;
      end if;
      Machine.ZX81_16K := Item_16K.Get_Active;
      Machine.ZX81_RAM_2000 := Item_2000.Get_Active;
      Machine.Issue_2 := Item_Issue2.Get_Active;
      if Gtk_Check_Menu_Item (Item) = Item_ZONX then
         Config.ZX81_Sound :=
           (if Item_ZONX.Get_Active then Config.ZON_X else Config.No_Board);
      elsif Gtk_Check_Menu_Item (Item) = Item_QS then
         Config.ZX81_Sound :=
           (if Item_QS.Get_Active then Config.Quicksilva
            else Config.No_Board);
      end if;
      if Gtk_Check_Menu_Item (Item) /= Item_Issue2
        and then Machine.Is_ZX81
      then
         Machine.Reset;          --  RAM changes need a power-on
      end if;
      Sync_Menu;
   end On_ZX81_Option;

   procedure On_Save_Snapshot (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Snapshot_Save (Choose_Save_File
                       ("Save snapshot (.z80, .szx, .sna or .azx)",
                        (if Machine.Is_ZX81 then "snapshot.azx"
                         else "snapshot.z80")));
   end On_Save_Snapshot;

   procedure On_Load_Snapshot (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Snapshot_Load (Choose_File ("Load snapshot", Snap_Types,
                                  "Snapshots and recordings (z80, szx, sna, " &
                                  "azx, rzx)"));
   end On_Load_Snapshot;

   procedure On_Quick_Save (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Snapshot_Save (Quick_Snapshot_Path);
   end On_Quick_Save;

   procedure On_Quick_Load (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Snapshot_Load (Quick_Snapshot_Path);
   end On_Quick_Load;

   procedure On_Record (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      if Machine.Is_ZX81 then
         Message ("RZX recordings are for the Spectrum models.");
      elsif Machine.RZX_Recording then
         Message ("Already recording (Machine -> Stop RZX recording).");
      else
         Machine.Start_RZX_Recording;
         Update_Status;
      end if;
   end On_Record;

   procedure On_Stop_Record (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
      Ok : Boolean;
   begin
      if not Machine.RZX_Recording then
         Message ("No RZX recording is running.");
         return;
      end if;
      declare
         Path : constant String :=
           Choose_Save_File ("Save the RZX recording", "recording.rzx");
      begin
         Machine.Stop_RZX_Recording (Path, Ok);
         if not Ok then
            Message ("Could not write " & Path);
         end if;
      end;
      Update_Status;
   end On_Stop_Record;

   procedure On_Screenshot (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
      Path : constant String := Choose_Save_File ("Save screenshot",
                                                  "screen.png");
   begin
      if Path /= "" then
         Blit.Save_PNG (Path);
      end if;
   end On_Screenshot;

   procedure Refresh_Screen is
   begin
      Blit.Copy (Surf);
      Area.Queue_Draw;
   end Refresh_Screen;

   procedure On_Monitor (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Keyboard.Release_All;
      Monitor.Open (Win, "stopped");
   end On_Monitor;

   procedure On_Forge (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Keyboard.Release_All;
      Forge.Open (Win, "");
   end On_Forge;

   procedure Toggle_Fullscreen is
   begin
      Is_Fullscreen := not Is_Fullscreen;
      if Is_Fullscreen then
         Bar.Hide;
         Status.Hide;
         Win.Fullscreen;
      else
         Win.Unfullscreen;
         Bar.Show;
         Status.Show;
      end if;
   end Toggle_Fullscreen;

   procedure Paste_Text is
      Clip : constant Gtk.Clipboard.Gtk_Clipboard :=
        Gtk.Clipboard.Get (Gdk.Property.Atom_Intern ("CLIPBOARD"));
      Text : constant String := Clip.Wait_For_Text;
      Clean : Unbounded_String;
   begin
      for C of Text loop
         if C = ASCII.LF or else C in ' ' .. '~' then
            Append (Clean, C);
         end if;
      end loop;
      Machine.Type_Text (To_String (Clean));
   exception
      when others => null;
   end Paste_Text;

   procedure On_Fullscreen (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Toggle_Fullscreen;
   end On_Fullscreen;

   procedure On_Integer_Scale
     (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      Integer_Scale := Item.Get_Active;
      Area.Queue_Draw;
   end On_Integer_Scale;

   procedure On_CRT (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      Video.Scanlines := Item.Get_Active;
   end On_CRT;

   procedure On_Positional
     (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      Keyboard.Positional := Item.Get_Active;
      Keyboard.Release_All;
   end On_Positional;

   procedure On_Paste (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Paste_Text;
   end On_Paste;

   function Model_Key (M : Model_Type) return String is
     (case M is
         when Config.ZX48 => "48", when Config.ZX128 => "128",
         when Config.TC2048 => "tc2048", when Config.Pentagon => "pentagon",
         when Config.Plus2 => "plus2", when Config.Plus2A => "plus2a",
         when Config.Plus3 => "plus3", when Config.ZX81 => "zx81",
         when Config.ZX80 => "zx80");

   procedure Save_Settings is
   begin
      Settings.Set ("model", Model_Key (Machine.Model));
      Settings.Set ("joystick", Keyboard.Joy_Type'Image (Keyboard.Joystick));
      Settings.Set ("joykeys",
                    (if Keyboard.Joystick_Keys = Keyboard.Keypad
                     then "keypad" else "cursor"));
      Settings.Set ("controller",
                    (if Host_Joystick.Selected >= 0
                     then Host_Joystick.Name (Host_Joystick.Selected)
                     else "none"));
      Settings.Set ("mute", Audio.Muted);
      Settings.Set ("positional", Keyboard.Positional);
      Settings.Set ("integerscale", Integer_Scale);
      Settings.Set ("crt", Video.Scanlines);
      Settings.Set ("flashload", Machine.Flash_Load);
      Settings.Set ("autoplay", Machine.Auto_Play);
      Settings.Set ("tapesound", Sound.Tape_Noise);
      Settings.Set ("zx81_16k", Machine.ZX81_16K);
      Settings.Set ("zx81_ram2000", Machine.ZX81_RAM_2000);
      Settings.Set ("zx81_sound",
                    Config.ZX81_Sound_Type'Image (Config.ZX81_Sound));
      Settings.Set ("issue2", Machine.Issue_2);
      Settings.Set ("interface1", Interface_1.Enabled);
      Settings.Set ("divmmc", DivMMC.Enabled);
      Settings.Set ("ulaplus", Config.ULAplus);
      Settings.Set ("beta128", Machine.Beta_Wanted);
      Settings.Set ("kempston_mouse", Peripherals.Mouse_On);
      Settings.Set ("zx_printer", Peripherals.Printer_On);
      Settings.Set ("multiface128", Peripherals.MF_Enabled);
      Settings.Set ("sdcard", Machine.SD_Name);
      Settings.Set ("lastdir", To_String (Last_Dir));
      declare
         W, H : Gint;
      begin
         Win.Get_Size (W, H);
         if not Is_Fullscreen then
            Settings.Set ("width", Integer (W));
            Settings.Set ("height", Integer (H));
         end if;
      end;
      Settings.Save;
   end Save_Settings;

   procedure On_Quit (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Win.Destroy;
   end On_Quit;

   procedure On_Reset (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Machine.Reset;
      Sync_Menu;
   end On_Reset;

   procedure On_NMI (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Machine.NMI_Button;
   end On_NMI;

   procedure On_Model (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      if Updating_Menu or else not Item.Get_Active then
         return;
      end if;
      for M in Model_Items'Range loop
         if Gtk_Radio_Menu_Item (Item) = Model_Items (M)
           and then Machine.Model /= M
         then
            Start_Machine (M);
         end if;
      end loop;
      Sync_Menu;
   end On_Model;

   procedure On_Warp (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      if not Updating_Menu then
         Warp := Item.Get_Active;
         Update_Status;
      end if;
   end On_Warp;

   procedure On_Pause (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      if not Updating_Menu then
         Paused := Item.Get_Active;
         Update_Status;
      end if;
   end On_Pause;

   procedure On_Mute (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      Audio.Muted := Item.Get_Active;
   end On_Mute;

   Joy_Items : array (Keyboard.Joy_Type) of Gtk_Radio_Menu_Item;
   Host_Items : array (-1 .. Host_Joystick.Max_Devices - 1)
     of Gtk_Radio_Menu_Item;
   Keyset_Keypad, Keyset_Cursor : Gtk_Radio_Menu_Item;

   procedure On_Host_Joy (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      if Updating_Menu or else not Item.Get_Active then
         return;
      end if;
      for I in Host_Items'Range loop
         if Host_Items (I) /= null
           and then Gtk_Radio_Menu_Item (Item) = Host_Items (I)
         then
            if I < 0 then
               Host_Joystick.Close;
            else
               Host_Joystick.Open (I);
            end if;
         end if;
      end loop;
      Update_Status;
   end On_Host_Joy;

   procedure On_Joy (Item : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      if Updating_Menu or else not Item.Get_Active then
         return;
      end if;
      for J in Joy_Items'Range loop
         if Gtk_Radio_Menu_Item (Item) = Joy_Items (J) then
            Keyboard.Joystick := J;
         end if;
      end loop;
      if Gtk_Radio_Menu_Item (Item) = Keyset_Keypad then
         Keyboard.Joystick_Keys := Keyboard.Keypad;
      elsif Gtk_Radio_Menu_Item (Item) = Keyset_Cursor then
         Keyboard.Joystick_Keys := Keyboard.Cursor_Keys;
      end if;
      Keyboard.Release_All;
      Update_Status;
   end On_Joy;

   procedure On_Keys_Help (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Message
        (Keyboard.Keys_Help & ASCII.LF & ASCII.LF &
         "Emulator keys: F11 warp, Alt+Enter fullscreen," & ASCII.LF &
         "  Alt+A autostart, Alt+T insert tape, Alt+P play / stop tape," &
         ASCII.LF & "  Alt+R reset, Alt+N NMI, Alt+M monitor," & ASCII.LF &
         "  Alt+S / Alt+L quick save / load, Ctrl+Shift+V paste text.");
   end On_Keys_Help;

   procedure On_About (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
   begin
      Message ("AdaZX" & ASCII.LF &
               "ZX Spectrum 48K / 128K / +2 / +2A / +3 and ZX81 emulator" &
               ASCII.LF & "in Ada and GtkAda." & ASCII.LF & ASCII.LF &
               "Amstrad have kindly given their permission for the" &
               ASCII.LF & "redistribution of their copyrighted material" &
               ASCII.LF & "but retain that copyright.");
   end On_About;

   ---------------------------------------------------------------------
   --  Event handlers
   ---------------------------------------------------------------------

   Last_OX, Last_OY : Float := 0.0;      --  where the picture was drawn
   Last_Scale : Float := 1.0;

   --  The Kempston mouse follows the pointer over the picture (X to the
   --  right, Y up, in screen pixels); buttons: left, right, middle
   procedure Mouse_At (X, Y : Gdouble) is
      PX : constant Integer := Integer
        (Float'Floor ((Float (X) - Last_OX) / Last_Scale / 2.0))
        - Video.Border;
      PY : constant Integer := Integer
        (Float'Floor ((Float (Y) - Last_OY) / Last_Scale / 2.0))
        - Video.Border;
   begin
      Peripherals.Mouse_X := Types.Byte (PX mod 256);
      Peripherals.Mouse_Y := Types.Byte ((191 - PY) mod 256);
   end Mouse_At;

   function On_Motion (Self : access Gtk_Widget_Record'Class;
                       Event : Gdk_Event_Motion) return Boolean is
      pragma Unreferenced (Self);
   begin
      if Peripherals.Mouse_On then
         Mouse_At (Event.X, Event.Y);
      end if;
      return False;
   end On_Motion;

   function On_Mouse_Button (Self : access Gtk_Widget_Record'Class;
                             Event : Gdk_Event_Button) return Boolean is
      pragma Unreferenced (Self);
      use type Types.Byte;
      Bit : constant Types.Byte :=
        (case Event.Button is when 1 => 2, when 3 => 1, when 2 => 4,
            when others => 0);
   begin
      if not Peripherals.Mouse_On or else Bit = 0 then
         return False;
      end if;
      if Event.The_Type = Button_Press then
         Peripherals.Mouse_Buttons := Peripherals.Mouse_Buttons and not Bit;
      else
         Peripherals.Mouse_Buttons := Peripherals.Mouse_Buttons or Bit;
      end if;
      return True;
   end On_Mouse_Button;

   function On_Draw (Self : access Gtk_Widget_Record'Class;
                     Cr   : Cairo_Context) return Boolean
   is
      W  : constant Float := Float (Self.Get_Allocated_Width);
      H  : constant Float := Float (Self.Get_Allocated_Height);
      SW : constant Float := Float (Blit.Width);
      SH : constant Float := Float (Blit.Height);
      Fit : constant Float := Float'Min (W / SW, H / SH);
      Scale : constant Float :=
        (if Integer_Scale and then Fit >= 0.5
         then Float'Floor (Fit * 2.0) / 2.0 else Fit);
      OX : constant Float := Float'Floor ((W - SW * Scale) / 2.0);
      OY : constant Float := Float'Floor ((H - SH * Scale) / 2.0);
   begin
      Last_OX := OX;
      Last_OY := OY;
      Last_Scale := Scale;
      Set_Source_Rgb (Cr, 0.0, 0.0, 0.0);
      Paint (Cr);
      Translate (Cr, Gdouble (OX), Gdouble (OY));
      Cairo.Scale (Cr, Gdouble (Scale), Gdouble (Scale));
      Rectangle (Cr, 0.0, 0.0, Gdouble (SW), Gdouble (SH));
      Clip (Cr);
      Set_Source_Surface (Cr, Surf, 0.0, 0.0);
      Cairo.Pattern.Set_Filter
        (Get_Source (Cr),
         (if Scale < 1.0 then Cairo.Pattern.Cairo_Filter_Good
          else Cairo.Pattern.Cairo_Filter_Nearest));
      Paint (Cr);
      return True;
   end On_Draw;

   function Alt_Key (Event : Gdk_Event_Key) return Boolean is
     ((Event.State and Gdk.Types.Mod1_Mask) /= 0);

   function On_Key_Press (Self  : access Gtk_Widget_Record'Class;
                          Event : Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
      KV : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Event.Keyval);
      function Is_Char (C : Character) return Boolean is
        (KV = Character'Pos (C) or else
         KV = Character'Pos (Ada.Characters.Handling.To_Upper (C)));
   begin
      if Alt_Key (Event) then
         Keyboard.Release_All;
         if KV = 16#FF0D# then
            Toggle_Fullscreen;
         elsif Is_Char ('a') then
            On_Autostart (null);
         elsif Is_Char ('t') then
            On_Attach_Tape (null);
         elsif Is_Char ('d') then
            On_Disc_A (null);
         elsif Is_Char ('p') then
            if Machine.Tape_Motor then
               Machine.Tape_Stop;
            else
               Machine.Tape_Play;
            end if;
            Update_Status;
         elsif Is_Char ('r') then
            Machine.Reset;
            Sync_Menu;
         elsif Is_Char ('n') then
            Machine.NMI_Button;
         elsif Is_Char ('m') then
            Monitor.Open (Win, "stopped");
         elsif Is_Char ('s') then
            Snapshot_Save (Quick_Snapshot_Path);
         elsif Is_Char ('l') then
            Snapshot_Load (Quick_Snapshot_Path);
         else
            return False;          --  menu mnemonics
         end if;
         return True;
      end if;
      if (Event.State and Gdk.Types.Control_Mask) /= 0
        and then (Event.State and Gdk.Types.Shift_Mask) /= 0
        and then Is_Char ('v')
      then
         Keyboard.Release_All;
         Paste_Text;
         return True;
      end if;
      if KV = 16#FFC8# then          --  F11
         Warp := not Warp;
         Sync_Menu;
         return True;
      end if;
      Keyboard.Key_Event (KV, Natural (Event.Hardware_Keycode), True);
      return True;
   end On_Key_Press;

   function On_Key_Release (Self  : access Gtk_Widget_Record'Class;
                            Event : Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
   begin
      Keyboard.Key_Event (Interfaces.Unsigned_32 (Event.Keyval),
                          Natural (Event.Hardware_Keycode), False);
      return True;
   end On_Key_Release;

   function On_Focus_Out (Self  : access Gtk_Widget_Record'Class;
                          Event : Gdk_Event_Focus) return Boolean
   is
      pragma Unreferenced (Self, Event);
   begin
      Keyboard.Release_All;
      return False;
   end On_Focus_Out;

   procedure On_Drop
     (Self    : access Gtk_Widget_Record'Class;
      Context : not null access Gdk.Drag_Contexts.Drag_Context_Record'Class;
      X, Y    : Gint;
      Data    : Gtk.Selection_Data.Gtk_Selection_Data;
      Info    : Guint;
      Time    : Guint)
   is
      pragma Unreferenced (Self, Context, X, Y, Info, Time);
      use type GNAT.Strings.String_Access;
      URIs : GNAT.Strings.String_List :=
        Gtk.Selection_Data.Get_Uris (Data);
   begin
      if URIs'Length > 0 and then URIs (URIs'First) /= null then
         declare
            Path : constant String :=
              Glib.Convert.Filename_From_URI (URIs (URIs'First).all, null);
         begin
            Do_Autostart (Path);
         end;
      end if;
      for U of URIs loop
         GNAT.Strings.Free (U);
      end loop;
   end On_Drop;

   procedure On_Destroy (Self : access Gtk_Widget_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Save_Settings;
      Gtk.Main.Main_Quit;
   end On_Destroy;

   function On_Win_Delete (Self : access Gtk_Widget_Record'Class;
                           Event : Gdk_Event) return Boolean is
      pragma Unreferenced (Self, Event);
   begin
      if Open_Forge then
         Win.Hide;      --  in the forge the emulator window only hides
         return True;
      end if;
      return False;
   end On_Win_Delete;

   procedure Quit_App is
   begin
      Win.Destroy;
   end Quit_App;

   procedure Show_Emulator is
   begin
      Win.Show_All;
      if Is_Fullscreen then
         Bar.Hide;
         Status.Hide;
      end if;
      Win.Present;
   end Show_Emulator;

   ---------------------------------------------------------------------
   --  Emulation pacing
   ---------------------------------------------------------------------

   function On_Timer_Data (Unused : Integer) return Boolean;

   package Timer_Sources is new Glib.Main.Generic_Sources (Integer);

   function On_Timer return Boolean is
      Now : constant Time := Clock;
      Ran : Natural := 0;
   begin
      Host_Joystick.Poll;
      if Paused or else Monitor.Active then
         return True;
      end if;

      if Warp or else Machine.Autostart_Busy
        or else (Machine.Tape_Motor and then not Machine.Flash_Load)
        or else (Machine.Typing_Busy and then Machine.Is_ZX81)
      then
         declare
            Deadline : constant Time := Now + Milliseconds (15);
         begin
            loop
               Machine.Run_Frame;
               Ran := Ran + 1;
               exit when Clock >= Deadline or else Machine.Break_Hit;
            end loop;
         end;
         Audio.Flush;
         Start_Time := Clock;
         Frames_Run := 0;
      elsif Audio.Available then
         while Audio.Buffered < Audio_Target and then Ran < 4 loop
            Machine.Run_Frame;
            Audio.Flush;
            Ran := Ran + 1;
         end loop;
      else
         declare
            Elapsed : constant Duration := To_Duration (Now - Start_Time);
            Due : constant Integer :=
              Integer (Float (Elapsed) * Machine.Frame_Rate) - Frames_Run;
         begin
            if Due > 10 then
               Start_Time := Now;
               Frames_Run := 0;
            end if;
            for F in 1 .. Integer'Min (Due, 3) loop
               Machine.Run_Frame;
               Audio.Flush;
               Ran := Ran + 1;
               Frames_Run := Frames_Run + 1;
            end loop;
         end;
      end if;

      if Forge.Is_Open then
         Forge.Tick;
      end if;
      if Machine.Break_Hit and then not Monitor.Active
        and then not Forge.Is_Open
      then
         Keyboard.Release_All;
         Refresh_Screen;
         Monitor.Open (Win, Machine.Stop_Text);
         return True;
      end if;

      if Ran > 0 then
         Blit.Copy (Surf);
         Area.Queue_Draw;
         FPS_Frames := FPS_Frames + Ran;
      end if;

      if Now - LED_Time >= Milliseconds (250) then
         LED_Time := Now;
         Update_Status;
      end if;

      if Now - FPS_Time >= Seconds (1) then
         FPS := FPS_Frames;
         FPS_Frames := 0;
         FPS_Time := Now;
      end if;
      return True;
   end On_Timer;

   function On_Timer_Data (Unused : Integer) return Boolean is
     (On_Timer);

   ---------------------------------------------------------------------
   --  Construction
   ---------------------------------------------------------------------

   function Add_Menu (Bar : Gtk_Menu_Bar; Title : String) return Gtk_Menu is
      Item : Gtk_Menu_Item;
      Menu : Gtk_Menu;
   begin
      Gtk_New_With_Mnemonic (Item, Title);
      Gtk_New (Menu);
      Item.Set_Submenu (Menu);
      Bar.Append (Item);
      return Menu;
   end Add_Menu;

   procedure Add_Item (Menu : Gtk_Menu; Label : String;
                       Cb : Cb_Gtk_Menu_Item_Void) is
      Item : Gtk_Menu_Item;
   begin
      Gtk_New_With_Mnemonic (Item, Label);
      Item.On_Activate (Cb);
      Menu.Append (Item);
   end Add_Item;

   procedure Add_Check (Menu : Gtk_Menu; Label : String;
                        Item : out Gtk_Check_Menu_Item;
                        Cb : Cb_Gtk_Check_Menu_Item_Void) is
   begin
      Gtk_New_With_Mnemonic (Item, Label);
      Item.On_Toggled (Cb);
      Menu.Append (Item);
   end Add_Check;

   procedure Add_Separator (Menu : Gtk_Menu) is
      Sep : Gtk_Separator_Menu_Item;
   begin
      Gtk_New (Sep);
      Menu.Append (Sep);
   end Add_Separator;

   procedure Add_Radio (Menu : Gtk_Menu; Label : String;
                        Group : in out Widget_SList.GSlist;
                        Item : out Gtk_Radio_Menu_Item;
                        Cb : Cb_Gtk_Check_Menu_Item_Void) is
   begin
      Gtk_New (Item, Group, Label);
      Group := Item.Get_Group;
      Item.On_Toggled (Cb);
      Menu.Append (Item);
   end Add_Radio;

   procedure Run (Model : Machine.Model_Type; ROM_Dir : String;
                  File : String; Attach : String := "";
                  Model_Given : Boolean := False) is
      VBox : Gtk_Box;
      M_File, M_Machine, M_Input, M_View, M_Tools, M_Help : Gtk_Menu;
      Mute, Item_Pos, Item_Int, Item_CRT : Gtk_Check_Menu_Item;
      Model_Group, Joy_Group, Keyset_Group, Host_Group :
        Widget_SList.GSlist := Widget_SList.Null_List;
      Timer : Glib.Main.G_Source_Id;
      pragma Unreferenced (Timer);
      Start_Model : Model_Type := Model;
   begin
      ROMs := To_Unbounded_String (ROM_Dir);
      Gtk.Main.Init;

      Settings.Load;
      Audio.Muted := Settings.Get ("mute", False);
      Keyboard.Positional := Settings.Get ("positional", False);
      Integer_Scale := Settings.Get ("integerscale", False);
      Video.Scanlines := Settings.Get ("crt", False);
      Machine.Flash_Load := Settings.Get ("flashload", Machine.Flash_Load);
      Machine.Auto_Play := Settings.Get ("autoplay", True);
      Sound.Tape_Noise := Settings.Get ("tapesound", True);
      Machine.ZX81_16K := Settings.Get ("zx81_16k", Machine.ZX81_16K);
      Machine.ZX81_RAM_2000 :=
        Settings.Get ("zx81_ram2000", Machine.ZX81_RAM_2000);
      declare
         V : constant String := Settings.Get ("zx81_sound", "NO_BOARD");
      begin
         Config.ZX81_Sound := Config.ZX81_Sound_Type'Value (V);
      exception
         when Constraint_Error => null;
      end;
      Machine.Issue_2 := Settings.Get ("issue2", Machine.Issue_2);
      if not Interface_1.Enabled then
         Interface_1.Enabled := Settings.Get ("interface1", False);
      end if;
      if not DivMMC.Enabled then
         DivMMC.Enabled := Settings.Get ("divmmc", False);
      end if;
      if not Config.ULAplus then
         Config.ULAplus := Settings.Get ("ulaplus", False);
      end if;
      if not Machine.Beta_Wanted then
         Machine.Beta_Wanted := Settings.Get ("beta128", False);
      end if;
      if not Peripherals.Mouse_On then
         Peripherals.Mouse_On := Settings.Get ("kempston_mouse", False);
      end if;
      if not Peripherals.Printer_On then
         Peripherals.Printer_On := Settings.Get ("zx_printer", False);
      end if;
      if not Peripherals.MF_Enabled then
         Peripherals.MF_Enabled := Settings.Get ("multiface128", False);
      end if;
      if Machine.SD_Name = "" then
         declare
            P : constant String := Settings.Get ("sdcard", "");
            Ok : Boolean;
         begin
            if P /= "" and then Ada.Directories.Exists (P) then
               Machine.Insert_SD (P, Ok);
            end if;
         end;
      end if;
      Last_Dir := To_Unbounded_String (Settings.Get ("lastdir", ""));
      begin
         Keyboard.Joystick := Keyboard.Joy_Type'Value
           (Settings.Get ("joystick", "KEMPSTON"));
      exception
         when others => Keyboard.Joystick := Keyboard.Kempston;
      end;
      if not Model_Given then
         declare
            Saved : constant String := Settings.Get ("model", "48");
         begin
            for M in Model_Type loop
               if Model_Key (M) = Saved then
                  Start_Model := M;
               end if;
            end loop;
         end;
      end if;

      Gtk_New (Win);
      Win.Set_Title ("AdaZX");
      Win.Set_Default_Size (Gint (Settings.Get ("width", 740)),
                            Gint (Settings.Get ("height", 660)));
      Win.On_Destroy (On_Destroy'Access);
      Win.On_Delete_Event (On_Win_Delete'Access);
      Win.On_Key_Press_Event (On_Key_Press'Access);
      Win.On_Key_Release_Event (On_Key_Release'Access);
      Win.On_Focus_Out_Event (On_Focus_Out'Access);

      Gtk_New_Vbox (VBox);
      Win.Add (VBox);

      Gtk_New (Bar);
      VBox.Pack_Start (Bar, Expand => False, Fill => False);

      M_File := Add_Menu (Bar, "_File");
      Add_Item (M_File, "_Autostart tape / snapshot / program... (Alt+A)",
                On_Autostart'Access);
      Add_Separator (M_File);
      Add_Item (M_File, "Insert +3 _disc in drive A (.dsk)... (Alt+D)",
                On_Disc_A'Access);
      Add_Item (M_File, "Insert +3 disc in drive B...", On_Disc_B'Access);
      Add_Item (M_File, "Eject drive A", On_Eject_A'Access);
      Add_Item (M_File, "Eject drive B", On_Eject_B'Access);
      Add_Item (M_File, "_New blank +3 disc...", On_New_Disc'Access);
      Add_Separator (M_File);
      Add_Item (M_File, "Insert Microdrive _cartridge 1 (.mdr)...",
                On_MDR_1'Access);
      Add_Item (M_File, "Insert Microdrive cartridge 2...", On_MDR_2'Access);
      Add_Item (M_File, "Eject the Microdrive cartridges", On_MDR_Eject'Access);
      Add_Item (M_File, "New blank Microdrive cartridge...", On_New_MDR'Access);
      Add_Item (M_File, "Insert _TR-DOS disc in drive A (.trd / .scl)...",
                On_TRD_A'Access);
      Add_Item (M_File, "Insert TR-DOS disc in drive B...", On_TRD_B'Access);
      Add_Item (M_File, "Eject the TR-DOS discs", On_TRD_Eject'Access);
      Add_Item (M_File, "New blank TR-DOS disc...", On_New_TRD'Access);
      Add_Item (M_File, "Save the ZX _Printer paper (PNG)...",
                On_Save_Paper'Access);
      Add_Item (M_File, "Clear the ZX Printer paper", On_Clear_Paper'Access);
      Add_Item (M_File, "Insert _SD card image (DivMMC)...",
                On_SD_Insert'Access);
      Add_Item (M_File, "SD card from a _folder (DivMMC)...",
                On_SD_Folder'Access);
      Add_Item (M_File, "New SD card image...", On_SD_New'Access);
      Add_Item (M_File, "Eject the SD card", On_SD_Eject'Access);
      Add_Separator (M_File);
      Add_Item (M_File, "Insert _tape (.tap .tzx .p)... (Alt+T)",
                On_Attach_Tape'Access);
      Add_Item (M_File, "_Play tape (Alt+P)", On_Play'Access);
      Add_Item (M_File, "_Stop tape", On_Stop'Access);
      Add_Item (M_File, "_Rewind tape", On_Tape_Rewind'Access);
      Add_Item (M_File, "_Eject tape", On_Eject'Access);
      Add_Item (M_File, "Save tape recording (.tap / .p)...",
                On_Save_Tape'Access);
      Add_Check (M_File, "Flash loading of standard blocks", Item_Flash,
                 On_Flash'Access);
      Add_Check (M_File, "Play the tape when the ROM loads", Item_Auto_Play,
                 On_Auto_Play'Access);
      Add_Check (M_File, "Hear the tape while loading", Item_Tape_Sound,
                 On_Tape_Sound'Access);
      Add_Separator (M_File);
      Add_Item (M_File, "Save screens_hot (PNG)...", On_Screenshot'Access);
      Add_Separator (M_File);
      Add_Item (M_File, "_Quit", On_Quit'Access);

      M_Machine := Add_Menu (Bar, "_Machine");
      for M in Model_Type loop
         Add_Radio (M_Machine, Config.Model_Name (M), Model_Group,
                    Model_Items (M), On_Model'Access);
      end loop;
      Add_Separator (M_Machine);
      Add_Check (M_Machine, "ZX81 / ZX80: 16K RAM pack", Item_16K,
                 On_ZX81_Option'Access);
      Add_Check (M_Machine, "ZX81: 8K RAM at &2000 (hi-res)", Item_2000,
                 On_ZX81_Option'Access);
      Add_Check (M_Machine, "ZX81 / ZX80: ZON X-81 sound board", Item_ZONX,
                 On_ZX81_Option'Access);
      Add_Check (M_Machine, "ZX81 / ZX80: Quicksilva sound board", Item_QS,
                 On_ZX81_Option'Access);
      Add_Check (M_Machine, "48K: issue 2 keyboard", Item_Issue2,
                 On_ZX81_Option'Access);
      Add_Check (M_Machine, "Interface _1 with Microdrives (48K / 128K)",
                 Item_IF1, On_IF1'Access);
      Add_Check (M_Machine, "_DivMMC with esxDOS (SD card; NMI = browser)",
                 Item_DivMMC, On_DivMMC'Access);
      Add_Check (M_Machine, "_Beta 128 disk interface (TR-DOS; 48K / 128K)",
                 Item_Beta, On_Beta'Access);
      Add_Check (M_Machine, "_Kempston mouse (the pointer over the picture)",
                 Item_Mouse, On_Peripheral'Access);
      Add_Check (M_Machine, "ZX _Printer (LPRINT, COPY)", Item_Printer,
                 On_Peripheral'Access);
      Add_Check (M_Machine, "_Multiface 128 (Alt+N = red button)", Item_MF,
                 On_Peripheral'Access);
      Add_Check (M_Machine, "ULA_plus 64-colour palette", Item_ULAplus,
                 On_ULAplus'Access);
      Add_Separator (M_Machine);
      Add_Item (M_Machine, "_Reset (Alt+R)", On_Reset'Access);
      Add_Item (M_Machine, "_NMI (Alt+N)", On_NMI'Access);
      Add_Separator (M_Machine);
      Add_Item (M_Machine, "Save _snapshot...", On_Save_Snapshot'Access);
      Add_Item (M_Machine, "_Load snapshot...", On_Load_Snapshot'Access);
      Add_Item (M_Machine, "_Quick save (Alt+S)", On_Quick_Save'Access);
      Add_Item (M_Machine, "Quick l_oad (Alt+L)", On_Quick_Load'Access);
      Add_Item (M_Machine, "Start RZX _input recording", On_Record'Access);
      Add_Item (M_Machine, "Stop RZX recording and save...",
                On_Stop_Record'Access);
      Add_Separator (M_Machine);
      Add_Item (M_Machine, "Paste text (Ctrl+Shift+V)", On_Paste'Access);
      Add_Check (M_Machine, "_Pause", Item_Pause, On_Pause'Access);
      Add_Check (M_Machine, "_Warp mode (F11)", Item_Warp, On_Warp'Access);
      Add_Check (M_Machine, "_Mute sound", Mute, On_Mute'Access);

      M_Input := Add_Menu (Bar, "_Input");
      Add_Radio (M_Input, "No joystick", Joy_Group,
                 Joy_Items (Keyboard.No_Joystick), On_Joy'Access);
      Add_Radio (M_Input, "Kempston joystick", Joy_Group,
                 Joy_Items (Keyboard.Kempston), On_Joy'Access);
      Add_Radio (M_Input, "Sinclair joystick 1 (keys 6-0)", Joy_Group,
                 Joy_Items (Keyboard.Sinclair_1), On_Joy'Access);
      Add_Radio (M_Input, "Sinclair joystick 2 (keys 1-5)", Joy_Group,
                 Joy_Items (Keyboard.Sinclair_2), On_Joy'Access);
      Add_Radio (M_Input, "Cursor / Protek joystick (5-8, 0)", Joy_Group,
                 Joy_Items (Keyboard.Cursor_Joystick), On_Joy'Access);
      Add_Separator (M_Input);
      Add_Radio (M_Input, "Joystick on the keypad", Keyset_Group,
                 Keyset_Keypad, On_Joy'Access);
      Add_Radio (M_Input, "Joystick on cursor keys + Right Alt",
                 Keyset_Group, Keyset_Cursor, On_Joy'Access);
      Add_Separator (M_Input);
      Add_Check (M_Input, "Positional keyboard mapping", Item_Pos,
                 On_Positional'Access);
      Add_Separator (M_Input);
      Host_Joystick.Scan;
      Add_Radio (M_Input, "No game controller", Host_Group, Host_Items (-1),
                 On_Host_Joy'Access);
      for I in 0 .. Host_Joystick.Count - 1 loop
         Add_Radio (M_Input, "Controller: " & Host_Joystick.Name (I),
                    Host_Group, Host_Items (I), On_Host_Joy'Access);
      end loop;

      M_View := Add_Menu (Bar, "_View");
      Add_Item (M_View, "_Fullscreen (Alt+Enter)", On_Fullscreen'Access);
      Add_Check (M_View, "_Integer scaling", Item_Int,
                 On_Integer_Scale'Access);
      Add_Check (M_View, "_CRT scanlines", Item_CRT, On_CRT'Access);

      M_Tools := Add_Menu (Bar, "_Tools");
      Add_Item (M_Tools, "Mo_nitor (Alt+M)", On_Monitor'Access);
      Add_Item (M_Tools, "_Forge: assembler, BASIC and editors",
                On_Forge'Access);

      M_Help := Add_Menu (Bar, "_Help");
      Add_Item (M_Help, "_Keyboard", On_Keys_Help'Access);
      Add_Item (M_Help, "_About", On_About'Access);

      Gtk_New (Area);
      Area.Set_Size_Request (352, 288);
      Area.On_Draw (On_Draw'Access);
      Area.Add_Events (Pointer_Motion_Mask or Button_Press_Mask
                       or Button_Release_Mask);
      Area.On_Motion_Notify_Event (On_Motion'Access);
      Area.On_Button_Press_Event (On_Mouse_Button'Access);
      Area.On_Button_Release_Event (On_Mouse_Button'Access);
      Gtk.Dnd.Dest_Set (Area, Gtk.Dnd.Dest_Default_All,
                        Actions => Gdk.Drag_Contexts.Action_Copy);
      Gtk.Dnd.Dest_Add_Uri_Targets (Area);
      Area.On_Drag_Data_Received (On_Drop'Access);
      VBox.Pack_Start (Area, Expand => True, Fill => True);

      Gtk_New (Status, "");
      Status.Set_Halign (Gtk.Widget.Align_Start);
      Status.Set_Ellipsize (Pango.Layout.Ellipsize_End);
      Status.Set_Margin_Start (6);
      VBox.Pack_Start (Status, Expand => False, Fill => False, Padding => 2);

      Surf := Cairo.Image_Surface.Create
        (Cairo.Image_Surface.Cairo_Format_RGB24,
         Gint (Blit.Width), Gint (Blit.Height));

      Sound.Sink := Audio.Push'Access;
      Monitor.On_Change := Refresh_Screen'Access;
      Forge.Refresh_Screen := Refresh_Screen'Access;
      Forge.Show_Emulator := Show_Emulator'Access;
      Audio.Start;

      Updating_Menu := True;
      Joy_Items (Keyboard.Joystick).Set_Active (True);
      if Settings.Get ("joykeys", "keypad") = "cursor" then
         Keyboard.Joystick_Keys := Keyboard.Cursor_Keys;
         Keyset_Cursor.Set_Active (True);
      else
         Keyset_Keypad.Set_Active (True);
      end if;
      declare
         Wanted : constant String := Settings.Get ("controller", "");
         Dev : Integer :=
           (if Wanted = "" then Host_Joystick.Auto_Select
            elsif Wanted = "none" then -1
            else Host_Joystick.Find (Wanted));
      begin
         if Wanted /= "" and then Wanted /= "none" and then Dev < 0 then
            Dev := Host_Joystick.Auto_Select;
         end if;
         if Dev >= 0 then
            Host_Joystick.Open (Dev);
            Host_Items (Dev).Set_Active (True);
         else
            Host_Items (-1).Set_Active (True);
         end if;
      end;
      Mute.Set_Active (Audio.Muted);
      Item_Pos.Set_Active (Keyboard.Positional);
      Item_Int.Set_Active (Integer_Scale);
      Item_CRT.Set_Active (Video.Scanlines);
      Updating_Menu := False;

      Start_Machine (Start_Model);
      if Attach /= "" then
         declare
            Ok : Boolean;
         begin
            Machine.Attach_Tape (Attach, Ok);
         end;
      end if;
      if File /= "" then
         Do_Autostart (File);
      end if;
      Sync_Menu;

      Win.Show_All;
      if Open_Forge then
         Win.Set_Title ("AdaZX (forge)");
         Forge.Quit_App := Quit_App'Access;
         Forge.Open (Win, To_String (Forge_File));
      end if;
      Timer := Timer_Sources.Timeout_Add
        (4, On_Timer_Data'Access, 0, Priority => 130);
      Gtk.Main.Main;
      Machine.Shutdown;
      Audio.Stop;
   end Run;

end GUI;
