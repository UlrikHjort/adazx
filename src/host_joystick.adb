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
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces; use Interfaces;
with Interfaces.C; use Interfaces.C;
with Interfaces.C.Strings;
with System;

with Keyboard;

package body Host_Joystick is

   type Device is record
      Number : Natural := 0;
      Label  : Unbounded_String;
   end record;

   Devices : array (0 .. Max_Devices - 1) of Device;
   Found   : Natural := 0;
   Current : Integer := -1;
   FD      : int := -1;

   --  Current controller state
   Axis_X, Axis_Y, Hat_X, Hat_Y : Integer := 0;
   Buttons : Unsigned_32 := 0;

   function C_Open (Path : Interfaces.C.Strings.chars_ptr; Flags : int)
     return int;
   pragma Import (C, C_Open, "open");
   function C_Read (F : int; Buf : System.Address; N : size_t) return long;
   pragma Import (C, C_Read, "read");
   function C_Close (F : int) return int;
   pragma Import (C, C_Close, "close");

   O_RDONLY   : constant int := 0;
   O_NONBLOCK : constant int := 8#4000#;

   type JS_Event is record
      Time   : Unsigned_32;
      Value  : Integer_16;
      Kind   : Unsigned_8;
      Number : Unsigned_8;
   end record;
   pragma Convention (C, JS_Event);

   function Read_Name (N : Natural) return String is
      Path : constant String := "/sys/class/input/js" &
        Ada.Strings.Fixed.Trim (N'Image, Ada.Strings.Left) & "/device/name";
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      declare
         L : constant String := Ada.Text_IO.Get_Line (F);
      begin
         Ada.Text_IO.Close (F);
         return L;
      end;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         return "Joystick" & N'Image;
   end Read_Name;

   procedure Scan is
   begin
      Found := 0;
      for N in 0 .. Max_Devices - 1 loop
         declare
            Path : constant String := "/dev/input/js" &
              Ada.Strings.Fixed.Trim (N'Image, Ada.Strings.Left);
         begin
            if Ada.Directories.Exists (Path) then
               Devices (Found) := (Number => N,
                                   Label => To_Unbounded_String (Read_Name (N)));
               Found := Found + 1;
            end if;
         exception
            when others => null;
         end;
      end loop;
   end Scan;

   function Count return Natural is (Found);
   function Name (Index : Natural) return String is
     (To_String (Devices (Index).Label));
   function Device_Number (Index : Natural) return Natural is
     (Devices (Index).Number);
   function Selected return Integer is (Current);

   function Find (Device_Name : String) return Integer is
   begin
      for I in 0 .. Found - 1 loop
         if Name (I) = Device_Name then
            return I;
         end if;
      end loop;
      return -1;
   end Find;

   function Auto_Select return Integer is
      use Ada.Characters.Handling;
   begin
      for I in 0 .. Found - 1 loop
         declare
            L : constant String := To_Lower (Name (I));
         begin
            if Ada.Strings.Fixed.Index (L, "wheel") = 0
              and then Ada.Strings.Fixed.Index (L, "keyboard") = 0
              and then Ada.Strings.Fixed.Index (L, "mouse") = 0
            then
               return I;
            end if;
         end;
      end loop;
      return -1;
   end Auto_Select;

   procedure Update is
      Bits : Unsigned_8 := 0;
      Dead : constant := 16_000;
   begin
      if Axis_Y < -Dead or else Hat_Y < 0 then Bits := Bits or 1; end if;
      if Axis_Y > Dead or else Hat_Y > 0 then Bits := Bits or 2; end if;
      if Axis_X < -Dead or else Hat_X < 0 then Bits := Bits or 4; end if;
      if Axis_X > Dead or else Hat_X > 0 then Bits := Bits or 8; end if;
      if (Buttons and 16#0F#) /= 0 then Bits := Bits or 16; end if;
      Keyboard.Set_Host_Joystick (Bits);
   end Update;

   procedure Close is
      R : int;
      pragma Unreferenced (R);
   begin
      if FD >= 0 then
         R := C_Close (FD);
      end if;
      FD := -1;
      Current := -1;
      Axis_X := 0; Axis_Y := 0; Hat_X := 0; Hat_Y := 0; Buttons := 0;
      Keyboard.Set_Host_Joystick (0);
   end Close;

   procedure Open (Index : Natural) is
      use Interfaces.C.Strings;
   begin
      Close;
      if Index >= Found then
         return;
      end if;
      declare
         P : chars_ptr := New_String
           ("/dev/input/js" &
            Ada.Strings.Fixed.Trim (Devices (Index).Number'Image,
                                    Ada.Strings.Left));
      begin
         FD := C_Open (P, O_RDONLY + O_NONBLOCK);
         Free (P);
      end;
      if FD >= 0 then
         Current := Index;
      end if;
   end Open;

   procedure Poll is
      E : JS_Event;
      N : long;
   begin
      if FD < 0 then
         return;
      end if;
      loop
         N := C_Read (FD, E'Address, 8);
         exit when N /= 8;
         case E.Kind and 16#7F# is      --  bit 7: initial state event
            when 1 =>                   --  button
               if E.Number < 32 then
                  if E.Value /= 0 then
                     Buttons := Buttons or Shift_Left (1, Natural (E.Number));
                  else
                     Buttons := Buttons and
                       not Shift_Left (1, Natural (E.Number));
                  end if;
               end if;
            when 2 =>                   --  axis
               case E.Number is
                  when 0 => Axis_X := Integer (E.Value);
                  when 1 => Axis_Y := Integer (E.Value);
                  when 6 => Hat_X := Integer (E.Value);   --  gamepad D-pad
                  when 7 => Hat_Y := Integer (E.Value);
                  when others => null;
               end case;
            when others =>
               null;
         end case;
      end loop;
      Update;
   end Poll;

end Host_Joystick;
