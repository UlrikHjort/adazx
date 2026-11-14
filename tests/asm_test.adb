-- ***************************************************************************
--                             AdaZX - Asm_Test
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

--  Round trip: every Z80 instruction is disassembled, the text assembled
--  again and the bytes compared.

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Interfaces; use Interfaces;
with Types; use Types;
with Disasm;
with Asm;

procedure Asm_Test is
   Mem : Byte_Array (0 .. 65535) := (others => 0);
   function Rd (A : Word) return Byte is (Mem (Natural (A)));
   Fails, Tested : Natural := 0;

   procedure Check (Bytes : Byte_Array) is
      Len : Natural;
      Base : constant Word := 16#8000#;
   begin
      Mem (16#8000# .. 16#8000# + Bytes'Length - 1) := Bytes;
      Mem (16#8000# + Bytes'Length .. 16#8010#) := (others => 16#12#);
      declare
         Text : constant String :=
           Disasm.Instruction (Rd'Unrestricted_Access, Base, Len);
      begin
         if Text = "NOP*" then
            return;
         end if;
         Tested := Tested + 1;
         Asm.Assemble_Text (" org $8000" & ASCII.LF & " " & Text, "t.asm");
         declare
            Ok : Boolean := not Asm.Has_Errors and then Asm.Has_Output;
            Out_Len : constant Natural :=
              (if Ok then Natural (Asm.High_Address) - 16#8000# + 1 else 0);
         begin
            if Ok then
               --  the bytes must disassemble to the same text (several
               --  undocumented encodings mean the same instruction)
               declare
                  Save : constant Byte_Array := Mem (16#8000# .. 16#8010#);
                  L2 : Natural;
               begin
                  for K in 0 .. Out_Len - 1 loop
                     Mem (16#8000# + K) := Asm.Output_Byte (Base + Word (K));
                  end loop;
                  Ok := Disasm.Instruction (Rd'Unrestricted_Access, Base, L2)
                    = Text and then L2 = Out_Len;
                  Mem (16#8000# .. 16#8010#) := Save;
               end;
            end if;
            if not Ok then
               Fails := Fails + 1;
               if Fails <= 40 then
                  Put (Text & "  expected");
                  for K in 0 .. Len - 1 loop
                     Put (" " & Disasm.Hex2 (Mem (16#8000# + K)));
                  end loop;
                  if Asm.Has_Errors then
                     Put ("  error: " & Asm.Error_Text (1));
                  elsif Asm.Has_Output then
                     Put ("  got");
                     for A in 16#8000# .. Natural (Asm.High_Address) loop
                        Put (" " & Disasm.Hex2 (Asm.Output_Byte (Word (A))));
                     end loop;
                  end if;
                  New_Line;
               end if;
            end if;
         end;
      end;
   end Check;

   function Uses_HL (Op : Byte) return Boolean is
      --  opcodes whose DD / FD form differs from the plain one
      Mem2 : Byte_Array (0 .. 3) := (Op, 16#12#, 16#34#, 16#56#);
      pragma Unreferenced (Mem2);
   begin
      return True;
   end Uses_HL;
begin
   for Op in Byte loop
      if Op not in 16#CB# | 16#DD# | 16#ED# | 16#FD# then
         Check ((Op, 16#12#, 16#34#));
      end if;
      Check ((16#CB#, Op));
      Check ((16#ED#, Op, 16#12#, 16#34#));
      Check ((16#DD#, 16#CB#, 16#05#, Op));
      Check ((16#FD#, 16#CB#, 16#FB#, Op));
   end loop;
   --  DD / FD forms: only those that disassemble differently from the
   --  plain opcode
   for Op in Byte loop
      if Op not in 16#CB# | 16#DD# | 16#ED# | 16#FD# and then Uses_HL (Op) then
         declare
            L1, L2 : Natural;
         begin
            Mem (0 .. 3) := (Op, 16#05#, 16#34#, 16#12#);
            Mem (16 .. 19) := (16#DD#, Op, 16#05#, 16#34#);
            Mem (20) := 16#12#;
            if Disasm.Instruction (Rd'Unrestricted_Access, 0, L1)
              /= Disasm.Instruction (Rd'Unrestricted_Access, 16, L2)
            then
               declare
                  DD : constant Byte_Array (0 .. 4) :=
                    (16#DD#, Op, 16#05#, 16#34#, 16#12#);
                  FD : constant Byte_Array (0 .. 4) :=
                    (16#FD#, Op, 16#05#, 16#34#, 16#12#);
               begin
                  Check (DD (0 .. L2 - 1));
                  Check (FD (0 .. L2 - 1));
               end;
            end if;
         end;
      end if;
   end loop;
   Put_Line ("tested" & Tested'Image & " instructions," & Fails'Image &
             " failures");
   Ada.Command_Line.Set_Exit_Status
     (if Fails = 0 then Ada.Command_Line.Success
      else Ada.Command_Line.Failure);
end Asm_Test;
