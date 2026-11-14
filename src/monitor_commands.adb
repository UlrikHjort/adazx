-- ***************************************************************************
--                         AdaZX - Monitor_Commands
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
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Interfaces; use Interfaces;
with Types; use Types;
with Machine;
with Disasm;

package body Monitor_Commands is


   Next_Dis  : Word := 0;
   Next_Mem  : Word := 0;

   procedure Print (S : String) is
   begin
      if Output /= null then
         Output (S);
      end if;
   end Print;

   function Read_Mem (A : Word) return Byte is (Machine.Monitor_Peek (A));

   function Reader return Disasm.Reader is (Read_Mem'Access);

   function Dis_Line (A : Word; Len : out Natural) return String is
      Text : String (1 .. 64);
      Last : Natural;
   begin
      Disasm.Disassemble (Reader, A, Text, Last, Len);
      return Text (1 .. Last);
   end Dis_Line;

   procedure Show_Registers is
   begin
      Print (Machine.Register_Text);
      declare
         Len : Natural;
         PC : constant Word := Machine.CPU_PC;
      begin
         Print ("> " & Dis_Line (PC, Len));
         Next_Dis := PC + Word (Len);
      end;
   end Show_Registers;

   procedure Changed is
   begin
      if On_Change /= null then
         On_Change.all;
      end if;
   end Changed;

   --  Tokenise and parse hexadecimal arguments
   type Arg_List is array (1 .. 40) of Natural;

   procedure Parse (Line : String; Cmd : out Unbounded_String;
                    Args : out Arg_List; Count : out Natural;
                    Bad : out Boolean) is
      I : Natural := Line'First;
      First_Token : Boolean := True;
   begin
      Cmd := Null_Unbounded_String;
      Count := 0;
      Bad := False;
      Args := (others => 0);
      while I <= Line'Last loop
         while I <= Line'Last and then Line (I) in ' ' | ',' loop
            I := I + 1;
         end loop;
         exit when I > Line'Last;
         declare
            J : Natural := I;
         begin
            while J <= Line'Last and then Line (J) not in ' ' | ',' loop
               J := J + 1;
            end loop;
            declare
               Tok : constant String := To_Lower (Line (I .. J - 1));
            begin
               if First_Token then
                  Cmd := To_Unbounded_String (Tok);
                  First_Token := False;
               elsif Count < Args'Last then
                  declare
                     T : constant String :=
                       (if Tok (Tok'First) = '$'
                        then Tok (Tok'First + 1 .. Tok'Last) else Tok);
                  begin
                     Count := Count + 1;
                     Args (Count) := Natural'Value ("16#" & T & "#");
                  exception
                     when others => Bad := True;
                  end;
               end if;
            end;
            I := J;
         end;
      end loop;
   end Parse;

   procedure Execute (Line : String) is
      Cmd : Unbounded_String;
      Args : Arg_List;
      N : Natural;
      Bad : Boolean;
   begin
      Print ("." & Line);
      Parse (Line, Cmd, Args, N, Bad);
      if Bad then
         Print ("?syntax: numbers are hexadecimal");
         return;
      end if;
      declare
         C : constant String := To_String (Cmd);
      begin
         if C = "r" then
            Show_Registers;

         elsif C = "z" or else C = "n" then
            for K in 1 .. (if N >= 1 then Natural'Max (Args (1), 1) else 1)
            loop
               Machine.Step_Instruction;
            end loop;
            Show_Registers;
            Changed;

         elsif C = "d" then
            declare
               A : Word := (if N >= 1 then Word (Args (1) mod 65536)
                            else Next_Dis);
               Len : Natural;
            begin
               for K in 1 .. 16 loop
                  Print (Dis_Line (A, Len));
                  A := A + Word (Len);
               end loop;
               Next_Dis := A;
            end;

         elsif C = "m" then
            declare
               A : Word := (if N >= 1 then Word (Args (1) mod 65536)
                            else Next_Mem);
               Lines : constant Natural :=
                 (if N >= 2 and then Args (2) >= Args (1)
                  then Natural'Min ((Args (2) - Args (1)) / 16 + 1, 256)
                  else 8);
            begin
               for L in 1 .. Lines loop
                  declare
                     Hex, Txt : Unbounded_String;
                     B : Byte;
                  begin
                     for K in 0 .. 15 loop
                        B := Reader (A + Word (K));
                        Append (Hex, " " & Disasm.Hex2 (B));
                        Append (Txt, (if B in 16#20# .. 16#7E#
                                      then Character'Val (B) else '.'));
                     end loop;
                     Print (Disasm.Hex4 (A) & " " & To_String (Hex) & "  " &
                            To_String (Txt));
                  end;
                  A := A + 16;
               end loop;
               Next_Mem := A;
            end;

         elsif C = ">" then
            if N < 2 then
               Print ("?usage: > addr byte ...");
            else
               for K in 2 .. N loop
                  Machine.Monitor_Poke
                    (Word ((Args (1) + K - 2) mod 65536),
                     Byte (Args (K) mod 256));
               end loop;
               Changed;
            end if;

         elsif C = "b" then
            if N >= 1 then
               Machine.Set_Breakpoint (Word (Args (1) mod 65536));
            end if;
            Print ("breakpoints:" & Machine.Breakpoint_List);

         elsif C = "bd" then
            if N >= 1 then
               Machine.Clear_Breakpoint (Word (Args (1) mod 65536));
            else
               Machine.Clear_Breakpoints;
            end if;
            Print ("breakpoints:" & Machine.Breakpoint_List);

         elsif C = "bl" then
            Print ("breakpoints:" & Machine.Breakpoint_List);

         elsif C = "io" then
            Print (Machine.Debug_Info);

         elsif C = "w" then
            if N >= 1 then
               declare
                  To : constant Word :=
                    Word ((if N >= 2 then Args (2) else Args (1)) mod 65536);
               begin
                  Machine.Add_Watch (Word (Args (1) mod 65536), To,
                                     True, True);
               end;
            else
               Machine.Clear_Watches;
            end if;
            Print ("watchpoints:" & Machine.Watch_List);

         elsif C = "g" or else C = "x" then
            if C = "g" and then N >= 1 then
               Machine.Monitor_Set_PC (Word (Args (1) mod 65536));
            end if;
            Machine.Resume;
            Resume_Requested := True;

         elsif C = "h" or else C = "?" or else C = "help" then
            Print ("r regs | z [n] step | d [addr] disasm | m [a [b]] memory" &
                   " | > addr bytes | g [addr] go | x exit");
            Print ("b addr break | bd [addr] delete | bl list |" &
                   " w [a [b]] watch (none = clear) | io chip state");

         elsif C /= "" then
            Print ("?unknown command (h for help)");
         end if;
      end;
   exception
      when others =>
         Print ("?error");
   end Execute;

end Monitor_Commands;
