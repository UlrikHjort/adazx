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
with System; use System;
with Interfaces.C; use Interfaces.C;
with Interfaces.C.Strings; use Interfaces.C.Strings;
with Glib; use Glib;
with Glib.Object;
with Gtk.Text_Iter; use Gtk.Text_Iter;
with Gtk.Text_View; use Gtk.Text_View;
with Gtk.Text_Buffer; use Gtk.Text_Buffer;

package body Source_View is

   subtype Ptr is System.Address;

   function LM_Default return Ptr;
   pragma Import (C, LM_Default, "gtk_source_language_manager_get_default");
   procedure LM_Set_Search_Path (LM : Ptr; Dirs : Ptr);
   pragma Import (C, LM_Set_Search_Path,
                  "gtk_source_language_manager_set_search_path");
   function LM_Get_Language (LM : Ptr; Id : chars_ptr) return Ptr;
   pragma Import (C, LM_Get_Language,
                  "gtk_source_language_manager_get_language");

   function Buffer_New (Lang : Ptr) return Ptr;
   pragma Import (C, Buffer_New, "gtk_source_buffer_new_with_language");
   function Buffer_New_Plain (Table : Ptr) return Ptr;
   pragma Import (C, Buffer_New_Plain, "gtk_source_buffer_new");
   function View_New (Buffer : Ptr) return Ptr;
   pragma Import (C, View_New, "gtk_source_view_new_with_buffer");

   procedure Set_Show_Line_Numbers (V : Ptr; B : Gboolean);
   pragma Import (C, Set_Show_Line_Numbers,
                  "gtk_source_view_set_show_line_numbers");
   procedure Set_Show_Line_Marks (V : Ptr; B : Gboolean);
   pragma Import (C, Set_Show_Line_Marks,
                  "gtk_source_view_set_show_line_marks");
   procedure Set_Highlight_Line (V : Ptr; B : Gboolean);
   pragma Import (C, Set_Highlight_Line,
                  "gtk_source_view_set_highlight_current_line");
   procedure Set_Auto_Indent (V : Ptr; B : Gboolean);
   pragma Import (C, Set_Auto_Indent, "gtk_source_view_set_auto_indent");
   procedure Set_Tab_Width (V : Ptr; W : Guint);
   pragma Import (C, Set_Tab_Width, "gtk_source_view_set_tab_width");
   procedure Set_Insert_Spaces (V : Ptr; B : Gboolean);
   pragma Import (C, Set_Insert_Spaces,
                  "gtk_source_view_set_insert_spaces_instead_of_tabs");
   procedure Set_Indent_Width (V : Ptr; W : Gint);
   pragma Import (C, Set_Indent_Width, "gtk_source_view_set_indent_width");

   function Attrs_New return Ptr;
   pragma Import (C, Attrs_New, "gtk_source_mark_attributes_new");
   type RGBA is record
      R, G, B, A : double;
   end record;
   pragma Convention (C, RGBA);
   procedure Attrs_Set_Background (A : Ptr; C : access constant RGBA);
   pragma Import (C, Attrs_Set_Background,
                  "gtk_source_mark_attributes_set_background");
   procedure Attrs_Set_Icon_Name (A : Ptr; Name : chars_ptr);
   pragma Import (C, Attrs_Set_Icon_Name,
                  "gtk_source_mark_attributes_set_icon_name");
   procedure View_Set_Mark_Attributes (V : Ptr; Category : chars_ptr;
                                       A : Ptr; Priority : Gint);
   pragma Import (C, View_Set_Mark_Attributes,
                  "gtk_source_view_set_mark_attributes");

   function Create_Source_Mark (B : Ptr; Name : chars_ptr;
                                Category : chars_ptr; Iter : Ptr) return Ptr;
   pragma Import (C, Create_Source_Mark,
                  "gtk_source_buffer_create_source_mark");
   procedure Remove_Source_Marks (B : Ptr; From, To : Ptr;
                                  Category : chars_ptr);
   pragma Import (C, Remove_Source_Marks,
                  "gtk_source_buffer_remove_source_marks");

   function Marks_At_Line (B : Ptr; Line : Gint; Category : chars_ptr)
                           return Ptr;
   pragma Import (C, Marks_At_Line, "gtk_source_buffer_get_source_marks_at_line");
   procedure G_Slist_Free (L : Ptr);
   pragma Import (C, G_Slist_Free, "g_slist_free");
   function Forward_To_Mark (B : Ptr; Iter : Ptr; Category : chars_ptr)
                             return Gboolean;
   pragma Import (C, Forward_To_Mark,
                  "gtk_source_buffer_forward_iter_to_source_mark");

   function Scheme_Manager return Ptr;
   pragma Import (C, Scheme_Manager,
                  "gtk_source_style_scheme_manager_get_default");
   function Get_Scheme (M : Ptr; Id : chars_ptr) return Ptr;
   pragma Import (C, Get_Scheme, "gtk_source_style_scheme_manager_get_scheme");
   procedure Set_Style_Scheme (B : Ptr; S : Ptr);
   pragma Import (C, Set_Style_Scheme, "gtk_source_buffer_set_style_scheme");

   procedure C_Begin_Not_Undoable (B : Ptr);
   pragma Import (C, C_Begin_Not_Undoable,
                  "gtk_source_buffer_begin_not_undoable_action");
   procedure C_End_Not_Undoable (B : Ptr);
   pragma Import (C, C_End_Not_Undoable,
                  "gtk_source_buffer_end_not_undoable_action");
   procedure C_Undo (B : Ptr);
   pragma Import (C, C_Undo, "gtk_source_buffer_undo");
   procedure C_Redo (B : Ptr);
   pragma Import (C, C_Redo, "gtk_source_buffer_redo");

   function Signal_Connect (Instance : Ptr; Signal : chars_ptr;
                            Handler : Ptr; Data : Ptr;
                            Destroy : Ptr; Flags : int) return unsigned_long;
   pragma Import (C, Signal_Connect, "g_signal_connect_data");

   --  Category names
   Cat : constant array (Mark_Kind) of chars_ptr :=
     (New_String ("breakpoint"), New_String ("pc"), New_String ("error"));

   --  Views created here, to map the C instance back to the Ada object
   Max_Views : constant := 64;
   Views : array (1 .. Max_Views) of Gtk_Text_View;
   View_Count : Natural := 0;

   Langs : array (Language) of Ptr := (others => Null_Address);
   Dummy_Bool : Boolean;

   procedure Init (Language_Dir : String) is
      LM : constant Ptr := LM_Default;
      type Path_Array is array (1 .. 3) of chars_ptr;
      pragma Convention (C, Path_Array);
      Paths : aliased Path_Array :=
        (New_String (Language_Dir),
         New_String ("/usr/share/gtksourceview-4/language-specs"),
         Null_Ptr);
   begin
      LM_Set_Search_Path (LM, Paths'Address);
      Langs (Assembly) := LM_Get_Language (LM, New_String ("z80asm"));
      Langs (Basic_Text) := LM_Get_Language (LM, New_String ("sinclairbasic"));
   end Init;

   procedure On_Mark_Activated (V : Ptr; Iter : access Gtk_Text_Iter;
                                Event : Ptr; Data : Ptr);
   pragma Convention (C, On_Mark_Activated);

   procedure On_Mark_Activated (V : Ptr; Iter : access Gtk_Text_Iter;
                                Event : Ptr; Data : Ptr) is
      pragma Unreferenced (Event, Data);
   begin
      if On_Gutter_Click = null then
         return;
      end if;
      for I in 1 .. View_Count loop
         if Views (I).Get_Object = V then
            On_Gutter_Click (Views (I), Natural (Get_Line (Iter.all)));
            return;
         end if;
      end loop;
   end On_Mark_Activated;

   procedure Gtk_New (View   : out Gtk.Text_View.Gtk_Text_View;
                      Buffer : out Gtk.Text_Buffer.Gtk_Text_Buffer;
                      Lang   : Language := Assembly) is
      B : constant Ptr :=
        (if Langs (Lang) /= Null_Address then Buffer_New (Langs (Lang))
         else Buffer_New_Plain (Null_Address));
      V : constant Ptr := View_New (B);
      Dummy : unsigned_long;

      procedure Attrs (K : Mark_Kind; Icon : String; Color : RGBA;
                       Priority : Gint) is
         A : constant Ptr := Attrs_New;
         C : aliased constant RGBA := Color;
      begin
         Attrs_Set_Background (A, C'Access);
         Attrs_Set_Icon_Name (A, New_String (Icon));
         View_Set_Mark_Attributes (V, Cat (K), A, Priority);
      end Attrs;
   begin
      Buffer := new Gtk_Text_Buffer_Record;
      Glib.Object.Set_Object (Buffer, B);
      View := new Gtk_Text_View_Record;
      Glib.Object.Set_Object (View, V);

      Set_Show_Line_Numbers (V, 1);
      Set_Show_Line_Marks (V, 1);
      Set_Highlight_Line (V, 1);
      Set_Auto_Indent (V, 1);
      Set_Tab_Width (V, 8);
      Set_Indent_Width (V, 8);
      Set_Insert_Spaces (V, 1);
      Attrs (Breakpoint, "media-record", (0.95, 0.70, 0.70, 1.0), 1);
      Attrs (Error_Line, "dialog-error", (1.0, 0.85, 0.75, 1.0), 2);
      Attrs (Current_PC, "go-next", (1.0, 0.95, 0.55, 1.0), 3);
      Dummy := Signal_Connect (V, New_String ("line-mark-activated"),
                               On_Mark_Activated'Address, Null_Address,
                               Null_Address, 0);
      if View_Count < Max_Views then
         View_Count := View_Count + 1;
         Views (View_Count) := View;
      end if;
   end Gtk_New;

   procedure Set_Dark (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer;
                       Dark : Boolean) is
      S : constant Ptr := Get_Scheme
        (Scheme_Manager, New_String (if Dark then "oblivion" else "classic"));
   begin
      if S /= Null_Address then
         Set_Style_Scheme (Buffer.Get_Object, S);
      end if;
   end Set_Dark;

   procedure Add_Mark (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer;
                       Kind : Mark_Kind; Line : Natural) is
      Iter : aliased Gtk_Text_Iter;
      Dummy : Ptr;
   begin
      Buffer.Get_Iter_At_Line (Iter, Gint (Line));
      Dummy := Create_Source_Mark (Buffer.Get_Object, Null_Ptr, Cat (Kind),
                                   Iter'Address);
   end Add_Mark;

   procedure Clear_Marks (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer;
                          Kind : Mark_Kind) is
      From, To : aliased Gtk_Text_Iter;
   begin
      Buffer.Get_Start_Iter (From);
      Buffer.Get_End_Iter (To);
      Remove_Source_Marks (Buffer.Get_Object, From'Address, To'Address,
                           Cat (Kind));
   end Clear_Marks;

   function Has_Mark (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer;
                      Kind : Mark_Kind; Line : Natural) return Boolean is
      L : constant Ptr := Marks_At_Line (Buffer.Get_Object, Gint (Line),
                                         Cat (Kind));
   begin
      if L = Null_Address then
         return False;
      end if;
      G_Slist_Free (L);
      return True;
   end Has_Mark;

   procedure Remove_Marks_At (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer;
                              Kind : Mark_Kind; Line : Natural) is
      From, To : aliased Gtk_Text_Iter;
   begin
      Buffer.Get_Iter_At_Line (From, Gint (Line));
      Copy (From, To);
      if not Ends_Line (To) then
         Forward_To_Line_End (To, Dummy_Bool);
      end if;
      Remove_Source_Marks (Buffer.Get_Object, From'Address, To'Address,
                           Cat (Kind));
   end Remove_Marks_At;

   procedure For_Each_Mark (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer;
                            Kind : Mark_Kind; Proc : not null Line_Proc) is
      Iter : aliased Gtk_Text_Iter;
      Last : Integer := -1;
   begin
      if Has_Mark (Buffer, Kind, 0) then
         Proc (0);
         Last := 0;
      end if;
      Buffer.Get_Start_Iter (Iter);
      while Forward_To_Mark (Buffer.Get_Object, Iter'Address, Cat (Kind)) /= 0
      loop
         declare
            L : constant Natural := Natural (Get_Line (Iter));
         begin
            if L /= Last then
               Proc (L);
               Last := L;
            end if;
         end;
      end loop;
   end For_Each_Mark;

   procedure Begin_Not_Undoable (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer) is
   begin
      C_Begin_Not_Undoable (Buffer.Get_Object);
   end Begin_Not_Undoable;

   procedure End_Not_Undoable (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer) is
   begin
      C_End_Not_Undoable (Buffer.Get_Object);
   end End_Not_Undoable;

   procedure Undo (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer) is
   begin
      C_Undo (Buffer.Get_Object);
   end Undo;

   procedure Redo (Buffer : Gtk.Text_Buffer.Gtk_Text_Buffer) is
   begin
      C_Redo (Buffer.Get_Object);
   end Redo;

   function Iter_Line (Iter : Gtk.Text_Iter.Gtk_Text_Iter) return Natural is
     (Natural (Get_Line (Iter)));

end Source_View;
