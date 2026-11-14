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
--  Machine-code monitor window (debugger).
--
--  Commands (numbers are hex, '$' optional):
--    r              registers           z [n]       step n instructions
--    d [addr]       disassemble         m [a [b]]   memory dump
--    > addr bb ..   write bytes         g [addr]    go (optionally set PC)
--    b addr         set breakpoint      bd [addr]   delete one / all
--    bl             list breakpoints    w [a [b]]   watch reads/writes
--    io             chip state
--    x              close and continue  h, ?        help

with Gtk.Window;

package Monitor is

   function Active return Boolean;
   --  True while the monitor holds the machine stopped.

   procedure Open (Parent : Gtk.Window.Gtk_Window; Reason : String := "");

   type Refresh_Proc is access procedure;
   On_Change : Refresh_Proc := null;
   --  Called after commands that change machine state (to redraw).

end Monitor;
