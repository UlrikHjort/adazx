-- ***************************************************************************
--                               AdaZX - Forge
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

--  AdaZX Forge: Z80 assembler IDE, BASIC editor, source-level debugger
--  and graphics editors around the running emulator.

with Gtk.Window;

package Forge is

   procedure Open (Parent : Gtk.Window.Gtk_Window; File : String := "");
   --  Show the forge window (opening File, or the files of last time).

   function Is_Open return Boolean;

   procedure Tick;
   --  Called regularly by the emulator loop: notices breakpoints and
   --  refreshes the debugger panels.

   type Proc is access procedure;
   Refresh_Screen : Proc := null;   --  redraw the emulator window
   Show_Emulator  : Proc := null;   --  bring the emulator window up
   Quit_App : Proc := null;
   --  Set when the forge is the main window (adazx-forge): closing the
   --  forge then quits the program instead of hiding it.

   procedure Save_State;

end Forge;
