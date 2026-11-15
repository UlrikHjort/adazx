-- ***************************************************************************
--                           AdaZX - Disasm_Export
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

with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.IO_Exceptions;
with Interfaces; use Interfaces;

package body Disasm_Export is

   function Hex4 (W : Word) return String renames Disasm.Hex4;

   procedure Export (Read : Disasm.Reader; From, To : Word;
                     Entries : Address_List; Executed : Executed_Func;
                     Path : String; Ok : out Boolean;
                     Code_Bytes : out Natural) is
      type Flags is array (Word range From .. To) of Boolean;
      Start : Flags := (others => False);   --  an instruction starts here
      Code : Flags := (others => False);    --  byte of an instruction
      Label : Flags := (others => False);
      Placed : Flags := (others => False);  --  its label is on a line

      Work : array (1 .. 65_536) of Word;
      Work_N : Natural := 0;

      procedure Push (A : Word) is
      begin
         if A in From .. To and then not Code (A) and then Work_N < Work'Last
         then
            Work_N := Work_N + 1;
            Work (Work_N) := A;
         end if;
      end Push;

      --  The $XXXX operand at the end of a flow instruction / in ($XXXX)
      function Operand (Text : String; Paren : Boolean) return Integer is
         P : constant Natural :=
           (if Paren then Index (Text, "($") else Index (Text, "$",
                                                         Ada.Strings.Backward));
         S : constant Natural := (if Paren then P + 2 else P + 1);
         E : Natural := S;
      begin
         if P = 0 then
            return -1;
         end if;
         while E <= Text'Last and then Text (E) in '0' .. '9' | 'A' .. 'F'
         loop
            E := E + 1;
         end loop;
         if E - S /= 4 and then E - S /= 2 then
            return -1;
         end if;
         return Integer'Value ("16#" & Text (S .. E - 1) & "#");
      end Operand;

      function Mnemonic (Text : String) return String is
        (if Index (Text, " ") = 0 then Text
         else Text (Text'First .. Index (Text, " ") - 1));

      function Is_Flow (M : String) return Boolean is
        (M = "JP" or else M = "JR" or else M = "CALL" or else M = "DJNZ"
         or else M = "RST");

      function Ends_Path (Text : String) return Boolean is
         M : constant String := Mnemonic (Text);
      begin
         return Text = "RET" or else M = "RETI" or else M = "RETN"
           or else ((M = "JP" or else M = "JR")
                    and then Index (Text, ",") = 0);
      end Ends_Path;

      procedure Trace is
         A : Word;
         Len : Natural;
      begin
         while Work_N > 0 loop
            A := Work (Work_N);
            Work_N := Work_N - 1;
            loop
               exit when Code (A);
               declare
                  Text : constant String := Disasm.Instruction (Read, A, Len);
                  M : constant String := Mnemonic (Text);
               begin
                  exit when Natural (A) + Len - 1 > Natural (To);
                  Start (A) := True;
                  for K in 0 .. Len - 1 loop
                     Code (A + Word (K)) := True;
                  end loop;
                  if Is_Flow (M) and then Index (Text, "(") = 0 then
                     declare
                        T : constant Integer := Operand (Text, False);
                     begin
                        if T >= 0 then
                           if Word (T) in From .. To then
                              Label (Word (T)) := True;
                           end if;
                           Push (Word (T));
                        end if;
                     end;
                  end if;
                  exit when Ends_Path (Text)
                    or else Natural (A) + Len > Natural (To);
                  A := A + Word (Len);
               end;
            end loop;
         end loop;
      end Trace;

      F : Ada.Text_IO.File_Type;
      Body_Text : Unbounded_String;
      NL : constant String := (1 => ASCII.LF);

      function Name (A : Word) return String is ("L" & Hex4 (A));

      --  The instruction with label names for in-range targets / (nn)
      function With_Labels (Text : String) return String is
         M : constant String := Mnemonic (Text);
         Paren : constant Boolean := not Is_Flow (M);
         T : constant Integer := Operand (Text, Paren);
         Num : constant String :=
           (if T > 255 or else (T >= 0 and then not Paren and then M /= "RST")
            then "$" & Hex4 (Word (T)) else "");
         P : constant Natural := (if Num /= "" then Index (Text, Num) else 0);
      begin
         if T < 0 or else Num = "" or else P = 0
           or else Word (T) not in From .. To or else not Label (Word (T))
         then
            return Text;
         end if;
         return Text (Text'First .. P - 1) & Name (Word (T))
           & Text (P + Num'Length .. Text'Last);
      end With_Labels;

      procedure Line (S : String) is
      begin
         Append (Body_Text, S & NL);
      end Line;

      A : Natural := Natural (From);
      Len : Natural;
   begin
      Code_Bytes := 0;
      for E of Entries loop
         Push (E);
      end loop;
      if Executed /= null then
         for X in From .. To loop
            if Executed (X) then
               Push (X);
            end if;
         end loop;
      end if;
      Trace;
      --  Data labels: (nn) operands of the code that point into the range
      for X in From .. To loop
         if Start (X) then
            declare
               Text : constant String := Disasm.Instruction (Read, X, Len);
               T : constant Integer := Operand (Text, True);
            begin
               if Index (Text, "($") > 0 and then T >= 0
                 and then Word (T) in From .. To
               then
                  Label (Word (T)) := True;
               end if;
            end;
         end if;
      end loop;

      while A <= Natural (To) loop
         declare
            W : constant Word := Word (A);
         begin
            if Label (W) then
               Line (Name (W) & ":");
               Placed (W) := True;
            end if;
            if Start (W) then
               declare
                  Text : constant String := Disasm.Instruction (Read, W, Len);
               begin
                  Line ("            " & With_Labels (Text));
                  Code_Bytes := Code_Bytes + Len;
                  A := A + Len;
               end;
            else
               --  data up to the next code, label or 8 bytes; text as a
               --  string when it is all printable
               declare
                  Stop : Natural := A + 1;
                  Text_Run : Boolean := True;
               begin
                  while Stop <= Natural (To) and then Stop - A < 16
                    and then not Start (Word (Stop))
                    and then not Label (Word (Stop))
                  loop
                     Stop := Stop + 1;
                  end loop;
                  for K in A .. Stop - 1 loop
                     declare
                        B : constant Byte := Read (Word (K));
                     begin
                        if B not in 32 .. 126 or else B = 34 then
                           Text_Run := False;
                        end if;
                     end;
                  end loop;
                  if Text_Run and then Stop - A >= 4 then
                     declare
                        S : Unbounded_String;
                     begin
                        for K in A .. Stop - 1 loop
                           Append (S, Character'Val (Read (Word (K))));
                        end loop;
                        Line ("            db """ & To_String (S) & """");
                     end;
                  else
                     declare
                        S : Unbounded_String;
                     begin
                        for K in A .. Stop - 1 loop
                           if K > A then
                              Append (S, ",");
                           end if;
                           Append (S, "$" & Disasm.Hex2 (Read (Word (K))));
                        end loop;
                        Line ("            db " & To_String (S));
                     end;
                  end if;
                  A := Stop;
               end;
            end if;
         end;
      end loop;

      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line
        (F, "; $" & Hex4 (From) & " - $" & Hex4 (To) &
            " disassembled by AdaZX (Forge); assembles to the same bytes");
      Ada.Text_IO.New_Line (F);
      for X in From .. To loop
         if Label (X) and then not Placed (X) then   --  inside an instruction
            Ada.Text_IO.Put_Line
              (F, Name (X) & (1 .. 12 - Name (X)'Length => ' ') & "equ $" &
                  Hex4 (X));
         end if;
      end loop;
      Ada.Text_IO.New_Line (F);
      Ada.Text_IO.Put_Line (F, "            org $" & Hex4 (From));
      Ada.Text_IO.Put (F, To_String (Body_Text));
      Ada.Text_IO.Close (F);
      Ok := True;
   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Ok := False;
   end Export;

end Disasm_Export;
