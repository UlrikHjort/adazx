-- ***************************************************************************
--                              AdaZX - Disasm
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

with Interfaces; use Interfaces;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Disasm is

   Digits_H : constant String := "0123456789ABCDEF";

   function Hex2 (B : Byte) return String is
     (Digits_H (Natural (Shift_Right (B, 4)) + 1)
      & Digits_H (Natural (B and 15) + 1));
   function Hex4 (W : Word) return String is (Hex2 (Hi (W)) & Hex2 (Lo (W)));

   R8 : constant array (0 .. 7) of String (1 .. 4) :=
     ("B   ", "C   ", "D   ", "E   ", "H   ", "L   ", "(HL)", "A   ");
   RP : constant array (0 .. 3) of String (1 .. 2) := ("BC", "DE", "HL", "SP");
   RP2 : constant array (0 .. 3) of String (1 .. 2) :=
     ("BC", "DE", "HL", "AF");
   CC : constant array (0 .. 7) of String (1 .. 2) :=
     ("NZ", "Z ", "NC", "C ", "PO", "PE", "P ", "M ");
   ALU : constant array (0 .. 7) of String (1 .. 6) :=
     ("ADD A,", "ADC A,", "SUB   ", "SBC A,", "AND   ", "XOR   ",
      "OR    ", "CP    ");
   ROT : constant array (0 .. 7) of String (1 .. 3) :=
     ("RLC", "RRC", "RL ", "RR ", "SLA", "SRA", "SLL", "SRL");

   function T (S : String) return String is
      L : Natural := S'Last;
   begin
      while L >= S'First and then S (L) = ' ' loop
         L := L - 1;
      end loop;
      return S (S'First .. L);
   end T;

   function Instruction (Read : Reader; Addr : Word;
                         Length : out Natural) return String is
      Pos : Word := Addr;
      Xm : Natural := 0;     --  0 HL, 1 IX, 2 IY
      Disp_Text : Unbounded_String;
      Has_Disp : Boolean := False;

      function Next return Byte is
         V : constant Byte := Read (Pos);
      begin
         Pos := Pos + 1;
         return V;
      end Next;

      function N8 return String is ("$" & Hex2 (Next));
      function N16 return String is
         L : constant Byte := Next;
         H : constant Byte := Next;
      begin
         return "$" & Hex4 (Make_Word (L, H));
      end N16;

      function Idx return String is
        (case Xm is when 1 => "IX", when 2 => "IY", when others => "HL");

      function Mem_HL return String is
      begin
         if Xm = 0 then
            return "(HL)";
         end if;
         if not Has_Disp then
            declare
               D : constant Byte := Next;
            begin
               Disp_Text := To_Unbounded_String
                 (if D < 128 then "+$" & Hex2 (D) else "-$" & Hex2 (-D));
               Has_Disp := True;
            end;
         end if;
         return "(" & Idx & To_String (Disp_Text) & ")";
      end Mem_HL;

      function Reg (N : Natural; Allow_Index : Boolean := True)
        return String is
      begin
         if N = 6 then
            return Mem_HL;
         elsif Allow_Index and then Xm /= 0 and then N in 4 .. 5 then
            return Idx & (if N = 4 then "H" else "L");
         end if;
         return T (R8 (N));
      end Reg;

      function RP_Name (P : Natural) return String is
        (if P = 2 then Idx else RP (P));

      Op : Byte;
      Result : Unbounded_String;
   begin
      Op := Next;
      while Op = 16#DD# or else Op = 16#FD# loop
         Xm := (if Op = 16#DD# then 1 else 2);
         Op := Next;
      end loop;

      declare
         X : Natural := Natural (Shift_Right (Op, 6));
         Y : Natural := Natural (Shift_Right (Op, 3) and 7);
         Z : Natural := Natural (Op and 7);
         P : Natural := Y / 2;
         Q : Natural := Y mod 2;
      begin
         if Op = 16#CB# then
            declare
               M : constant String := (if Xm /= 0 then Mem_HL else "");
               Op2 : constant Byte := Next;
               Target : constant String :=
                 (if Xm /= 0 then M else Reg (Natural (Op2 and 7), False));
               Copy : constant String :=
                 (if Xm /= 0 and then (Op2 and 7) /= 6
                  and then Shift_Right (Op2, 6) /= 1
                  then "," & T (R8 (Natural (Op2 and 7))) else "");
            begin
               X := Natural (Shift_Right (Op2, 6));
               Y := Natural (Shift_Right (Op2, 3) and 7);
               case X is
                  when 0 => Result := To_Unbounded_String
                       (T (ROT (Y)) & " " & Target & Copy);
                  when 1 => Result := To_Unbounded_String
                       ("BIT" & Y'Image & "," & Target);
                  when 2 => Result := To_Unbounded_String
                       ("RES" & Y'Image & "," & Target & Copy);
                  when others => Result := To_Unbounded_String
                       ("SET" & Y'Image & "," & Target & Copy);
               end case;
            end;
         elsif Op = 16#ED# then
            Op := Next;
            X := Natural (Shift_Right (Op, 6));
            Y := Natural (Shift_Right (Op, 3) and 7);
            Z := Natural (Op and 7);
            P := Y / 2;
            Q := Y mod 2;
            if X = 1 then
               case Z is
                  when 0 => Result := To_Unbounded_String
                       (if Y = 6 then "IN (C)" else "IN " & T (R8 (Y)) & ",(C)");
                  when 1 => Result := To_Unbounded_String
                       (if Y = 6 then "OUT (C),0"
                        else "OUT (C)," & T (R8 (Y)));
                  when 2 => Result := To_Unbounded_String
                       ((if Q = 0 then "SBC HL," else "ADC HL,") & RP (P));
                  when 3 =>
                     declare
                        N : constant String := N16;
                     begin
                        Result := To_Unbounded_String
                          (if Q = 0 then "LD (" & N & ")," & RP (P)
                           else "LD " & RP (P) & ",(" & N & ")");
                     end;
                  when 4 => Result := To_Unbounded_String ("NEG");
                  when 5 => Result := To_Unbounded_String
                       (if Y = 1 then "RETI" else "RETN");
                  when 6 => Result := To_Unbounded_String
                       ("IM " & (case Y is when 0 | 1 | 4 | 5 => "0",
                                    when 2 | 6 => "1", when others => "2"));
                  when others =>
                     Result := To_Unbounded_String
                       (case Y is
                           when 0 => "LD I,A", when 1 => "LD R,A",
                           when 2 => "LD A,I", when 3 => "LD A,R",
                           when 4 => "RRD", when 5 => "RLD",
                           when others => "NOP*");
               end case;
            elsif X = 2 and then Z <= 3 and then Y >= 4 then
               declare
                  Names : constant array (0 .. 3, 4 .. 7) of String (1 .. 4) :=
                    (("LDI ", "LDD ", "LDIR", "LDDR"),
                     ("CPI ", "CPD ", "CPIR", "CPDR"),
                     ("INI ", "IND ", "INIR", "INDR"),
                     ("OUTI", "OUTD", "OTIR", "OTDR"));
               begin
                  Result := To_Unbounded_String (T (Names (Z, Y)));
               end;
            else
               Result := To_Unbounded_String ("NOP*");
            end if;
         else
            case X is
               when 0 =>
                  case Z is
                     when 0 =>
                        case Y is
                           when 0 => Result := To_Unbounded_String ("NOP");
                           when 1 => Result := To_Unbounded_String ("EX AF,AF'");
                           when others =>
                              declare
                                 D : constant Byte := Next;
                                 Target : constant Word :=
                                   Pos + (if D < 128 then Word (D)
                                          else Word (D) or 16#FF00#);
                                 Dest : constant String := "$" & Hex4 (Target);
                              begin
                                 Result := To_Unbounded_String
                                   (if Y = 2 then "DJNZ " & Dest
                                    elsif Y = 3 then "JR " & Dest
                                    else "JR " & T (CC (Y - 4)) & "," & Dest);
                              end;
                        end case;
                     when 1 =>
                        Result := To_Unbounded_String
                          (if Q = 0 then "LD " & RP_Name (P) & "," & N16
                           else "ADD " & Idx & "," & RP_Name (P));
                     when 2 =>
                        case Y is
                           when 0 => Result := To_Unbounded_String ("LD (BC),A");
                           when 1 => Result := To_Unbounded_String ("LD A,(BC)");
                           when 2 => Result := To_Unbounded_String ("LD (DE),A");
                           when 3 => Result := To_Unbounded_String ("LD A,(DE)");
                           when 4 => Result := To_Unbounded_String
                                ("LD (" & N16 & ")," & Idx);
                           when 5 => Result := To_Unbounded_String
                                ("LD " & Idx & ",(" & N16 & ")");
                           when 6 => Result := To_Unbounded_String
                                ("LD (" & N16 & "),A");
                           when others => Result := To_Unbounded_String
                                ("LD A,(" & N16 & ")");
                        end case;
                     when 3 =>
                        Result := To_Unbounded_String
                          ((if Q = 0 then "INC " else "DEC ") & RP_Name (P));
                     when 4 => Result := To_Unbounded_String ("INC " & Reg (Y));
                     when 5 => Result := To_Unbounded_String ("DEC " & Reg (Y));
                     when 6 =>
                        declare
                           R : constant String := Reg (Y);
                        begin
                           Result := To_Unbounded_String ("LD " & R & "," & N8);
                        end;
                     when others =>
                        Result := To_Unbounded_String
                          (case Y is
                              when 0 => "RLCA", when 1 => "RRCA",
                              when 2 => "RLA", when 3 => "RRA",
                              when 4 => "DAA", when 5 => "CPL",
                              when 6 => "SCF", when others => "CCF");
                  end case;
               when 1 =>
                  if Op = 16#76# then
                     Result := To_Unbounded_String ("HALT");
                  elsif Y = 6 or else Z = 6 then
                     declare
                        Dst : constant String :=
                          (if Y = 6 then Mem_HL else T (R8 (Y)));
                        Src : constant String :=
                          (if Z = 6 then Mem_HL else T (R8 (Z)));
                     begin
                        Result := To_Unbounded_String ("LD " & Dst & "," & Src);
                     end;
                  else
                     Result := To_Unbounded_String
                       ("LD " & Reg (Y) & "," & Reg (Z));
                  end if;
               when 2 =>
                  Result := To_Unbounded_String (T (ALU (Y)) &
                    (if ALU (Y) (6) = ',' then "" else " ") & Reg (Z));
               when others =>
                  case Z is
                     when 0 => Result := To_Unbounded_String
                          ("RET " & T (CC (Y)));
                     when 1 =>
                        if Q = 0 then
                           Result := To_Unbounded_String
                             ("POP " & (if P = 2 then Idx else RP2 (P)));
                        else
                           Result := To_Unbounded_String
                             (case P is
                                 when 0 => "RET",
                                 when 1 => "EXX",
                                 when 2 => "JP (" & Idx & ")",
                                 when others => "LD SP," & Idx);
                        end if;
                     when 2 => Result := To_Unbounded_String
                          ("JP " & T (CC (Y)) & "," & N16);
                     when 3 =>
                        case Y is
                           when 0 => Result := To_Unbounded_String ("JP " & N16);
                           when 2 => Result := To_Unbounded_String
                                ("OUT (" & N8 & "),A");
                           when 3 => Result := To_Unbounded_String
                                ("IN A,(" & N8 & ")");
                           when 4 => Result := To_Unbounded_String
                                ("EX (SP)," & Idx);
                           when 5 => Result := To_Unbounded_String ("EX DE,HL");
                           when 6 => Result := To_Unbounded_String ("DI");
                           when others => Result := To_Unbounded_String ("EI");
                        end case;
                     when 4 => Result := To_Unbounded_String
                          ("CALL " & T (CC (Y)) & "," & N16);
                     when 5 =>
                        if Q = 0 then
                           Result := To_Unbounded_String
                             ("PUSH " & (if P = 2 then Idx else RP2 (P)));
                        else
                           Result := To_Unbounded_String ("CALL " & N16);
                        end if;
                     when 6 =>
                        Result := To_Unbounded_String
                          (T (ALU (Y)) &
                           (if ALU (Y) (6) = ',' then "" else " ") & N8);
                     when others => Result := To_Unbounded_String
                          ("RST $" & Hex2 (Byte (Y * 8)));
                  end case;
            end case;
         end if;
      end;
      Length := Natural (Pos - Addr);
      return To_String (Result);
   end Instruction;

   procedure Disassemble (Read : Reader; Addr : Word;
                          Text : out String; Last : out Natural;
                          Length : out Natural) is
      Ins : constant String := Instruction (Read, Addr, Length);
      Bytes : Unbounded_String;
   begin
      for K in 0 .. Length - 1 loop
         Append (Bytes, Hex2 (Read (Addr + Word (K))) & " ");
      end loop;
      while Ada.Strings.Unbounded.Length (Bytes) < 13 loop
         Append (Bytes, ' ');
      end loop;
      declare
         S : constant String := Hex4 (Addr) & "  " & To_String (Bytes) & Ins;
      begin
         Last := Text'First + Natural'Min (S'Length, Text'Length) - 1;
         Text (Text'First .. Last) := S (S'First .. S'First + Last - Text'First);
      end;
   end Disassemble;

   function Is_Call (Read : Reader; Addr : Word) return Boolean is
      Op : constant Byte := Read (Addr);
   begin
      if Op = 16#CD# or else (Op and 16#C7#) = 16#C4#
        or else (Op and 16#C7#) = 16#C7# or else Op = 16#10#
      then
         return True;
      elsif Op = 16#ED# then
         declare
            Op2 : constant Byte := Read (Addr + 1);
         begin
            return (Op2 and 16#F4#) = 16#B0#;     --  LDIR CPIR INIR OTIR ...
         end;
      end if;
      return False;
   end Is_Call;

end Disasm;
