-- ***************************************************************************
--                              AdaZX - Forge
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
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Directories;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Streams.Stream_IO;
with Ada.Command_Line;

with Glib; use Glib;
with Glib.Unicode;
with Glib.Properties;
with Gdk.Types; use Gdk.Types;
with Gdk.Types.Keysyms; use Gdk.Types.Keysyms;
with Gdk.Event;
with Gtk.Accel_Group; use Gtk.Accel_Group;
with Gtk.Box; use Gtk.Box;
with Gtk.Dialog; use Gtk.Dialog;
with Gtk.Enums; use Gtk.Enums;
with Gtk.File_Chooser;
with Gtk.File_Chooser_Dialog; use Gtk.File_Chooser_Dialog;
with Gtk.File_Filter; use Gtk.File_Filter;
with Gtk.Frame; use Gtk.Frame;
with Gtk.GEntry; use Gtk.GEntry;
with Gtk.Label; use Gtk.Label;
with Gtk.Menu; use Gtk.Menu;
with Gtk.Menu_Bar; use Gtk.Menu_Bar;
with Gtk.Menu_Item; use Gtk.Menu_Item;
with Gtk.Message_Dialog; use Gtk.Message_Dialog;
with Gtk.Notebook; use Gtk.Notebook;
with Gtk.Paned; use Gtk.Paned;
with Gtk.Scrolled_Window; use Gtk.Scrolled_Window;
with Gtk.Separator_Menu_Item; use Gtk.Separator_Menu_Item;
with Gtk.Settings;
with Gtk.Text_Buffer; use Gtk.Text_Buffer;
with Gtk.Text_Iter; use Gtk.Text_Iter;
with Gtk.Text_View; use Gtk.Text_View;
with Gtk.Tool_Button; use Gtk.Tool_Button;
with Gtk.Separator_Tool_Item; use Gtk.Separator_Tool_Item;
with Gtk.Toolbar; use Gtk.Toolbar;
with Gtk.Widget; use Gtk.Widget;
with Gtk.Window; use Gtk.Window;
with Pango.Font;
with Pango.Layout;
with GNAT.Strings;

with Types; use Types;
with Machine;
use type Machine.Model_Type;
with Asm;
with Basic;
use type Basic.Dialect;
with Disasm;
with Settings;
with Source_View;
with UDG_Editor;
with Screen_Editor;
with ZX81_Editor;
use type Source_View.Language;
with Interfaces; use Interfaces;

