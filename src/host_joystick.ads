-- ***************************************************************************
--                          AdaZX - Host_Joystick
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
--  Host game controllers through the Linux joystick API (/dev/input/jsN).
--  The selected device drives the emulated joystick port chosen in the
--  Keyboard package (together with the keyboard joystick keys).

package Host_Joystick is

   Max_Devices : constant := 8;

   procedure Scan;
   --  Look for /dev/input/js0 .. js7.

   function Count return Natural;
   function Name (Index : Natural) return String;   --  0-based
   function Device_Number (Index : Natural) return Natural;  --  N of jsN

   procedure Open (Index : Natural);
   procedure Close;
   function Selected return Integer;    --  index into the scan, -1 = none

   procedure Poll;
   --  Read pending events and update the emulated joystick.

   function Find (Device_Name : String) return Integer;
   --  Index of the device with this name, or -1.

   function Auto_Select return Integer;
   --  The first device that looks like a joystick or gamepad (not a wheel).

end Host_Joystick;
