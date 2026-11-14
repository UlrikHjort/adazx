-- ***************************************************************************
--                              AdaZX - P_Files
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

with Ada.Streams.Stream_IO;
with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Memory;
with Interfaces; use Interfaces;

package body P_Files is

   package SIO renames Ada.Streams.Stream_IO;

   Image : Byte_Array_Access := null;
   Image_Name : Unbounded_String;
   Last_Loaded : Word := 16#4009#;
   Rec : Byte_Array_Access := null;

   procedure Insert (Path : String; Ok : out Boolean) is
      F : SIO.File_Type;
   begin
      SIO.Open (F, SIO.In_File, Path);
      declare
         N : constant Natural := Natural (SIO.Size (F));
      begin
         Image := new Byte_Array (0 .. N - 1);
         Byte_Array'Read (SIO.Stream (F), Image.all);
      end;
      SIO.Close (F);
      --  .81 / .p81 files start with the program name (last char + 128)
      if Image'Length > 0 and then Image (0) /= 0 then
         for K in Image'Range loop
            if Image (K) >= 128 then
               Image := new Byte_Array'(Image (K + 1 .. Image'Last));
               exit;
            end if;
         end loop;
      end if;
      Image_Name := To_Unbounded_String (Ada.Directories.Simple_Name (Path));
      Ok := Image'Length > 16#407D# - 16#4009#;
   exception
      when others =>
         Ok := False;
   end Insert;

   procedure Set_Image (Data : Byte_Array) is
   begin
      Image := new Byte_Array'(Data);
      Image_Name := To_Unbounded_String ("(program)");
   end Set_Image;

   procedure Eject is
   begin
      Image := null;
      Image_Name := Null_Unbounded_String;
   end Eject;

   function Loaded return Boolean is (Image /= null);
   function Name return String is (To_String (Image_Name));

   procedure Load_Into_Memory is
      A : Word := 16#4009#;
   begin
      if Image = null then
         return;
      end if;
      for B of Image.all loop
         Memory.Write (A, B);
         A := A + 1;
      end loop;
      Last_Loaded := A - 1;
   end Load_Into_Memory;

   function Last_Address return Word is (Last_Loaded);

   procedure Record_Memory is
      E_Line : constant Word :=
        Make_Word (Memory.Read (16#4014#), Memory.Read (16#4015#));
   begin
      if E_Line > 16#4009# then
         Rec := new Byte_Array (0 .. Natural (E_Line - 16#4009#) - 1);
         for K in Rec'Range loop
            Rec (K) := Memory.Read (16#4009# + Word (K));
         end loop;
      end if;
   end Record_Memory;

   function Recorded return Natural is
     (if Rec = null then 0 else Rec'Length);

   procedure Save_Recording (Path : String; Ok : out Boolean) is
      F : SIO.File_Type;
   begin
      Ok := Rec /= null;
      if Ok then
         SIO.Create (F, SIO.Out_File, Path);
         Byte_Array'Write (SIO.Stream (F), Rec.all);
         SIO.Close (F);
      end if;
   exception
      when others =>
         Ok := False;
   end Save_Recording;

end P_Files;
