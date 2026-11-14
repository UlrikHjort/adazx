-- ***************************************************************************
--                             AdaZX - Settings
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
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Text_IO; use Ada.Text_IO;

package body Settings is

   package Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type => String, Element_Type => String);

   Values : Maps.Map;

   function Dir return String is
     ((if Ada.Environment_Variables.Exists ("HOME")
       then Ada.Environment_Variables.Value ("HOME") else ".") &
      "/.config/adazx");

   function Path return String is (Dir & "/settings");

   procedure Load is
      F : File_Type;
   begin
      Values.Clear;
      if not Ada.Directories.Exists (Path) then
         return;
      end if;
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         declare
            Line : constant String := Get_Line (F);
            Eq : constant Natural := Ada.Strings.Fixed.Index (Line, "=");
         begin
            if Eq > Line'First and then Line (Line'First) /= '#' then
               Values.Include (Line (Line'First .. Eq - 1),
                               Line (Eq + 1 .. Line'Last));
            end if;
         end;
      end loop;
      Close (F);
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
   end Load;

   procedure Save is
      F : File_Type;
   begin
      if not Ada.Directories.Exists (Dir) then
         Ada.Directories.Create_Path (Dir);
      end if;
      Create (F, Out_File, Path);
      Put_Line (F, "# AdaC64 settings");
      for C in Values.Iterate loop
         Put_Line (F, Maps.Key (C) & "=" & Maps.Element (C));
      end loop;
      Close (F);
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
   end Save;

   function Get (Key : String; Default : String := "") return String is
     (if Values.Contains (Key) then Values.Element (Key) else Default);

   function Get (Key : String; Default : Boolean) return Boolean is
     (if Values.Contains (Key) then Values.Element (Key) = "1" else Default);

   function Get (Key : String; Default : Integer) return Integer is
   begin
      if Values.Contains (Key) then
         return Integer'Value (Values.Element (Key));
      end if;
      return Default;
   exception
      when others => return Default;
   end Get;

   procedure Set (Key : String; Value : String) is
   begin
      Values.Include (Key, Value);
   end Set;

   procedure Set (Key : String; Value : Boolean) is
   begin
      Set (Key, (if Value then "1" else "0"));
   end Set;

   procedure Set (Key : String; Value : Integer) is
   begin
      Set (Key, Ada.Strings.Fixed.Trim (Value'Image, Ada.Strings.Left));
   end Set;

end Settings;
