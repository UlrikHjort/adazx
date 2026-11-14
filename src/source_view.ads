-- ***************************************************************************
--                           AdaZX - Source_View
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
--  Minimal binding to GtkSourceView 4 (code editor widget) for the forge.
--  The view and buffer are ordinary GtkTextView / GtkTextBuffer objects
--  to GtkAda, so all of Gtk.Text_View and Gtk.Text_Buffer apply.

with Gtk.Text_View;
with Gtk.Text_Buffer;
with Gtk.Text_Iter;

package Source_View is

   procedure Init (Language_Dir : String);
   --  Add Language_Dir (holding z80asm.lang) to the language search
   --  path; call once before creating views.

   type Language is (Assembly, Basic_Text);
   procedure Gtk_New (View   : out Gtk.Text_View.Gtk_Text_View;
                      Buffer : out Gtk.Text_Buffer.Gtk_Text_Buffer;
                      Lang   : Language := Assembly);
   --  A source view with Z80 assembly or Sinclair BASIC highlighting,
   --  line numbers and a mark gutter.

   procedure Set_Dark (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer;
                       Dark : Boolean);

   --  Line marks (shown in the gutter): breakpoints and the current PC
   type Mark_Kind is (Breakpoint, Current_PC, Error_Line);
   procedure Add_Mark (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer;
                       Kind : Mark_Kind; Line : Natural);   --  0-based
   procedure Clear_Marks (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer;
                          Kind : Mark_Kind);
   function Has_Mark (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer;
                      Kind : Mark_Kind; Line : Natural) return Boolean;
   procedure Remove_Marks_At (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer;
                              Kind : Mark_Kind; Line : Natural);
   type Line_Proc is access procedure (Line : Natural);
   procedure For_Each_Mark (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer;
                            Kind : Mark_Kind; Proc : not null Line_Proc);
   --  Lines (0-based, ascending) carrying a mark of that kind; marks move
   --  with the text when it is edited.

   type Gutter_Click is access procedure
     (View : Gtk.Text_View.Gtk_Text_View; Line : Natural);
   On_Gutter_Click : Gutter_Click := null;
   --  Called when the user clicks a line in the mark gutter.

   procedure Begin_Not_Undoable (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer);
   procedure End_Not_Undoable (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer);
   procedure Undo (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer);
   procedure Redo (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer);

   function Iter_Line (Iter : Gtk.Text_Iter.Gtk_Text_Iter) return Natural;

end Source_View;
