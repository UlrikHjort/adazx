-- ***************************************************************************
--                             AdaZX - Monitor
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
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with Gtk.Box; use Gtk.Box;
with Gtk.GEntry; use Gtk.GEntry;
with Gtk.Scrolled_Window; use Gtk.Scrolled_Window;
with Gtk.Text_Buffer; use Gtk.Text_Buffer;
with Gtk.Text_Iter; use Gtk.Text_Iter;
with Gtk.Text_View; use Gtk.Text_View;
with Gtk.Widget; use Gtk.Widget;
with Gtk.Enums;
with Gdk.Event;
with Gtk.Window;
use type Gtk.Window.Gtk_Window;
with Pango.Font;

with Machine;
with Monitor_Commands;

package body Monitor is

   Win     : Gtk.Window.Gtk_Window := null;
   View    : Gtk_Text_View;
   Buffer  : Gtk_Text_Buffer;
   Command : Gtk_Entry;
   Is_Active : Boolean := False;

   function Active return Boolean is (Is_Active);

   procedure Print (S : String) is
      Iter : Gtk_Text_Iter;
   begin
      Buffer.Get_End_Iter (Iter);
      Buffer.Insert (Iter, S & ASCII.LF);
      Buffer.Get_End_Iter (Iter);
      Buffer.Place_Cursor (Iter);
      View.Scroll_To_Mark (Buffer.Get_Insert, 0.0, False, 0.0, 1.0);
   end Print;

   procedure Changed is
   begin
      if On_Change /= null then
         On_Change.all;
      end if;
   end Changed;

   procedure On_Command (Self : access Gtk_Entry_Record'Class) is
      Line : constant String := Trim (Self.Get_Text, Ada.Strings.Both);
   begin
      Self.Set_Text ("");
      Monitor_Commands.Resume_Requested := False;
      Monitor_Commands.Execute (Line);
      if Monitor_Commands.Resume_Requested then
         Is_Active := False;
         Win.Hide;
      end if;
   end On_Command;

   function On_Delete (Self : access Gtk_Widget_Record'Class;
                       Event : Gdk.Event.Gdk_Event) return Boolean is
      pragma Unreferenced (Self, Event);
   begin
      Machine.Resume;
      Is_Active := False;
      Win.Hide;
      return True;      --  keep the window for reuse
   end On_Delete;

   procedure Build (Parent : Gtk.Window.Gtk_Window) is
      Box : Gtk_Box;
      Scroll : Gtk_Scrolled_Window;
   begin
      Gtk.Window.Gtk_New (Win);
      Win.Set_Title ("AdaZX monitor");
      Win.Set_Default_Size (760, 480);
      Win.Set_Transient_For (Parent);
      Win.On_Delete_Event (On_Delete'Access);

      Gtk_New_Vbox (Box);
      Win.Add (Box);

      Gtk_New (Scroll);
      Scroll.Set_Policy (Gtk.Enums.Policy_Automatic, Gtk.Enums.Policy_Always);
      Box.Pack_Start (Scroll, Expand => True, Fill => True);

      Gtk_New (Buffer);
      Gtk_New (View, Buffer);
      View.Set_Editable (False);
      View.Modify_Font (Pango.Font.From_String ("Monospace 10"));
      Scroll.Add (View);

      Gtk_New (Command);
      Command.Modify_Font (Pango.Font.From_String ("Monospace 10"));
      Command.On_Activate (On_Command'Access);
      Box.Pack_Start (Command, Expand => False, Fill => False);
      Monitor_Commands.Output := Print'Access;
      Monitor_Commands.On_Change := Changed'Access;
      Print ("AdaZX monitor - h for help");
   end Build;

   procedure Open (Parent : Gtk.Window.Gtk_Window; Reason : String := "") is
   begin
      if Win = null then
         Build (Parent);
      end if;
      Is_Active := True;
      if Reason /= "" then
         Print ("*** " & Reason);
      end if;
      Monitor_Commands.Show_Registers;
      Win.Show_All;
      Win.Present;
      Command.Grab_Focus;
   end Open;

end Monitor;
