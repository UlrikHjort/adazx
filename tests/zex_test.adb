-- ***************************************************************************
--                             AdaZX - Zex_Test
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

--  Runs a CP/M instruction exerciser (zexdoc.com / zexall.com) on the Z80
--  core with a minimal BDOS (functions 2 and 9).

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Interfaces; use Interfaces;
with Types; use Types;
with Tstates;
with Z80;

procedure Zex_Test is
   Mem : Byte_Array (0 .. 16#FFFF#) := (others => 0);
   function Read (Addr : Word) return Byte is (Mem (Natural (Addr)));
   procedure Write (Addr : Word; Value : Byte) is
   begin
      Mem (Natural (Addr)) := Value;
   end Write;
   function No_Delay (Addr : Word) return Natural is (0);
   function In_Port (Port : Word) return Byte is
   begin
      Tstates.T := Tstates.T + 4;
      return Hi (Port);
   end In_Port;
   procedure Out_Port (Port : Word; Value : Byte) is
   begin
      Tstates.T := Tstates.T + 4;
   end Out_Port;
   function Int_Data return Byte is (16#FF#);
   package CPU is new Z80 (Read, Write, Read, No_Delay, No_Delay,
                           In_Port, Out_Port, Int_Data);
   package SIO renames Ada.Streams.Stream_IO;
   F : SIO.File_Type;
   Errors : Natural := 0;
   Line : String (1 .. 200);
   Line_Len : Natural := 0;
   procedure Out_Char (C : Character) is
   begin
      if C = ASCII.LF then
         Put_Line (Line (1 .. Line_Len));
         if Line_Len >= 5 and then
           (for some K in 1 .. Line_Len - 4 => Line (K .. K + 4) = "ERROR")
         then
            Errors := Errors + 1;
         end if;
         Line_Len := 0;
      elsif C /= ASCII.CR and then Line_Len < Line'Last then
         Line_Len := Line_Len + 1;
         Line (Line_Len) := C;
      end if;
   end Out_Char;
begin
   SIO.Open (F, SIO.In_File, Argument (1));
   declare
      N : constant Natural := Natural (SIO.Size (F));
      D : Byte_Array (0 .. N - 1);
   begin
      Byte_Array'Read (SIO.Stream (F), D);
      Mem (16#100# .. 16#100# + N - 1) := D;
   end;
   SIO.Close (F);
   Mem (0) := 16#76#;               --  warm boot: HALT
   Mem (5) := 16#C9#;               --  BDOS: RET (trapped below)
   Mem (6) := 16#00#; Mem (7) := 16#F0#;   --  top of TPA
   CPU.Reset;
   CPU.PC := 16#100#;
   CPU.SP := 16#F000#;
   loop
      if CPU.PC = 5 then
         case CPU.C is
            when 2 => Out_Char (Character'Val (CPU.E));
            when 9 =>
               declare
                  A : Word := CPU.DE;
               begin
                  while Mem (Natural (A)) /= Character'Pos ('$') loop
                     Out_Char (Character'Val (Mem (Natural (A))));
                     A := A + 1;
                  end loop;
               end;
            when others => null;
         end case;
      end if;
      exit when CPU.PC = 0;
      CPU.Step;
      if Tstates.T > 1_000_000_000 then
         Tstates.T := 0;
      end if;
   end loop;
   Put_Line ("errors:" & Errors'Image);
   Set_Exit_Status (if Errors = 0 then Success else Failure);
end Zex_Test;