package body Forge is



   ---------------------------------------------------------------------
   --  Widgets and state
   ---------------------------------------------------------------------

   Win      : Gtk_Window := null;
   Parent_W : Gtk_Window := null;
   Book     : Gtk_Notebook;
   Out_View : Gtk_Text_View;
   Out_Buf  : Gtk_Text_Buffer;
   Regs     : Gtk_Label;
   Dis_Buf  : Gtk_Text_Buffer;
   Mem_Buf  : Gtk_Text_Buffer;
   Mem_Addr : Gtk_Entry;
   Watch_E  : Gtk_Entry;
   Watch_L  : Gtk_Label;
   Status   : Gtk_Label;

   Max_Tabs : constant := 32;
   type Tab is record
      Used   : Boolean := False;
      View   : Gtk_Text_View;
      Buffer : Gtk_Text_Buffer;
      Scroll : Gtk_Scrolled_Window;
      Label  : Gtk_Label;
      Path   : Unbounded_String;
      Lang   : Source_View.Language := Source_View.Assembly;
   end record;
   Tabs : array (1 .. Max_Tabs) of Tab;

   Main_File   : Unbounded_String;    --  file that is assembled
   Stop_Shown  : Boolean := False;
   Built       : Boolean := False;    --  debug info is current
   type Program_Kind is (No_Program, Asm_Program, Basic_Program);
   Last_Kind   : Program_Kind := No_Program;
   Basic_File  : Unbounded_String;    --  last tokenized BASIC source
   Basic_Line  : Integer := -1;       --  BASIC line shown as running
   Last_PRG    : Unbounded_String;    --  the program the last build wrote
   Last_Source : Unbounded_String;    --  ... and its main source file
   Last_Basic_Check : Time := Clock;
   Last_Update : Time := Clock;
   Stop_Cycles : Long_Long_Integer := 0;
   Mono : constant String := "Monospace 10";

   function Is_Open return Boolean is
     (Win /= null and then Win.Get_Visible);

   procedure Print (S : String) is
      Iter : Gtk_Text_Iter;
   begin
      Out_Buf.Get_End_Iter (Iter);
      Out_Buf.Insert (Iter, S & ASCII.LF);
      Out_Buf.Get_End_Iter (Iter);
      Out_Buf.Place_Cursor (Iter);
      Out_View.Scroll_To_Mark (Out_Buf.Get_Insert, 0.0, False, 0.0, 1.0);
   end Print;

   procedure Set_Status (S : String) is
   begin
      Status.Set_Text (S);
   end Set_Status;

   function Hex4 (W : Word) return String renames Disasm.Hex4;
   function Hex2 (B : Byte) return String renames Disasm.Hex2;

   function Base_Name (P : String) return String is
     (if P = "" then "untitled" else Ada.Directories.Simple_Name (P));

   ---------------------------------------------------------------------
   --  Tabs and files
   ---------------------------------------------------------------------

   function Current_Tab return Natural is
      Page : constant Gint := Book.Get_Current_Page;
   begin
      for I in Tabs'Range loop
         if Tabs (I).Used and then Book.Page_Num (Tabs (I).Scroll) = Page
         then
            return I;
         end if;
      end loop;
      return 0;
   end Current_Tab;

   function Find_Tab (Path : String) return Natural is
   begin
      for I in Tabs'Range loop
         if Tabs (I).Used and then To_String (Tabs (I).Path) = Path then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Tab;

   function Tab_Of_Buffer (B : Gtk_Text_Buffer) return Natural is
   begin
      for I in Tabs'Range loop
         if Tabs (I).Used and then Tabs (I).Buffer = B then
            return I;
         end if;
      end loop;
      return 0;
   end Tab_Of_Buffer;

   procedure Update_Label (T : Positive) is
      Name : constant String := Base_Name (To_String (Tabs (T).Path));
      Main : constant Boolean :=
        Tabs (T).Path /= Null_Unbounded_String
        and then Tabs (T).Path = Main_File;
   begin
      Tabs (T).Label.Set_Text
        ((if Tabs (T).Buffer.Get_Modified then "*" else "") & Name &
         (if Main then " (main)" else ""));
   end Update_Label;

   procedure Update_Title is
   begin
      Win.Set_Title ("AdaZX Forge - " &
                     (if Main_File = Null_Unbounded_String then "no project"
                      else To_String (Main_File)));
      for I in Tabs'Range loop
         if Tabs (I).Used then
            Update_Label (I);
         end if;
      end loop;
   end Update_Title;

   procedure On_Modified (Self : access Gtk_Text_Buffer_Record'Class) is
      T : constant Natural := Tab_Of_Buffer (Gtk_Text_Buffer (Self));
   begin
      if T > 0 then
         Update_Label (T);
      end if;
   end On_Modified;

   function Read_File (Path : String; Ok : out Boolean) return String is
      use Ada.Streams.Stream_IO;
      F : File_Type;
   begin
      Open (F, In_File, Path);
      declare
         N : constant Natural := Natural (Size (F));
         S : String (1 .. N);
      begin
         String'Read (Stream (F), S);
         Close (F);
         Ok := True;
         declare
            Valid : Boolean;
            Invalid_Index : Natural;
         begin
            Glib.Unicode.UTF8_Validate (S, Valid, Invalid_Index);
            if Valid then
               return S;
            end if;
         end;
         --  Not UTF-8: treat as Latin-1
         declare
            R : Unbounded_String;
         begin
            for C of S loop
               if Character'Pos (C) < 128 then
                  Append (R, C);
               else
                  Append (R, Character'Val (16#C0# + Character'Pos (C) / 64));
                  Append (R, Character'Val (16#80# + Character'Pos (C) mod 64));
               end if;
            end loop;
            return To_String (R);
         end;
      end;
   exception
      when others =>
         Ok := False;
         return "";
   end Read_File;

   function Buffer_Text (B : Gtk_Text_Buffer) return String is
      From, To : Gtk_Text_Iter;
   begin
      B.Get_Start_Iter (From);
      B.Get_End_Iter (To);
      return B.Get_Text (From, To, True);
   end Buffer_Text;

   function Write_File (Path, Text : String) return Boolean is
      use Ada.Streams.Stream_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      String'Write (Stream (F), Text);
      Close (F);
      return True;
   exception
      when others =>
         return False;
   end Write_File;

   function New_Tab (Path : String; Text : String;
                     Is_Basic : Boolean := False) return Natural is
      T : Natural := 0;
      Dummy : Gint;
   begin
      for I in Tabs'Range loop
         if not Tabs (I).Used then
            T := I;
            exit;
         end if;
      end loop;
      if T = 0 then
         Print ("too many open files");
         return 0;
      end if;
      Tabs (T).Used := True;
      Tabs (T).Path := To_Unbounded_String (Path);
      Tabs (T).Lang :=
        (if Is_Basic or else Basic.Is_Source (Path)
         then Source_View.Basic_Text else Source_View.Assembly);
      Source_View.Gtk_New (Tabs (T).View, Tabs (T).Buffer, Tabs (T).Lang);
      Tabs (T).View.Modify_Font (Pango.Font.From_String ("Monospace 11"));
      Source_View.Begin_Not_Undoable (Tabs (T).Buffer);
      Tabs (T).Buffer.Set_Text (Text);
      Source_View.End_Not_Undoable (Tabs (T).Buffer);
      Tabs (T).Buffer.Set_Modified (False);
      declare
         Start : Gtk_Text_Iter;
      begin
         Tabs (T).Buffer.Get_Start_Iter (Start);
         Tabs (T).Buffer.Place_Cursor (Start);
      end;
      Tabs (T).Buffer.On_Modified_Changed (On_Modified'Access);
      Gtk_New (Tabs (T).Scroll);
      Tabs (T).Scroll.Add (Tabs (T).View);
      Gtk_New (Tabs (T).Label, "");
      Dummy := Book.Append_Page (Tabs (T).Scroll, Tabs (T).Label);
      Tabs (T).Scroll.Show_All;
      Book.Set_Current_Page (Book.Page_Num (Tabs (T).Scroll));
      Update_Label (T);
      Tabs (T).View.Grab_Focus;
      return T;
   end New_Tab;

   function Open_Path (Path : String) return Natural is
      T : Natural := Find_Tab (Path);
      Ok : Boolean;
   begin
      if T = 0 then
         declare
            Text : constant String := Read_File (Path, Ok);
         begin
            if not Ok then
               Print ("cannot open " & Path);
               return 0;
            end if;
            T := New_Tab (Path, Text);
         end;
      end if;
      if T > 0 then
         Book.Set_Current_Page (Book.Page_Num (Tabs (T).Scroll));
         Tabs (T).View.Grab_Focus;
         if Main_File = Null_Unbounded_String then
            Main_File := To_Unbounded_String (Path);
            Update_Title;
         end if;
      end if;
      return T;
   end Open_Path;

   procedure Goto_Line (T : Positive; Line : Positive) is
      Iter : Gtk_Text_Iter;
   begin
      Tabs (T).Buffer.Get_Iter_At_Line (Iter, Gint (Line - 1));
      Tabs (T).Buffer.Place_Cursor (Iter);
      Tabs (T).View.Scroll_To_Mark (Tabs (T).Buffer.Get_Insert, 0.1, True,
                                    0.0, 0.4);
   end Goto_Line;

   function Cursor_Line (T : Positive) return Positive is
      Iter : Gtk_Text_Iter;
   begin
      Tabs (T).Buffer.Get_Iter_At_Mark (Iter, Tabs (T).Buffer.Get_Insert);
      return Natural (Get_Line (Iter)) + 1;
   end Cursor_Line;

   function Choose_File (Title : String; Save : Boolean;
                         Name : String := "";
                         PRG_Files : Boolean := False) return String is
      Dlg : Gtk_File_Chooser_Dialog;
      W : Gtk_Widget;
      Filter_Src, Filter_All : Gtk_File_Filter;
      Result : Unbounded_String;
      pragma Unreferenced (W);
      Last : constant String := Settings.Get ("forge_dir", Settings.Get ("studio_dir", ""));
   begin
      Gtk_New (Dlg, Title, Win,
               (if Save then Gtk.File_Chooser.Action_Save
                else Gtk.File_Chooser.Action_Open));
      W := Dlg.Add_Button ("_Cancel", Gtk_Response_Cancel);
      W := Dlg.Add_Button ((if Save then "_Save" else "_Open"),
                           Gtk_Response_Accept);
      Gtk_New (Filter_Src);
      if PRG_Files then
         Filter_Src.Set_Name ("Tapes with BASIC (.tap, .p)");
         Filter_Src.Add_Pattern ("*.tap");
         Filter_Src.Add_Pattern ("*.p");
      else
         Filter_Src.Set_Name ("Sources (assembly, BASIC)");
         for P of GNAT.Strings.String_List'
           (new String'("*.asm"), new String'("*.z80s"), new String'("*.s"),
            new String'("*.a80"), new String'("*.inc"), new String'("*.bas"),
            new String'("*.zxb"), new String'("*.b81"), new String'("*.udg"),
            new String'("*.scr"), new String'("*.zxs"), new String'("*.z81s"),
            new String'("*.png"))
         loop
            Filter_Src.Add_Pattern (P.all);
         end loop;
      end if;
      Gtk_New (Filter_All);
      Filter_All.Set_Name ("All files");
      Filter_All.Add_Pattern ("*");
      Gtk.File_Chooser.Add_Filter (+Dlg, Filter_Src);
      Gtk.File_Chooser.Add_Filter (+Dlg, Filter_All);
      if Save then
         Gtk.File_Chooser.Set_Do_Overwrite_Confirmation (+Dlg, True);
         Gtk.File_Chooser.Set_Current_Name
           (+Dlg, (if Name = "" then "program.asm" else Name));
      end if;
      if Last /= "" then
         declare
            Dummy : constant Boolean :=
              Gtk.File_Chooser.Set_Current_Folder (+Dlg, Last);
         begin
            null;
         end;
      end if;
      if Dlg.Run = Gtk_Response_Accept then
         Result := To_Unbounded_String (Gtk.File_Chooser.Get_Filename (+Dlg));
         Settings.Set ("forge_dir", Ada.Directories.Containing_Directory
                         (To_String (Result)));
      end if;
      Dlg.Destroy;
      return To_String (Result);
   end Choose_File;

   function Save_Tab (T : Positive; Ask : Boolean := False) return Boolean is
   begin
      if Ask or else Tabs (T).Path = Null_Unbounded_String then
         declare
            P : constant String :=
              Choose_File ("Save source", True,
                           (if Tabs (T).Path /= Null_Unbounded_String
                            then Base_Name (To_String (Tabs (T).Path))
                            elsif Tabs (T).Lang = Source_View.Basic_Text
                            then "program.bas" else "program.asm"));
         begin
            if P = "" then
               return False;
            end if;
            if Main_File = Tabs (T).Path then
               Main_File := To_Unbounded_String (P);
            end if;
            Tabs (T).Path := To_Unbounded_String (P);
            if Main_File = Null_Unbounded_String then
               Main_File := To_Unbounded_String (P);
            end if;
         end;
      end if;
      if not Write_File (To_String (Tabs (T).Path),
                         Buffer_Text (Tabs (T).Buffer))
      then
         Print ("cannot write " & To_String (Tabs (T).Path));
         return False;
      end if;
      Tabs (T).Buffer.Set_Modified (False);
      Update_Title;
      return True;
   end Save_Tab;

   function Save_All return Boolean is
   begin
      for I in Tabs'Range loop
         if Tabs (I).Used
           and then (Tabs (I).Buffer.Get_Modified
                     or else Tabs (I).Path = Null_Unbounded_String)
         then
            if not Save_Tab (I) then
               return False;
            end if;
         end if;
      end loop;
      return True;
   end Save_All;

   function Confirm_Discard (What : String) return Boolean is
      Dlg : Gtk_Message_Dialog;
      R : Gtk_Response_Type;
   begin
      Gtk_New (Dlg, Win, Modal, Message_Question, Buttons_Yes_No,
               What & " has unsaved changes. Discard them?");
      R := Dlg.Run;
      Dlg.Destroy;
      return R = Gtk_Response_Yes;
   end Confirm_Discard;

   procedure Close_Tab (T : Positive) is
   begin
      if Tabs (T).Buffer.Get_Modified
        and then not Confirm_Discard (Base_Name (To_String (Tabs (T).Path)))
      then
         return;
      end if;
      Book.Remove_Page (Book.Page_Num (Tabs (T).Scroll));
      if Tabs (T).Path = Main_File then
         Main_File := Null_Unbounded_String;
         for I in Tabs'Range loop
            if I /= T and then Tabs (I).Used
              and then Tabs (I).Path /= Null_Unbounded_String
            then
               Main_File := Tabs (I).Path;
               exit;
            end if;
         end loop;
      end if;
      Tabs (T) := (others => <>);
      Update_Title;
   end Close_Tab;

   Template : constant String :=
     "; New ZX Spectrum program (Z80) - F5 assembles and runs it" & ASCII.LF &
     "; (see the top of src/asm.ads for the syntax)" & ASCII.LF &
     ASCII.LF &
     "CLS         equ $0daf           ; ROM: clear the screen" & ASCII.LF &
     "CHAN_OPEN   equ $1601           ; ROM: open a channel" & ASCII.LF &
     ASCII.LF &
     "            org $8000" & ASCII.LF &
     ASCII.LF &
     "start:      call CLS" & ASCII.LF &
     "            ld a,2              ; channel 2: the upper screen" &
     ASCII.LF &
     "            call CHAN_OPEN" & ASCII.LF &
     "            ld hl,message" & ASCII.LF &
     ".next       ld a,(hl)           ; .next is local to start" & ASCII.LF &
     "            or a" & ASCII.LF &
     "            ret z               ; 0 ends the text: back to BASIC" &
     ASCII.LF &
     "            rst $10             ; print the character in A" &
     ASCII.LF &
     "            inc hl" & ASCII.LF &
     "            jr .next" & ASCII.LF &
     ASCII.LF &
     "message:    db 16, 2, ""Hello from AdaZX Forge"", 13" & ASCII.LF &
     "            db 16, 1, ""Z80 at 3.5 MHz"", 0" & ASCII.LF &
     "            end start" & ASCII.LF;

   ZX81_Template : constant String :=
     "; New ZX81 program (Z80) - F5 assembles and runs it.  The code goes" &
     ASCII.LF &
     "; into a REM line at 16514 and runs with RAND USR 16514." & ASCII.LF &
     ASCII.LF &
     "PRINT_CH    equ $0010           ; RST $10 prints the character in A" &
     ASCII.LF & ASCII.LF &
     "            org 16514" & ASCII.LF &
     "start:      ld b,32" & ASCII.LF &
     ".loop       ld a,b" & ASCII.LF &
     "            and $3f" & ASCII.LF &
     "            rst PRINT_CH        ; ZX81 character codes" & ASCII.LF &
     "            djnz .loop" & ASCII.LF &
     "            ret" & ASCII.LF;

   Basic_Template : constant String :=
     "10 REM AdaZX Forge - F5 runs this program" & ASCII.LF &
     "20 BORDER 1: PAPER 1: INK 7: CLS" & ASCII.LF &
     "30 PRINT AT 0,4; INK 6;""Hello from AdaZX Forge""" & ASCII.LF &
     "40 FOR i=0 TO 255 STEP 8" & ASCII.LF &
     "50 PLOT 128,88: DRAW INK 1+INT (i/32),i-128,87-i/2" & ASCII.LF &
     "60 NEXT i" & ASCII.LF &
     "70 BEEP .2,0: BEEP .2,7: BEEP .4,12" & ASCII.LF;

   ZX81_Basic_Template : constant String :=
     "10 REM ADAZX FORGE - F5 RUNS THIS PROGRAM" & ASCII.LF &
     "20 PRINT ""HELLO FROM ADAZX FORGE""" & ASCII.LF &
     "30 FOR I=0 TO 63" & ASCII.LF &
     "40 PLOT I,21+20*SIN (I/10)" & ASCII.LF &
     "50 NEXT I" & ASCII.LF;

   function Asm_Template return String is
     (if Machine.Model = Machine.ZX81 then ZX81_Template else Template);
   function Basic_Text_Template return String is
     (if Machine.Model = Machine.ZX81 then ZX81_Basic_Template
      else Basic_Template);

   ---------------------------------------------------------------------
   --  Debugger panels
   ---------------------------------------------------------------------

   function Mon_Peek (A : Word) return Byte is (Machine.Monitor_Peek (A));

   function Parse_Address (S : String; Ok : out Boolean) return Word is
      T : constant String := Trim (S, Ada.Strings.Both);
      V : Integer;
   begin
      Ok := False;
      if T = "" then
         return 0;
      end if;
      if Asm.Lookup (T, V) then
         Ok := V in 0 .. 65535;
         return Word (V mod 65536);
      end if;
      declare
         H : constant String :=
           (if T (T'First) = '$' then T (T'First + 1 .. T'Last) else T);
      begin
         V := Integer'Value ("16#" & H & "#");
         Ok := V in 0 .. 65535;
         return Word (V mod 65536);
      end;
   exception
      when others =>
         Ok := False;
         return 0;
   end Parse_Address;

   procedure Update_Registers is
      Cyc : constant Long_Long_Integer := Machine.Cycle_Count;
      PC  : constant Word := Machine.CPU_PC;
      Lbl : constant String := (if Built then Asm.Label_At (PC) else "");
   begin
      Regs.Set_Text
        (Machine.Register_Text & ASCII.LF &
         "cycles" & Cyc'Image & "   (+" &
         Trim (Long_Long_Integer'Image (Cyc - Stop_Cycles), Ada.Strings.Left)
         & " since the last stop)" &
         (if Lbl /= "" then ASCII.LF & "at " & Lbl else ""));
   end Update_Registers;

   procedure Update_Disassembly is
      PC : constant Word := Machine.CPU_PC;
      Start : Word := PC;
      R : Unbounded_String;
      A : Word;
      Text : String (1 .. 64);
      Last, Len : Natural;
      F, L : Natural;
   begin
      --  Back up a few instructions using the assembler's line map
      if Built then
         declare
            Count : Natural := 0;
         begin
            for Back in 1 .. 24 loop
               exit when Natural (PC) < Back;
               Asm.Line_Of (PC - Word (Back), F, L);
               if F > 0 and then Asm.Is_Code (PC - Word (Back)) then
                  Start := PC - Word (Back);
                  Count := Count + 1;
                  exit when Count = 6;
               end if;
            end loop;
         end;
      end if;
      A := Start;
      for N in 1 .. 26 loop
         declare
            Lbl : constant String := Asm.Label_At (A);
         begin
            if Lbl /= "" and then Built then
               Append (R, "        " & Lbl & ":" & ASCII.LF);
            end if;
         end;
         Disasm.Disassemble (Mon_Peek'Access, A, Text, Last, Len);
         Append (R, (if A = PC then "=> " else "   ") &
                   (if Machine.Is_Breakpoint (A) then "* " else "  ") &
                   Text (1 .. Last) & ASCII.LF);
         A := A + Word (Len);
      end loop;
      Dis_Buf.Set_Text (To_String (R));
   end Update_Disassembly;

   procedure Update_Memory is
      Ok : Boolean;
      Base : Word := Parse_Address (Mem_Addr.Get_Text, Ok);
      R : Unbounded_String;
      function Show (B : Byte) return Character is
        (if B in 32 .. 126 then Character'Val (B)
         else '.');
   begin
      if not Ok then
         Base := (if Machine.Model = Machine.ZX81 then 16#4000#
                  else 16#5C00#);
      end if;
      for Row in 0 .. 15 loop
         declare
            A : constant Word := Base + Word (Row * 8);
            Chars : String (1 .. 8);
         begin
            Append (R, "$" & Hex4 (A) & "  ");
            for C in 0 .. 7 loop
               declare
                  B : constant Byte := Mon_Peek (A + Word (C));
               begin
                  Append (R, Hex2 (B) & " ");
                  Chars (C + 1) := Show (B);
               end;
            end loop;
            Append (R, " " & Chars & ASCII.LF);
         end;
      end loop;
      Mem_Buf.Set_Text (To_String (R));
   end Update_Memory;

   procedure Update_Watches is
   begin
      Watch_L.Set_Text ("watch:" & Machine.Watch_List & ASCII.LF &
                        "break:" & Machine.Breakpoint_List);
   end Update_Watches;

   procedure Update_Panels is
   begin
      Update_Registers;
      Update_Disassembly;
      Update_Memory;
      Update_Watches;
   end Update_Panels;

   ---------------------------------------------------------------------
   --  Breakpoints and building
   ---------------------------------------------------------------------

   --  Address of the first instruction at or after Line (1-based)
   procedure Line_Address (Path : String; Line : Positive;
                           Found : out Boolean; A : out Word) is
   begin
      for L in Line .. Line + 20 loop
         Asm.Address_Of (Path, L, Found, A, Code_Only => True);
         exit when Found;
      end loop;
   end Line_Address;

   procedure Apply_Breakpoints is
   begin
      --  BASIC: marks in the BASIC tab become BASIC line breakpoints
      Machine.Clear_Basic_Breakpoints;
      if Last_Kind = Basic_Program then
         declare
            T : constant Natural := Find_Tab (To_String (Basic_File));
            procedure Set_Basic (Line : Natural) is
               N : constant Integer := Basic.Basic_Line_Of (Line + 1);
            begin
               if N >= 0 then
                  Machine.Add_Basic_Breakpoint (N);
               end if;
            end Set_Basic;
         begin
            if T > 0 then
               Source_View.For_Each_Mark
                 (Tabs (T).Buffer, Source_View.Breakpoint,
                  Set_Basic'Unrestricted_Access);
            end if;
         end;
      end if;
      Machine.Clear_Breakpoints;
      if not Built then
         return;
      end if;
      for I in Tabs'Range loop
         if Tabs (I).Used and then Tabs (I).Path /= Null_Unbounded_String then
            declare
               Path : constant String := To_String (Tabs (I).Path);
               procedure Set (Line : Natural) is
                  Found : Boolean;
                  A : Word;
               begin
                  Line_Address (Path, Line + 1, Found, A);
                  if Found then
                     Machine.Set_Breakpoint (A);
                  end if;
               end Set;
            begin
               Source_View.For_Each_Mark
                 (Tabs (I).Buffer, Source_View.Breakpoint,
                  Set'Unrestricted_Access);
            end;
         end if;
      end loop;
      Update_Watches;
   end Apply_Breakpoints;

   procedure Toggle_Breakpoint (T : Positive; Line0 : Natural) is
   begin
      if Source_View.Has_Mark (Tabs (T).Buffer, Source_View.Breakpoint, Line0)
      then
         Source_View.Remove_Marks_At (Tabs (T).Buffer, Source_View.Breakpoint,
                                      Line0);
      else
         Source_View.Add_Mark (Tabs (T).Buffer, Source_View.Breakpoint, Line0);
      end if;
      Apply_Breakpoints;
   end Toggle_Breakpoint;

   procedure On_Gutter (View : Gtk_Text_View; Line : Natural) is
   begin
      for I in Tabs'Range loop
         if Tabs (I).Used and then Tabs (I).View = View then
            Toggle_Breakpoint (I, Line);
         end if;
      end loop;
   end On_Gutter;

   procedure Clear_PC_Marks is
   begin
      for I in Tabs'Range loop
         if Tabs (I).Used then
            Source_View.Clear_Marks (Tabs (I).Buffer, Source_View.Current_PC);
         end if;
      end loop;
   end Clear_PC_Marks;

   function Project_Dir return String is
     (if Main_File = Null_Unbounded_String then ""
      else Ada.Directories.Containing_Directory (To_String (Main_File)));

   function Full_Path (P : String) return String is
     (if P'Length > 0 and then P (P'First) = '/' then P
      else Project_Dir & "/" & P);

   procedure Report (Line : String) is
      D : constant String := Project_Dir & "/";
      R : Unbounded_String := To_Unbounded_String (Line);
      I : Natural;
   begin
      if D'Length > 1 then
         loop
            I := Index (R, D);
            exit when I = 0;
            Replace_Slice (R, I, I + D'Length - 1, "");
         end loop;
      end if;
      Print (To_String (R));
   end Report;

   function Dialect return Basic.Dialect is
     (if Machine.Model = Machine.ZX81 then Basic.ZX81 else Basic.Spectrum);

   function Build_Basic (T : Positive) return Boolean is
      PRG : Unbounded_String;
      Ok : Boolean;
      Path : constant String := To_String (Tabs (T).Path);
   begin
      Out_Buf.Set_Text ("");
      Print ("tokenizing " & Path & " (" &
             (if Dialect = Basic.ZX81 then "ZX81" else "Spectrum")
             & " BASIC)");
      Print ("");
      Basic.Report := Report'Access;
      Basic.Build (Path, Dialect, PRG, Ok);
      Last_PRG := PRG;
      Last_Source := To_Unbounded_String (Path);
      for E in 1 .. Basic.Error_Count loop
         if Basic.Error_Line (E) > 0 then
            Source_View.Add_Mark (Tabs (T).Buffer, Source_View.Error_Line,
                                  Basic.Error_Line (E) - 1);
         end if;
      end loop;
      if Basic.Error_Count > 0 and then Basic.Error_Line (1) > 0 then
         Goto_Line (T, Basic.Error_Line (1));
      end if;
      Built := False;
      Machine.Clear_Breakpoints;
      Basic_File := Tabs (T).Path;
      Last_Kind := (if Ok then Basic_Program else No_Program);
      Apply_Breakpoints;
      Set_Status (if Ok then "built " & Base_Name (To_String (PRG))
                  else "build failed");
      return Ok;
   end Build_Basic;

   function Build return Boolean is
      PRG : Unbounded_String;
      Ok : Boolean;
   begin
      if Current_Tab = 0 then
         Print ("nothing to build");
         return False;
      end if;
      if not Save_All then
         return False;
      end if;
      for I in Tabs'Range loop
         if Tabs (I).Used then
            Source_View.Clear_Marks (Tabs (I).Buffer, Source_View.Error_Line);
         end if;
      end loop;
      if Tabs (Current_Tab).Lang = Source_View.Basic_Text then
         return Build_Basic (Current_Tab);
      end if;
      if Main_File = Null_Unbounded_String
        or else Basic.Is_Source (To_String (Main_File))
      then
         Main_File := Tabs (Current_Tab).Path;
         Update_Title;
      end if;
      Out_Buf.Set_Text ("");
      Print ("assembling " & To_String (Main_File));
      Print ("");
      Asm.Report := Report'Access;
      Asm.Target := (if Machine.Model = Machine.ZX81 then Asm.ZX81
                     else Asm.Spectrum);
      Asm.Build (To_String (Main_File), PRG, Ok);
      Last_PRG := PRG;
      Last_Source := Main_File;
      Built := Asm.Has_Output and then not Asm.Has_Errors;
      for I in Tabs'Range loop
         if Tabs (I).Used then
            Source_View.Clear_Marks (Tabs (I).Buffer, Source_View.Error_Line);
         end if;
      end loop;
      for E in 1 .. Asm.Error_Count loop
         declare
            T : constant Natural := Find_Tab (Asm.Error_File (E));
         begin
            if T > 0 and then Asm.Error_Line (E) > 0 then
               Source_View.Add_Mark (Tabs (T).Buffer, Source_View.Error_Line,
                                     Asm.Error_Line (E) - 1);
            end if;
         end;
      end loop;
      if Asm.Error_Count > 0 then
         --  Jump to the first error
         declare
            T : constant Natural := Open_Path (Asm.Error_File (1));
         begin
            if T > 0 and then Asm.Error_Line (1) > 0 then
               Goto_Line (T, Asm.Error_Line (1));
            end if;
         end;
      end if;
      Set_Status (if Ok then "built " & Base_Name (To_String (PRG))
                  else "build failed");
      Apply_Breakpoints;
      Last_Kind := (if Ok then Asm_Program else No_Program);
      return Ok;
   end Build;

   procedure Run_Basic is
   begin
      Clear_PC_Marks;
      if Machine.Break_Hit then
         Machine.Resume;
      end if;
      Stop_Shown := False;
      Basic_Line := -1;
      Machine.Inject_And_Run (Basic.Program, 0, "RUN" & ASCII.LF,
                              Is_Basic => True);
      Print ("running: reset, load the BASIC program, RUN");
      Set_Status ("running");
      if Parent_W /= null then
         Parent_W.Present;
      end if;
   end Run_Basic;

   procedure Run_Program is
      Low  : constant Word := Asm.Low_Address;
      High : constant Word := Asm.High_Address;
   begin
      if Last_Kind = Basic_Program then
         Run_Basic;
         return;
      end if;
      Clear_PC_Marks;
      if Machine.Break_Hit then
         Machine.Resume;
      end if;
      Stop_Shown := False;
      if Machine.Model = Machine.ZX81 then
         if Low /= 16#4082# then
            Print ("ZX81 programs must start at 16514 ($4082): org 16514");
            return;
         end if;
         Machine.Inject_And_Run (Asm.ZX81_Program, 0, "RUN" & ASCII.LF,
                                 Is_Basic => True);
         Print ("running: reset, load 1 REM (code) / 2 RAND USR" &
                Natural'Image (Natural (Asm.Start_Address)) & ", RUN");
      else
         declare
            Cmd : constant String :=
              "RANDOMIZE USR" & Natural'Image (Natural (Asm.Start_Address));
         begin
            Machine.Inject_And_Run (Asm.Code_Bytes, Low, Cmd & ASCII.LF);
            Print ("running: reset, load $" & Hex4 (Low) & "-$" & Hex4 (High)
                   & ", " & Cmd);
         end;
      end if;
      Set_Status ("running");
      if Parent_W /= null then
         Parent_W.Present;
      end if;
   end Run_Program;

   ---------------------------------------------------------------------
   --  Stopping and stepping
   ---------------------------------------------------------------------

   procedure Show_Stop is
      PC : constant Word := Machine.CPU_PC;
      F, L : Natural;
      use type Machine.Stop_Reason;
   begin
      Stop_Shown := True;
      Clear_PC_Marks;
      if Machine.Last_Stop = Machine.Basic_Line then
         declare
            T : constant Natural := Find_Tab (To_String (Basic_File));
            SL : constant Natural :=
              Basic.Source_Line_Of (Natural'Max (0, Machine.Basic_Stop_Line));
         begin
            Basic_Line := Machine.Basic_Stop_Line;
            if T > 0 and then SL > 0 then
               Source_View.Add_Mark (Tabs (T).Buffer, Source_View.Current_PC,
                                     SL - 1);
               Goto_Line (T, SL);
            end if;
         end;
      elsif Built then
         Asm.Line_Of (PC, F, L);
         if F > 0 then
            declare
               T : constant Natural := Open_Path (Asm.File_Name (F));
            begin
               if T > 0 then
                  Source_View.Add_Mark (Tabs (T).Buffer,
                                        Source_View.Current_PC, L - 1);
                  Goto_Line (T, L);
               end if;
            end;
         end if;
      end if;
      Set_Status ("stopped: " & Machine.Stop_Text);
      Update_Panels;
      Stop_Cycles := Machine.Cycle_Count;
      if Refresh_Screen /= null then
         Refresh_Screen.all;
      end if;
      Win.Present;
   end Show_Stop;

   procedure Resumed is
   begin
      Clear_PC_Marks;
      Stop_Shown := False;
      Set_Status ("running");
   end Resumed;

   ---------------------------------------------------------------------
   --  Actions
   ---------------------------------------------------------------------

   --  Load the tape (.tap / .p) the last build wrote, through the ROM
   procedure Load_Tape is
      Ok : Boolean;
      P : constant String := To_String (Last_PRG);
   begin
      if P = "" or else not Ada.Directories.Exists (P) then
         Print ("build the program first");
         return;
      end if;
      if Machine.Break_Hit then
         Machine.Resume;
      end if;
      Machine.Autostart (P, Ok);
      Resumed;
      Print (if Ok then "loading " & Ada.Directories.Simple_Name (P) &
               " with LOAD """""
             else "cannot load " & P & ": " & Machine.Error_Message);
      if Parent_W /= null then
         Parent_W.Present;
      end if;
   end Load_Tape;

   --  The BASIC program in the emulator's memory
   function Memory_Program return Byte_Array is
      From, To : Word;
   begin
      if Machine.Model = Machine.ZX81 then
         From := 16#407D#;
         To := Machine.Peek_Word (16#400C#);         --  D_FILE
      else
         From := Machine.Peek_Word (23635);           --  PROG
         To := Machine.Peek_Word (23627);             --  VARS
      end if;
      if To <= From or else To - From > 48_000 then
         return (1 .. 0 => 0);
      end if;
      declare
         D : Byte_Array (0 .. Natural (To - From) - 1);
      begin
         for K in D'Range loop
            D (K) := Machine.Peek (From + Word (K));
         end loop;
         return D;
      end;
   end Memory_Program;

   function Unsaved_Ok return Boolean is
      Names : Unbounded_String;
   begin
      for I in Tabs'Range loop
         if Tabs (I).Used and then Tabs (I).Buffer.Get_Modified then
            Append (Names, (if Length (Names) > 0 then ", " else "") &
                      Base_Name (To_String (Tabs (I).Path)));
         end if;
      end loop;
      return Length (Names) = 0 or else Confirm_Discard (To_String (Names));
   end Unsaved_Ok;

   procedure Close_Forge is
   begin
      Save_State;
      if Quit_App /= null then
         if Unsaved_Ok then
            Quit_App.all;
         end if;
      else
         Win.Hide;
      end if;
   end Close_Forge;

   type Action is
     (A_New, A_New_Basic, A_Import_PRG, A_Fetch_Basic, A_Open, A_Save,
      A_Save_As, A_Close_Tab, A_Set_Main,
      A_Undo, A_Redo, A_Close,
      A_Build, A_Run, A_Rebuild_Run, A_Tape,
      A_Pause, A_Step_Into, A_Step_Over,
      A_Step_Out, A_Run_To_Cursor, A_Toggle_BP, A_Clear_BPs,
      A_Reset,
      A_Emulator, A_UDG, A_Screen, A_ZX81_Screen,
      A_Help);

   procedure Do_Action (A : Action) is
      T : constant Natural := Current_Tab;
      Dummy : Boolean;
      Stopped : constant Boolean := Machine.Break_Hit;
   begin
      case A is
         when A_New =>
            Dummy := New_Tab ("", Asm_Template) > 0;
         when A_New_Basic =>
            Dummy := New_Tab ("", Basic_Text_Template, Is_Basic => True) > 0;
         when A_Import_PRG =>
            declare
               P : constant String :=
                 Choose_File ("Import BASIC program", False, PRG_Files => True);
               Ok : Boolean;
            begin
               if P /= "" then
                  declare
                     Text : constant String := Basic.List_File (P, Ok);
                  begin
                     if Ok and then Text /= "" then
                        Dummy := New_Tab ("", Text, Is_Basic => True) > 0;
                        Print ("imported " & P & " (save it as .bas)");
                     else
                        Print ("no BASIC program in " & P);
                     end if;
                  end;
               end if;
            end;
         when A_Fetch_Basic =>
            declare
               Text : constant String :=
                 Basic.List (Memory_Program, Dialect);
            begin
               if Text = "" then
                  Print ("no BASIC program in the emulator's memory");
               else
                  Dummy := New_Tab ("", Text, Is_Basic => True) > 0;
                  Print ("listed the BASIC program from memory");
               end if;
            end;
         when A_Open =>
            declare
               P : constant String := Choose_File ("Open source", False);
            begin
               if P /= "" then
                  if UDG_Editor.Is_UDG_File (P) then
                     UDG_Editor.Open (Win, P);
                  elsif ZX81_Editor.Is_ZX81_Screen_File (P) then
                     ZX81_Editor.Open (Win, P);
                  elsif Screen_Editor.Is_Screen_File (P) then
                     Screen_Editor.Open (Win, P);
                  else
                     Dummy := Open_Path (P) > 0;
                  end if;
               end if;
            end;
         when A_Save =>
            if T > 0 then
               Dummy := Save_Tab (T);
            end if;
         when A_Save_As =>
            if T > 0 then
               Dummy := Save_Tab (T, Ask => True);
            end if;
         when A_Close_Tab =>
            if T > 0 then
               Close_Tab (T);
            end if;
         when A_Set_Main =>
            if T > 0 and then Tabs (T).Path /= Null_Unbounded_String then
               Main_File := Tabs (T).Path;
               Update_Title;
            end if;
         when A_Undo =>
            if T > 0 then
               Source_View.Undo (Tabs (T).Buffer);
            end if;
         when A_Redo =>
            if T > 0 then
               Source_View.Redo (Tabs (T).Buffer);
            end if;
         when A_Close =>
            Close_Forge;
         when A_Build =>
            Dummy := Build;
         when A_Run =>
            if Stopped then
               Machine.Resume;
               Resumed;
            elsif Build then
               Run_Program;
            end if;
         when A_Tape =>
            if Build then
               Load_Tape;
            end if;
         when A_Rebuild_Run =>
            if Build then
               Run_Program;
            end if;
         when A_Pause =>
            Machine.Request_Break;
         when A_Step_Into =>
            if Stopped and then Last_Kind = Basic_Program
              and then not Built
            then
               Machine.Step_Basic_Line;     --  one BASIC line
               Resumed;
            elsif Stopped then
               Machine.Step_Instruction;
               Show_Stop;
            else
               Machine.Request_Break;
            end if;
         when A_Step_Over =>
            if Stopped and then Last_Kind = Basic_Program
              and then not Built
            then
               Machine.Step_Basic_Line;
               Resumed;
            elsif Stopped then
               Machine.Step_Over;
               if Machine.Break_Hit then
                  Show_Stop;
               else
                  Resumed;
               end if;
            else
               Machine.Request_Break;
            end if;
         when A_Step_Out =>
            if Stopped then
               Machine.Step_Out;
               Resumed;
            end if;
         when A_Run_To_Cursor =>
            if T > 0 and then Built then
               declare
                  Found : Boolean;
                  Addr : Word;
               begin
                  Line_Address (To_String (Tabs (T).Path), Cursor_Line (T),
                                Found, Addr);
                  if Found then
                     Machine.Run_To (Addr);
                     Resumed;
                  else
                     Print ("no code at or after the cursor line");
                  end if;
               end;
            end if;
         when A_Toggle_BP =>
            if T > 0 then
               Toggle_Breakpoint (T, Cursor_Line (T) - 1);
            end if;
         when A_Clear_BPs =>
            for I in Tabs'Range loop
               if Tabs (I).Used then
                  Source_View.Clear_Marks (Tabs (I).Buffer,
                                           Source_View.Breakpoint);
               end if;
            end loop;
            Machine.Clear_Breakpoints;
            Machine.Clear_Watches;
            Update_Watches;
         when A_Reset =>
            if Stopped then
               Machine.Resume;
            end if;
            Machine.Reset;
            Resumed;
         when A_Emulator =>
            if Show_Emulator /= null then
               Show_Emulator.all;
            elsif Parent_W /= null then
               Parent_W.Present;
            end if;
         when A_UDG =>
            UDG_Editor.Open (Win);
         when A_Screen =>
            Screen_Editor.Open (Win);
         when A_ZX81_Screen =>
            ZX81_Editor.Open (Win);
         when A_Help =>
            Print ("F5 build & run / continue   Ctrl+F5 rebuild & run   " &
                   "F6 pause   F7 build   Shift+F5 build tape and LOAD it");
            Print ("F9 breakpoint (or click the line-number gutter)   " &
                   "F10 step over   F11 step into   Shift+F11 step out");
            Print ("Ctrl+F10 run to cursor   memory box: $addr or label   " &
                   "watch box: ""$5c08 w"", ""score rw"", ""$4000-$57ff w""");
            Print ("Click an error line here to jump to it.  Syntax: see " &
                   "the top of src/asm.ads (pasmo / sjasmplus style).");
            Print ("Spectrum: code is loaded and started with RANDOMIZE " &
                   "USR start; the .tap has a BASIC loader.  ZX81: org " &
                   "16514, the code goes into a REM line.");
            Print ("BASIC (.bas / .b81, Ctrl+Shift+N): F5 tokenizes and " &
                   "runs it, the running line is highlighted and F10 / F11 " &
                   "step lines.  See src/basic.ads.");
      end case;
   end Do_Action;

   Menu_Items : array (Action) of Gtk_Menu_Item;
   Tool_Items : array (Action) of Gtk_Tool_Button;

   procedure On_Menu (Item : access Gtk_Menu_Item_Record'Class) is
   begin
      for A in Action loop
         if Menu_Items (A) /= null
           and then Gtk_Menu_Item (Item) = Menu_Items (A)
         then
            Do_Action (A);
            return;
         end if;
      end loop;
   end On_Menu;

   procedure On_Tool (Item : access Gtk_Tool_Button_Record'Class) is
   begin
      for A in Action loop
         if Tool_Items (A) /= null
           and then Gtk_Tool_Button (Item) = Tool_Items (A)
         then
            Do_Action (A);
            return;
         end if;
      end loop;
   end On_Tool;

   ---------------------------------------------------------------------
   --  Panel input
   ---------------------------------------------------------------------

   procedure On_Mem_Entry (Self : access Gtk_Entry_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Update_Memory;
   end On_Mem_Entry;

   procedure On_Watch_Entry (Self : access Gtk_Entry_Record'Class) is
      T : constant String := Trim (Self.Get_Text, Ada.Strings.Both);
      Sp : constant Natural := Index (T, " ");
      Target : constant String := (if Sp = 0 then T else T (T'First .. Sp - 1));
      Flags : constant String :=
        To_Lower (if Sp = 0 then "w" else Trim (T (Sp .. T'Last),
                                                 Ada.Strings.Both));
      Dash : constant Natural := Index (Target, "-");
      Ok1, Ok2 : Boolean := True;
      From, To : Word;
   begin
      if T = "" then
         return;
      end if;
      if T = "clear" then
         Machine.Clear_Watches;
      else
         if Dash > Target'First then
            From := Parse_Address (Target (Target'First .. Dash - 1), Ok1);
            To := Parse_Address (Target (Dash + 1 .. Target'Last), Ok2);
         else
            From := Parse_Address (Target, Ok1);
            To := From;
         end if;
         if not (Ok1 and Ok2) then
            Print ("watch: unknown address " & Target);
            return;
         end if;
         if Flags = "off" or else Flags = "-" then
            Machine.Remove_Watch (From);
         else
            Machine.Add_Watch (From, To, Index (Flags, "r") > 0,
                               Index (Flags, "w") > 0);
         end if;
      end if;
      Self.Set_Text ("");
      Update_Watches;
   end On_Watch_Entry;

   --  Clicking a "file:line:" line in the output jumps there
   function On_Output_Click (Self : access Gtk_Widget_Record'Class;
                             Event : Gdk.Event.Gdk_Event_Button)
                             return Boolean is
      pragma Unreferenced (Self, Event);
      Iter, Line_End : Gtk_Text_Iter;
      Ok : Boolean;
   begin
      Out_Buf.Get_Iter_At_Mark (Iter, Out_Buf.Get_Insert);
      Set_Line_Offset (Iter, 0);
      Copy (Iter, Line_End);
      if not Ends_Line (Line_End) then
         Forward_To_Line_End (Line_End, Ok);
      end if;
      declare
         S : constant String := Out_Buf.Get_Text (Iter, Line_End, True);
         C1 : constant Natural := Index (S, ":");
         C2 : constant Natural :=
           (if C1 > 0 then Index (S (C1 + 1 .. S'Last), ":") else 0);
      begin
         if C1 > 1 and then C2 > C1 + 1 then
            declare
               Path : constant String := Full_Path (S (S'First .. C1 - 1));
               Line : constant Natural :=
                 Natural'Value (S (C1 + 1 .. C2 - 1));
               T : constant Natural := Open_Path (Path);
            begin
               if T > 0 and then Line > 0 then
                  Goto_Line (T, Line);
                  Tabs (T).View.Grab_Focus;
               end if;
            end;
         end if;
      end;
      return False;
   exception
      when others =>
         return False;
   end On_Output_Click;

   function On_Delete (Self : access Gtk_Widget_Record'Class;
                       Event : Gdk.Event.Gdk_Event) return Boolean is
      pragma Unreferenced (Self, Event);
   begin
      Close_Forge;
      return True;    --  keep the window (and the open files) for later
   end On_Delete;

   ---------------------------------------------------------------------
   --  Construction
   ---------------------------------------------------------------------

   function Share_Dir return String is
      Exe : constant String := Ada.Command_Line.Command_Name;
      Candidates : constant array (1 .. 3) of Unbounded_String :=
        (To_Unbounded_String
           (Ada.Directories.Containing_Directory
              (Ada.Directories.Containing_Directory
                 (Ada.Directories.Full_Name (Exe))) & "/share/adazx"),
         To_Unbounded_String (Ada.Directories.Current_Directory &
                              "/share/adazx"),
         To_Unbounded_String ("/usr/local/share/adazx"));
   begin
      for C of Candidates loop
         if Ada.Directories.Exists (To_String (C) &
                                    "/language-specs/z80asm.lang")
         then
            return To_String (C);
         end if;
      end loop;
      return To_String (Candidates (1));
   exception
      when others =>
         return "share/adazx";
   end Share_Dir;

   procedure Build_Window is
      Accel : Gtk_Accel_Group;
      VBox, Right : Gtk_Box;
      Bar : Gtk_Menu_Bar;
      Tools : Gtk_Toolbar;
      H : Gtk_Paned;
      V : Gtk_Paned;
      Scroll : Gtk_Scrolled_Window;
      Frame : Gtk_Frame;
      Box : Gtk_Box;
      Dis_View, Mem_View : Gtk_Text_View;

      function Menu (Title : String) return Gtk_Menu is
         Item : Gtk_Menu_Item;
         M : Gtk_Menu;
      begin
         Gtk_New_With_Mnemonic (Item, Title);
         Gtk_New (M);
         Item.Set_Submenu (M);
         Bar.Append (Item);
         return M;
      end Menu;

      procedure Item (M : Gtk_Menu; Label : String; A : Action;
                      Key : Gdk_Key_Type := 0;
                      Mods : Gdk_Modifier_Type := 0) is
      begin
         Gtk_New_With_Mnemonic (Menu_Items (A), Label);
         Menu_Items (A).On_Activate (On_Menu'Access);
         if Key /= 0 then
            Menu_Items (A).Add_Accelerator ("activate", Accel, Key, Mods,
                                            Accel_Visible);
         end if;
         M.Append (Menu_Items (A));
      end Item;

      procedure Separator (M : Gtk_Menu) is
         S : Gtk_Separator_Menu_Item;
      begin
         Gtk_New (S);
         M.Append (S);
      end Separator;

      procedure Tool (Label, Icon : String; A : Action; Tip : String) is
      begin
         Gtk_New (Tool_Items (A), Label => Label);
         Tool_Items (A).Set_Icon_Name (Icon);
         Tool_Items (A).Set_Tooltip_Text (Tip);
         Tool_Items (A).On_Clicked (On_Tool'Access);
         Tool_Items (A).Set_Is_Important (True);
         Tools.Insert (Tool_Items (A));
      end Tool;

      procedure Tool_Separator is
         S : Gtk_Separator_Tool_Item;
      begin
         Gtk_New (S);
         Tools.Insert (S);
      end Tool_Separator;

      function Mono_View (B : out Gtk_Text_Buffer) return Gtk_Text_View is
         View : Gtk_Text_View;
      begin
         Gtk_New (B);
         Gtk_New (View, B);
         View.Set_Editable (False);
         View.Set_Cursor_Visible (False);
         View.Modify_Font (Pango.Font.From_String (Mono));
         return View;
      end Mono_View;

      M : Gtk_Menu;
   begin
      Source_View.Init (Share_Dir & "/language-specs");
      Source_View.On_Gutter_Click := On_Gutter'Access;
      --  F10 is ours (step over), not the menu bar's
      Glib.Properties.Set_Property
        (Gtk.Settings.Get_Default, Gtk.Settings.Gtk_Menu_Bar_Accel_Property,
         "");

      Gtk_New (Win);
      Win.Set_Title ("AdaZX Forge");
      Win.Set_Default_Size (1280, 820);
      Win.On_Delete_Event (On_Delete'Access);
      Gtk_New (Accel);
      Win.Add_Accel_Group (Accel);

      Gtk_New_Vbox (VBox);
      Win.Add (VBox);
      Gtk_New (Bar);
      VBox.Pack_Start (Bar, Expand => False, Fill => False);

      M := Menu ("_File");
      Item (M, "_New assembly source", A_New, GDK_LC_n, Control_Mask);
      Item (M, "New _BASIC program", A_New_Basic, GDK_LC_n,
            Control_Mask or Shift_Mask);
      Item (M, "_Open...", A_Open, GDK_LC_o, Control_Mask);
      Item (M, "_Save", A_Save, GDK_LC_s, Control_Mask);
      Item (M, "Save _as...", A_Save_As, GDK_LC_s, Control_Mask or Shift_Mask);
      Item (M, "Set as _main file", A_Set_Main);
      Separator (M);
      Item (M, "_Import BASIC from a tape (.tap / .p)...", A_Import_PRG);
      Item (M, "_Get BASIC program from emulator", A_Fetch_Basic);
      Separator (M);
      Item (M, "_Close tab", A_Close_Tab, GDK_LC_w, Control_Mask);
      Separator (M);
      Item (M, "Close Forge", A_Close);
      M := Menu ("_Edit");
      Item (M, "_Undo", A_Undo, GDK_LC_z, Control_Mask);
      Item (M, "_Redo", A_Redo, GDK_LC_z, Control_Mask or Shift_Mask);
      M := Menu ("_Build");
      Item (M, "_Build", A_Build, GDK_F7);
      Item (M, "Build and _run / continue", A_Run, GDK_F5);
      Item (M, "Rebuild and run", A_Rebuild_Run, GDK_F5, Control_Mask);
      Separator (M);
      Item (M, "Build _tape and LOAD it through the ROM", A_Tape, GDK_F5,
            Shift_Mask);
      M := Menu ("_Debug");
      Item (M, "_Pause", A_Pause, GDK_F6);
      Item (M, "Step _into", A_Step_Into, GDK_F11);
      Item (M, "Step _over", A_Step_Over, GDK_F10);
      Item (M, "Step o_ut", A_Step_Out, GDK_F11, Shift_Mask);
      Item (M, "Run to _cursor", A_Run_To_Cursor, GDK_F10, Control_Mask);
      Separator (M);
      Item (M, "Toggle _breakpoint", A_Toggle_BP, GDK_F9);
      Item (M, "Clear all breakpoints and watches", A_Clear_BPs);
      Separator (M);
      Item (M, "_Reset machine", A_Reset);
      Item (M, "Show _emulator", A_Emulator, GDK_F12);
      M := Menu ("_Tools");
      Item (M, "_UDG / character set editor", A_UDG, GDK_LC_k, Control_Mask);
      Item (M, "Spectrum _screen editor (SCREEN$)", A_Screen, GDK_LC_b,
            Control_Mask);
      Item (M, "ZX81 screen _editor", A_ZX81_Screen, GDK_LC_r, Control_Mask);
      M := Menu ("_Help");
      Item (M, "_Keys and syntax", A_Help, GDK_F1);

      Gtk_New (Tools);
      Tools.Set_Style (Toolbar_Both_Horiz);
      Tool ("New", "document-new", A_New, "New source (Ctrl+N)");
      Tool ("Open", "document-open", A_Open, "Open source (Ctrl+O)");
      Tool ("Save", "document-save", A_Save, "Save (Ctrl+S)");
      Tool_Separator;
      Tool ("Build", "system-run", A_Build, "Assemble (F7)");
      Tool ("Run", "media-playback-start", A_Run,
            "Build and run, or continue when stopped (F5)");
      Tool ("Pause", "media-playback-pause", A_Pause, "Pause (F6)");
      Tool_Separator;
      Tool ("Into", "go-down", A_Step_Into, "Step into (F11)");
      Tool ("Over", "go-next", A_Step_Over, "Step over (F10)");
      Tool ("Out", "go-up", A_Step_Out, "Step out (Shift+F11)");
      Tool ("Breakpoint", "media-record", A_Toggle_BP,
            "Toggle breakpoint (F9)");
      Tool_Separator;
      Tool ("Reset", "view-refresh", A_Reset, "Reset the machine");
      Tool ("Emulator", "video-display", A_Emulator,
            "Show the emulator window (F12)");
      VBox.Pack_Start (Tools, Expand => False, Fill => False);

      Gtk_New_Hpaned (H);
      VBox.Pack_Start (H, Expand => True, Fill => True);

      --  Left: editor tabs above the build output
      Gtk_New_Vpaned (V);
      Gtk_New (Book);
      Book.Set_Scrollable (True);
      V.Pack1 (Book, Resize => True, Shrink => False);
      Gtk_New (Scroll);
      Gtk_New (Out_Buf);
      Gtk_New (Out_View, Out_Buf);
      Out_View.Set_Editable (False);
      Out_View.Modify_Font (Pango.Font.From_String (Mono));
      Out_View.On_Button_Release_Event (On_Output_Click'Access);
      Scroll.Add (Out_View);
      V.Pack2 (Scroll, Resize => False, Shrink => True);
      V.Set_Position (600);
      H.Pack1 (V, Resize => True, Shrink => False);

      --  Right: debugger panels
      Gtk_New_Vbox (Right, Spacing => 4);
      Gtk_New (Status, "ready");
      Status.Set_Halign (Align_Start);
      Status.Set_Ellipsize (Pango.Layout.Ellipsize_End);
      Right.Pack_Start (Status, Expand => False, Fill => False);

      Gtk_New (Frame, "Registers");
      Gtk_New (Regs, "");
      Regs.Set_Halign (Align_Start);
      Regs.Set_Selectable (True);
      Regs.Modify_Font (Pango.Font.From_String (Mono));
      Frame.Add (Regs);
      Right.Pack_Start (Frame, Expand => False, Fill => False);

      Gtk_New (Frame, "Disassembly");
      Gtk_New (Scroll);
      Dis_View := Mono_View (Dis_Buf);
      Scroll.Add (Dis_View);
      Frame.Add (Scroll);
      Right.Pack_Start (Frame, Expand => True, Fill => True);

      Gtk_New (Frame, "Memory");
      Gtk_New_Vbox (Box);
      Gtk_New (Mem_Addr);
      Mem_Addr.Set_Text ("$5C00");
      Mem_Addr.Set_Placeholder_Text ("address or label");
      Mem_Addr.On_Activate (On_Mem_Entry'Access);
      Box.Pack_Start (Mem_Addr, Expand => False, Fill => False);
      Mem_View := Mono_View (Mem_Buf);
      Box.Pack_Start (Mem_View, Expand => False, Fill => False);
      Frame.Add (Box);
      Right.Pack_Start (Frame, Expand => False, Fill => False);

      Gtk_New (Frame, "Watchpoints");
      Gtk_New_Vbox (Box);
      Gtk_New (Watch_E);
      Watch_E.Set_Placeholder_Text
        ("$5c08 w  |  score rw  |  $4000-$57ff w  |  $5c08 off  |  clear");
      Watch_E.On_Activate (On_Watch_Entry'Access);
      Box.Pack_Start (Watch_E, Expand => False, Fill => False);
      Gtk_New (Watch_L, "");
      Watch_L.Set_Halign (Align_Start);
      Watch_L.Set_Line_Wrap (True);
      Watch_L.Modify_Font (Pango.Font.From_String (Mono));
      Box.Pack_Start (Watch_L, Expand => False, Fill => False);
      Frame.Add (Box);
      Right.Pack_Start (Frame, Expand => False, Fill => False);

      H.Pack2 (Right, Resize => False, Shrink => False);
      H.Set_Position (720);
   end Build_Window;

   procedure Open (Parent : Gtk.Window.Gtk_Window; File : String := "") is
      Dummy : Natural;
   begin
      Parent_W := Parent;
      if Win = null then
         Build_Window;
         Win.Show_All;
         if File = "" then
            --  Reopen the files of the last session
            declare
               S : constant String := Settings.Get ("forge_files", Settings.Get ("studio_files", ""));
               From : Positive := S'First;
            begin
               for I in S'Range loop
                  if S (I) = '|' or else I = S'Last then
                     declare
                        P : constant String :=
                          S (From .. (if S (I) = '|' then I - 1 else I));
                     begin
                        if P /= "" and then Ada.Directories.Exists (P) then
                           Dummy := Open_Path (P);
                        end if;
                     end;
                     From := I + 1;
                  end if;
               end loop;
               declare
                  M : constant String := Settings.Get ("forge_main", Settings.Get ("studio_main", ""));
               begin
                  if M /= "" and then Find_Tab (M) > 0 then
                     Main_File := To_Unbounded_String (M);
                  end if;
               end;
            end;
            if Current_Tab = 0 then
               Dummy := New_Tab ("", Asm_Template);
            end if;
         end if;
         Do_Action (A_Help);
      end if;
      if File /= "" then
         declare
            Full : constant String :=
              (if Ada.Directories.Exists (File)
               then Ada.Directories.Full_Name (File) else File);
         begin
            if UDG_Editor.Is_UDG_File (Full) then
               UDG_Editor.Open (Win, Full);
            elsif ZX81_Editor.Is_ZX81_Screen_File (Full) then
               ZX81_Editor.Open (Win, Full);
            elsif Screen_Editor.Is_Screen_File (Full) then
               Screen_Editor.Open (Win, Full);
            elsif Ada.Directories.Exists (Full) then
               Dummy := Open_Path (Full);
               Main_File := To_Unbounded_String (Full);
            else
               --  New file of that name
               Dummy := New_Tab (Full, Asm_Template);
               if Write_File (Full, Asm_Template) then
                  Tabs (Dummy).Buffer.Set_Modified (False);
                  Main_File := To_Unbounded_String (Full);
               end if;
            end if;
         end;
      end if;
      Update_Title;
      Update_Panels;
      Win.Show_All;
      Win.Present;
   end Open;

   procedure Save_State is
      Files : Unbounded_String;
   begin
      if Win = null then
         return;
      end if;
      for I in Tabs'Range loop
         if Tabs (I).Used and then Tabs (I).Path /= Null_Unbounded_String then
            if Length (Files) > 0 then
               Append (Files, "|");
            end if;
            Append (Files, Tabs (I).Path);
         end if;
      end loop;
      Settings.Set ("forge_files", To_String (Files));
      Settings.Set ("forge_main", To_String (Main_File));
   end Save_State;

   --  Highlight the BASIC line being executed (from BASIC's text pointer)
   procedure Track_Basic_Line is
      N  : constant Integer := Machine.Basic_Current_Line;
      T  : constant Natural := Find_Tab (To_String (Basic_File));
   begin
      if N = Basic_Line or else T = 0 then
         return;
      end if;
      Basic_Line := N;
      Source_View.Clear_Marks (Tabs (T).Buffer, Source_View.Current_PC);
      if N >= 0 then
         declare
            L : constant Natural := Basic.Source_Line_Of (N);
         begin
            if L > 0 then
               Source_View.Add_Mark (Tabs (T).Buffer, Source_View.Current_PC,
                                     L - 1);
            end if;
         end;
         Set_Status ("running BASIC line" & N'Image);
      else
         Set_Status ("BASIC: ready (direct mode)");
      end if;
   end Track_Basic_Line;

   procedure Tick is
   begin
      if Win = null then
         return;
      end if;
      if Machine.Break_Hit then
         if not Stop_Shown then
            Show_Stop;
         end if;
      else
         if Stop_Shown then
            Resumed;
         end if;
         if Last_Kind = Basic_Program
           and then Clock - Last_Basic_Check > Milliseconds (100)
         then
            Last_Basic_Check := Clock;
            Track_Basic_Line;
         end if;
         if Win.Get_Visible and then Clock - Last_Update > Milliseconds (250)
         then
            Last_Update := Clock;
            Update_Registers;
            Update_Disassembly;
            Update_Memory;
         end if;
      end if;
   end Tick;

end Forge;
