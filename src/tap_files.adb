-- ***************************************************************************
--                             AdaZX - Tap_Files
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

with Basic;
with Interfaces; use Interfaces;

package body Tap_Files is

   function Block (Flag : Byte; Data : Byte_Array) return Byte_Array is
      Parity : Byte := Flag;
      Len : constant Natural := Data'Length + 2;
   begin
      for B of Data loop
         Parity := Parity xor B;
      end loop;
      return Byte_Array'(Byte (Len mod 256), Byte (Len / 256), Flag)
        & Data & Byte_Array'(1 => Parity);
   end Block;

   function Header (Kind : Byte; Name : String;
                    Length, Param1, Param2 : Natural) return Byte_Array is
      H : Byte_Array (0 .. 16) := (others => 32);
   begin
      H (0) := Kind;
      for K in 1 .. Natural'Min (10, Name'Length) loop
         H (K) := Character'Pos (Name (Name'First + K - 1));
      end loop;
      H (11) := Byte (Length mod 256);
      H (12) := Byte (Length / 256 mod 256);
      H (13) := Byte (Param1 mod 256);
      H (14) := Byte (Param1 / 256 mod 256);
      H (15) := Byte (Param2 mod 256);
      H (16) := Byte (Param2 / 256 mod 256);
      return Block (0, H);
   end Header;

   function Program (Name : String; Basic_Text : String;
                     Autostart : Natural := 10) return Byte_Array is
   begin
      Basic.Tokenize_Text (Basic_Text, Basic.Spectrum);
      declare
         P : constant Byte_Array := Basic.Program;
      begin
         return Header (0, Name, P'Length, Autostart, P'Length)
           & Block (16#FF#, P);
      end;
   end Program;

   function Code (Name : String; Data : Byte_Array; Load : Natural)
                  return Byte_Array is
     (Header (3, Name, Data'Length, Load, 32768) & Block (16#FF#, Data));

end Tap_Files;
