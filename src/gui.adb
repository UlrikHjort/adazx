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
   Item_16K, Item_2000, Item_Issue2 : Gtk_Check_Menu_Item;
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
         (if Machine.Model = Config.ZX81
          then (if Machine.ZX81_16K then " 16K" else " 1K") else "") &
         (if T /= "" then "  |  tape: " & Short (T) &
            (if Machine.Tape_Motor
             then " (playing, block" & Tape.Current_Block'Image & "/" &
               Tape.Block_Count'Image & ")"
             else "") else "") &
         (if Machine.Model /= Config.ZX81
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
      Item_Issue2.Set_Active (Machine.Issue_2);
      Model_Items (Machine.Model).Set_Active (True);
      Updating_Menu := False;
      if Machine.Model /= Config.ZX81 then
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
     ("tap", "tzx", "z80", "szx", "sna", "azx", "rzx", "p  ", "81 ", "scr",
      "bas", "asm");
   Tape_Types : constant Ext_List := ("tap", "tzx", "p  ", "81 ");
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
                       "Spectrum and ZX81 files (tap, tzx, z80, sna, p, ...)"));
   end On_Autostart;

   procedure On_Attach_Tape (Item : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (Item);
      Path : constant String :=
        Choose_File ("Insert tape", Tape_Types, "Tapes (tap, tzx, p, 81)");
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
                             (if Machine.Is_ZX81 then "recording.p"
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
      if Gtk_Check_Menu_Item (Item) /= Item_Issue2
        and then Machine.Model = Config.ZX81
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
         when Config.Plus2 => "plus2", when Config.Plus2A => "plus2a",
         when Config.Plus3 => "plus3", when Config.ZX81 => "zx81");

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
      Settings.Set ("issue2", Machine.Issue_2);
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
      Machine.Issue_2 := Settings.Get ("issue2", Machine.Issue_2);
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
      Add_Check (M_Machine, "ZX81: 16K RAM pack", Item_16K,
                 On_ZX81_Option'Access);
      Add_Check (M_Machine, "ZX81: 8K RAM at &2000 (hi-res)", Item_2000,
                 On_ZX81_Option'Access);
      Add_Check (M_Machine, "48K: issue 2 keyboard", Item_Issue2,
                 On_ZX81_Option'Access);
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
