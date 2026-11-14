-- ***************************************************************************
--                             AdaZX - Fuse_Test
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

--  Runs Fuse's Z80 core tests (tests/z80/fuse/tests.in) and prints the
--  results in the format of tests.expected (bus events with T-states,
--  final registers, changed memory), so the two can be compared with diff.

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Interfaces; use Interfaces;
with Types; use Types;
with Tstates;
with Z80;

procedure Fuse_Test is

   Mem, Initial : Byte_Array (0 .. 16#FFFF#);

   function H2 (V : Natural) return String is
      D : constant String := "0123456789abcdef";
   begin
      return D (V / 16 mod 16 + 1) & D (V mod 16 + 1);
   end H2;
   function H4 (V : Natural) return String is
     (H2 (V / 256 mod 256) & H2 (V mod 256));

   function Time return String is
      S : constant String := Integer'Image (Tstates.T);
      Pad : constant String (1 .. 5) := (others => ' ');
   begin
      return Pad (1 .. Integer'Max (0, 5 - (S'Length - 1))) &
        S (S'First + 1 .. S'Last);
   end Time;

   procedure Event (Kind : String; Addr : Word) is
   begin
      Put_Line (Time & " " & Kind & " " & H4 (Natural (Addr)));
   end Event;
   procedure Event (Kind : String; Addr : Word; V : Byte) is
   begin
      Put_Line (Time & " " & Kind & " " & H4 (Natural (Addr)) & " " &
                  H2 (Natural (V)));
   end Event;

   function Read (Addr : Word) return Byte is
   begin
      Event ("MR", Addr, Mem (Natural (Addr)));
      return Mem (Natural (Addr));
   end Read;

   procedure Write (Addr : Word; Value : Byte) is
   begin
      Event ("MW", Addr, Value);
      Mem (Natural (Addr)) := Value;
   end Write;

   function Contend (Addr : Word) return Natural is
   begin
      Event ("MC", Addr);
      return 0;
   end Contend;

   procedure Pre_IO (Port : Word) is
   begin
      if (Port and 16#C000#) = 16#4000# then
         Event ("PC", Port);
      end if;
      Tstates.T := Tstates.T + 1;
   end Pre_IO;

   procedure Post_IO (Port : Word) is
   begin
      if (Port and 1) /= 0 then
         if (Port and 16#C000#) = 16#4000# then
            for K in 1 .. 3 loop
               Event ("PC", Port);
               Tstates.T := Tstates.T + 1;
            end loop;
         else
            Tstates.T := Tstates.T + 3;
         end if;
      else
         Event ("PC", Port);
         Tstates.T := Tstates.T + 3;
      end if;
   end Post_IO;

   function In_Port (Port : Word) return Byte is
      V : constant Byte := Hi (Port);
   begin
      Pre_IO (Port);
      Event ("PR", Port, V);
      Post_IO (Port);
      return V;
   end In_Port;

   procedure Out_Port (Port : Word; Value : Byte) is
   begin
      Pre_IO (Port);
      Event ("PW", Port, Value);
      Post_IO (Port);
   end Out_Port;

   function Int_Data return Byte is (16#FF#);

   package CPU is new Z80 (Read, Write, Read, Contend, Contend,
                           In_Port, Out_Port, Int_Data);

   F : File_Type;

   --  Token reader over the input file
   Line : String (1 .. 512);
   Last : Natural := 0;
   Pos  : Natural := 1;

   function Next_Token return String is
   begin
      loop
         while Pos <= Last and then Line (Pos) = ' ' loop
            Pos := Pos + 1;
         end loop;
         exit when Pos <= Last;
         Get_Line (F, Line, Last);
         Pos := 1;
      end loop;
      declare
         Start : constant Natural := Pos;
      begin
         while Pos <= Last and then Line (Pos) /= ' ' loop
            Pos := Pos + 1;
         end loop;
         return Line (Start .. Pos - 1);
      end;
   end Next_Token;

   function Hex (S : String) return Integer is
     (if S = "-1" then -1 else Integer'Value ("16#" & S & "#"));

   procedure Set_Pair (Hi_R, Lo_R : out Byte; V : Integer) is
   begin
      Hi_R := Byte (V / 256);
      Lo_R := Byte (V mod 256);
   end Set_Pair;

   Name : String (1 .. 80);
   Name_Last : Natural;
   End_T : Integer;
begin
   Open (F, In_File, (if Ada.Command_Line.Argument_Count > 0
                      then Ada.Command_Line.Argument (1)
                      else "tests/z80/fuse/tests.in"));
   while not End_Of_File (F) loop
      Get_Line (F, Name, Name_Last);
      if Name_Last > 0 then
         for K in 0 .. 16#FFFF# loop
            Mem (K) := (case K mod 4 is when 0 => 16#DE#, when 1 => 16#AD#,
                           when 2 => 16#BE#, when others => 16#EF#);
         end loop;
         CPU.Reset;
         Tstates.T := 0;
         Set_Pair (CPU.A, CPU.F, Hex (Next_Token));
         Set_Pair (CPU.B, CPU.C, Hex (Next_Token));
         Set_Pair (CPU.D, CPU.E, Hex (Next_Token));
         Set_Pair (CPU.H, CPU.L, Hex (Next_Token));
         Set_Pair (CPU.A2, CPU.F2, Hex (Next_Token));
         Set_Pair (CPU.B2, CPU.C2, Hex (Next_Token));
         Set_Pair (CPU.D2, CPU.E2, Hex (Next_Token));
         Set_Pair (CPU.H2, CPU.L2, Hex (Next_Token));
         CPU.IX := Word (Hex (Next_Token));
         CPU.IY := Word (Hex (Next_Token));
         CPU.SP := Word (Hex (Next_Token));
         CPU.PC := Word (Hex (Next_Token));
         CPU.MEMPTR := Word (Hex (Next_Token));
         CPU.I := Byte (Hex (Next_Token));
         CPU.R := Byte (Hex (Next_Token));
         CPU.IFF1 := Next_Token = "1";
         CPU.IFF2 := Next_Token = "1";
         CPU.IM := Integer'Value (Next_Token);
         CPU.Halted := Next_Token = "1";
         End_T := Integer'Value (Next_Token);
         loop
            declare
               Addr : Integer := Hex (Next_Token);
               V : Integer;
            begin
               exit when Addr < 0;
               loop
                  V := Hex (Next_Token);
                  exit when V < 0;
                  Mem (Addr) := Byte (V);
                  Addr := Addr + 1;
               end loop;
            end;
         end loop;
         Pos := Last + 1;
         Initial := Mem;
         Put_Line (Name (1 .. Name_Last));
         while Tstates.T < End_T loop
            CPU.Step;
         end loop;
         Put_Line (H4 (Natural (CPU.AF)) & " " & H4 (Natural (CPU.BC)) & " " &
                     H4 (Natural (CPU.DE)) & " " & H4 (Natural (CPU.HL)) & " " &
                     H4 (Natural (Make_Word (CPU.F2, CPU.A2))) & " " &
                     H4 (Natural (Make_Word (CPU.C2, CPU.B2))) & " " &
                     H4 (Natural (Make_Word (CPU.E2, CPU.D2))) & " " &
                     H4 (Natural (Make_Word (CPU.L2, CPU.H2))) & " " &
                     H4 (Natural (CPU.IX)) & " " & H4 (Natural (CPU.IY)) & " " &
                     H4 (Natural (CPU.SP)) & " " & H4 (Natural (CPU.PC)) & " " &
                     H4 (Natural (CPU.MEMPTR)));
         Put_Line (H2 (Natural (CPU.I)) & " " & H2 (Natural (CPU.R)) & " " &
                     (if CPU.IFF1 then "1" else "0") & " " &
                     (if CPU.IFF2 then "1" else "0") & " " &
                     Integer'Image (CPU.IM) (2 .. 2) & " " &
                     (if CPU.Halted then "1" else "0") &
                     Integer'Image (Tstates.T));
         declare
            K : Natural := 0;
         begin
            while K <= 16#FFFF# loop
               if Mem (K) /= Initial (K) then
                  Put (H4 (K) & " ");
                  while K <= 16#FFFF# and then Mem (K) /= Initial (K) loop
                     Put (H2 (Natural (Mem (K))) & " ");
                     K := K + 1;
                  end loop;
                  Put_Line ("-1");
               else
                  K := K + 1;
               end if;
            end loop;
         end;
         New_Line;
      end if;
   end loop;
   Close (F);
end Fuse_Test;
