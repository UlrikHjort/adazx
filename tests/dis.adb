-- ***************************************************************************
--                                AdaZX - Dis
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

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Types; use Types;
with Disasm;
with Interfaces; use Interfaces;
procedure Dis is
   Mem : Byte_Array (0 .. 65535) := (others => 0);
   function Rd (A : Word) return Byte is (Mem (Natural (A)));
   package SIO renames Ada.Streams.Stream_IO;
   F : SIO.File_Type;
   A : Word := Word'Value ("16#" & Argument (2) & "#");
   N : constant Natural := Natural'Value (Argument (3));
   T : String (1 .. 80); L, Len : Natural;
begin
   SIO.Open (F, SIO.In_File, Argument (1));
   declare
      D : Byte_Array (0 .. Natural (SIO.Size (F)) - 1);
   begin
      Byte_Array'Read (SIO.Stream (F), D);
      Mem (0 .. D'Last) := D;
   end;
   for I in 1 .. N loop
      Disasm.Disassemble (Rd'Unrestricted_Access, A, T, L, Len);
      Put_Line (T (1 .. L));
      A := A + Word (Len);
   end loop;
end Dis;
