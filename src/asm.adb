-- ***************************************************************************
--                                AdaZX - Asm
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

with File_Ext;
with Ada.Text_IO;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;
with Interfaces; use Interfaces;
with Basic;
with Basic_ZX80;

package body Asm is

   package SIO renames Ada.Streams.Stream_IO;

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   Mem : Byte_Array (0 .. 65_535) := (others => 0);
   Used : array (0 .. 65_535) of Boolean := (others => False);
   Code_At : array (0 .. 65_535) of Boolean := (others => False);
   Line_File : array (0 .. 65_535) of Natural := (others => 0);
   Line_No : array (0 .. 65_535) of Natural := (others => 0);
   Lowest, Highest : Integer := -1;
   Start : Integer := -1;
   Loader : Boolean := True;
   Out_Name : Unbounded_String;

   type Error_Rec is record
      File : Natural := 0;
      Line : Natural := 0;
      Text : Unbounded_String;
      Warning : Boolean := False;
   end record;
   Errors : array (1 .. 200) of Error_Rec;
   N_Errors : Natural := 0;
   Real_Errors : Natural := 0;

   Files : array (1 .. 64) of Unbounded_String;
   N_Files : Natural := 0;

   ---------------------------------------------------------------------
   --  Symbols
   ---------------------------------------------------------------------

   type Symbol is record
      Value : Integer := 0;
      Pass : Natural := 0;          --  pass it was last defined in
      Redefinable : Boolean := False;
      Is_Label : Boolean := False;
   end record;

   package Symbol_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, Symbol, Ada.Strings.Hash, "=");
   Symbols : Symbol_Maps.Map;

   type Name_Array is array (Positive range <>) of Unbounded_String;
   Sorted : Name_Array (1 .. 8192);
   N_Sorted : Natural := 0;

   Pass : Natural := 0;
   Final : Boolean := False;
   Changed : Boolean := False;    --  a symbol got a new value this pass
   Unknown : Boolean := False;    --  an expression used an undefined name

   PC : Integer := 0;             --  address of the current instruction
   Out_PC : Integer := 0;         --  where the next byte goes
   Global_Label : Unbounded_String;
   Cur_File : Natural := 0;
   Cur_Line : Natural := 0;
   Is_Instruction : Boolean := False;

   Asm_Error : exception;
   Changed_Last : Boolean := True;

   function Disasm_Hex (V : Natural) return String is
      D : constant String := "0123456789ABCDEF";
   begin
      return (D (V / 4096 mod 16 + 1), D (V / 256 mod 16 + 1),
              D (V / 16 mod 16 + 1), D (V mod 16 + 1));
   end Disasm_Hex;

   procedure Add_Error (Text : String; Warning : Boolean := False) is
   begin
      if not Final then
         return;
      end if;
      if N_Errors < Errors'Last then
         N_Errors := N_Errors + 1;
         Errors (N_Errors) := (Cur_File, Cur_Line,
                               To_Unbounded_String (Text), Warning);
      end if;
      if not Warning then
         Real_Errors := Real_Errors + 1;
      end if;
   end Add_Error;

   procedure Fail (Text : String) is
   begin
      Add_Error (Text);
      raise Asm_Error;
   end Fail;

   function Full_Name (Name : String) return String is
     (if Name'Length > 0 and then Name (Name'First) = '.'
      then To_String (Global_Label) & Name else Name);

   procedure Define (Name : String; Value : Integer;
                     Redefinable : Boolean := False;
                     Is_Label : Boolean := False) is
      Full : constant String := Full_Name (Name);
      C : constant Symbol_Maps.Cursor := Symbols.Find (Full);
   begin
      if Symbol_Maps.Has_Element (C) then
         declare
            S : Symbol := Symbol_Maps.Element (C);
         begin
            if S.Pass = Pass and then not S.Redefinable
              and then not Redefinable
            then
               Add_Error ("symbol " & Full & " defined twice");
               return;
            end if;
            if S.Value /= Value and then not Redefinable then
               Changed := True;
            end if;
            S.Value := Value;
            S.Pass := Pass;
            S.Redefinable := Redefinable;
            S.Is_Label := Is_Label;
            Symbols.Replace_Element (C, S);
         end;
      else
         if Pass > 1 and then not Redefinable then
            Changed := True;
         end if;
         Symbols.Insert (Full, (Value, Pass, Redefinable, Is_Label));
      end if;
   end Define;

   function Find_Symbol (Name : String; Value : out Integer) return Boolean
   is
      Full : constant String := Full_Name (Name);
      C : constant Symbol_Maps.Cursor := Symbols.Find (Full);
   begin
      if Symbol_Maps.Has_Element (C) then
         Value := Symbol_Maps.Element (C).Value;
         return True;
      end if;
      Value := 0;
      return False;
   end Find_Symbol;

   ---------------------------------------------------------------------
   --  Expressions
   ---------------------------------------------------------------------

   function Is_Ident_Start (C : Character) return Boolean is
     (Is_Letter (C) or else C = '_' or else C = '.' or else C = '@');
   function Is_Ident (C : Character) return Boolean is
     (Is_Alphanumeric (C) or else C = '_' or else C = '.' or else C = '@'
      or else C = ''');

   function Eval (S : String) return Integer;

   function Eval (S : String) return Integer is
      P : Natural := S'First;

      procedure Skip is
      begin
         while P <= S'Last and then (S (P) = ' ' or else S (P) = ASCII.HT)
         loop
            P := P + 1;
         end loop;
      end Skip;

      function Peek_Op (Op : String) return Boolean is
      begin
         Skip;
         return P + Op'Length - 1 <= S'Last
           and then S (P .. P + Op'Length - 1) = Op;
      end Peek_Op;

      function Take (Op : String) return Boolean is
      begin
         if Peek_Op (Op) then
            P := P + Op'Length;
            return True;
         end if;
         return False;
      end Take;

      function Parse_Or return Integer;

      function Number (Digs : String; Base : Positive) return Integer is
         V : Long_Long_Integer := 0;
      begin
         if Digs'Length = 0 then
            Fail ("bad number in " & S);
         end if;
         for C of Digs loop
            declare
               D : constant Integer :=
                 (case C is
                     when '0' .. '9' => Character'Pos (C) - 48,
                     when 'a' .. 'f' => Character'Pos (C) - 87,
                     when 'A' .. 'F' => Character'Pos (C) - 55,
                     when others => 99);
            begin
               if D >= Base then
                  Fail ("bad digit in number " & Digs);
               end if;
               V := (V * Long_Long_Integer (Base) + Long_Long_Integer (D))
                 mod 2 ** 32;
            end;
         end loop;
         return Integer (V mod 2 ** 31);
      end Number;

      function Primary return Integer is
      begin
         Skip;
         if P > S'Last then
            Fail ("missing value in " & S);
         end if;
         declare
            C : constant Character := S (P);
         begin
            if C = '(' then
               P := P + 1;
               declare
                  V : constant Integer := Parse_Or;
               begin
                  if not Take (")") then
                     Fail ("missing ) in " & S);
                  end if;
                  return V;
               end;
            elsif C = '-' then
               P := P + 1;
               return -Primary;
            elsif C = '+' then
               P := P + 1;
               return Primary;
            elsif C = '~' then
               P := P + 1;
               return -Primary - 1;
            elsif C = '!' then
               P := P + 1;
               return (if Primary = 0 then 1 else 0);
            elsif C = ''' or else C = '"' then
               if P + 2 <= S'Last and then S (P + 2) = C then
                  P := P + 3;
                  return Character'Pos (S (P - 2));
               end if;
               Fail ("bad character constant in " & S);
            elsif C = '$' or else C = '#' then
               P := P + 1;
               if P > S'Last or else not Is_Hexadecimal_Digit (S (P)) then
                  if C = '$' then
                     return PC;
                  end if;
                  Fail ("bad number in " & S);
               end if;
               declare
                  B : constant Natural := P;
               begin
                  while P <= S'Last and then Is_Hexadecimal_Digit (S (P)) loop
                     P := P + 1;
                  end loop;
                  return Number (S (B .. P - 1), 16);
               end;
            elsif C = '%' then
               P := P + 1;
               declare
                  B : constant Natural := P;
               begin
                  while P <= S'Last and then S (P) in '0' | '1' loop
                     P := P + 1;
                  end loop;
                  return Number (S (B .. P - 1), 2);
               end;
            elsif Is_Digit (C) then
               declare
                  B : constant Natural := P;
               begin
                  if C = '0' and then P < S'Last
                    and then S (P + 1) in 'x' | 'X'
                  then
                     P := P + 2;
                     declare
                        B2 : constant Natural := P;
                     begin
                        while P <= S'Last
                          and then Is_Hexadecimal_Digit (S (P))
                        loop
                           P := P + 1;
                        end loop;
                        return Number (S (B2 .. P - 1), 16);
                     end;
                  end if;
                  if C = '0' and then P < S'Last
                    and then S (P + 1) in 'b' | 'B'
                    and then P + 2 <= S'Last and then S (P + 2) in '0' | '1'
                  then
                     P := P + 2;
                     declare
                        B2 : constant Natural := P;
                     begin
                        while P <= S'Last and then S (P) in '0' | '1' loop
                           P := P + 1;
                        end loop;
                        return Number (S (B2 .. P - 1), 2);
                     end;
                  end if;
                  while P <= S'Last and then Is_Hexadecimal_Digit (S (P)) loop
                     P := P + 1;
                  end loop;
                  if P <= S'Last and then S (P) in 'h' | 'H' then
                     P := P + 1;
                     return Number (S (B .. P - 2), 16);
                  end if;
                  --  1010b binary
                  if S (P - 1) in 'b' | 'B'
                    and then (for all K in B .. P - 2 => S (K) in '0' | '1')
                    and then P - 2 >= B
                  then
                     return Number (S (B .. P - 2), 2);
                  end if;
                  return Number (S (B .. P - 1), 10);
               end;
            elsif Is_Ident_Start (C) then
               declare
                  B : constant Natural := P;
               begin
                  while P <= S'Last and then Is_Ident (S (P)) loop
                     P := P + 1;
                  end loop;
                  declare
                     Name : constant String := S (B .. P - 1);
                     U : constant String := To_Upper (Name);
                     V : Integer;
                  begin
                     if (U = "LOW" or else U = "HIGH") and then Peek_Op ("(")
                     then
                        V := Primary;
                        return (if U = "LOW" then V mod 256
                                else (V mod 65536) / 256);
                     elsif U = "DEFINED" and then Take ("(") then
                        Skip;
                        declare
                           B2 : constant Natural := P;
                           Dummy : Integer;
                        begin
                           while P <= S'Last and then Is_Ident (S (P)) loop
                              P := P + 1;
                           end loop;
                           declare
                              N2 : constant String := S (B2 .. P - 1);
                           begin
                              if not Take (")") then
                                 Fail ("missing ) in " & S);
                              end if;
                              return (if Find_Symbol (N2, Dummy) then 1 else 0);
                           end;
                        end;
                     end if;
                     if not Find_Symbol (Name, V) then
                        Unknown := True;
                        if Final then
                           Fail ("undefined symbol " & Name);
                        end if;
                     end if;
                     return V;
                  end;
               end;
            else
               Fail ("syntax error in expression " & S);
            end if;
         end;
         return 0;
      end Primary;

      function Mul return Integer is
         V : Integer := Primary;
      begin
         loop
            if Take ("*") then
               V := V * Primary;
            elsif Take ("/") then
               declare
                  D : constant Integer := Primary;
               begin
                  if D = 0 then
                     Fail ("division by zero");
                  end if;
                  V := V / D;
               end;
            elsif Take ("%") then
               declare
                  D : constant Integer := Primary;
               begin
                  if D = 0 then
                     Fail ("division by zero");
                  end if;
                  V := V mod D;
               end;
            else
               return V;
            end if;
         end loop;
      end Mul;

      function Add return Integer is
         V : Integer := Mul;
      begin
         loop
            if Take ("+") then
               V := V + Mul;
            elsif Peek_Op ("-") then
               P := P + 1;
               V := V - Mul;
            else
               return V;
            end if;
         end loop;
      end Add;

      function Shift return Integer is
         V : Integer := Add;
      begin
         loop
            if Take ("<<") then
               V := Integer (Shift_Left (Unsigned_32'Mod (V), Add mod 32)
                             and 16#7FFF_FFFF#);
            elsif Take (">>") then
               V := Integer (Shift_Right (Unsigned_32'Mod (V), Add mod 32)
                             and 16#7FFF_FFFF#);
            else
               return V;
            end if;
         end loop;
      end Shift;

      function Compare return Integer is
         V : Integer := Shift;
         function B (X : Boolean) return Integer is (if X then 1 else 0);
      begin
         loop
            if Take ("<=") then
               V := B (V <= Shift);
            elsif Take (">=") then
               V := B (V >= Shift);
            elsif Take ("<>") or else Take ("!=") then
               V := B (V /= Shift);
            elsif Take ("==") or else Take ("=") then
               V := B (V = Shift);
            elsif Take ("<") then
               V := B (V < Shift);
            elsif Take (">") then
               V := B (V > Shift);
            else
               return V;
            end if;
         end loop;
      end Compare;

      function Bit_And return Integer is
         V : Integer := Compare;
      begin
         while not Peek_Op ("&&") and then Take ("&") loop
            V := Integer (Unsigned_32'Mod (V) and Unsigned_32'Mod (Compare)
                          and 16#7FFF_FFFF#);
         end loop;
         return V;
      end Bit_And;

      function Bit_Xor return Integer is
         V : Integer := Bit_And;
      begin
         while Take ("^") loop
            V := Integer ((Unsigned_32'Mod (V) xor Unsigned_32'Mod (Bit_And))
                          and 16#7FFF_FFFF#);
         end loop;
         return V;
      end Bit_Xor;

      function Bit_Or return Integer is
         V : Integer := Bit_Xor;
      begin
         while not Peek_Op ("||") and then Take ("|") loop
            V := Integer ((Unsigned_32'Mod (V) or Unsigned_32'Mod (Bit_Xor))
                          and 16#7FFF_FFFF#);
         end loop;
         return V;
      end Bit_Or;

      function Parse_Or return Integer is
         V : Integer := Bit_Or;
      begin
         loop
            if Take ("&&") then
               V := (if V /= 0 and then Bit_Or /= 0 then 1 else 0);
            elsif Take ("||") then
               declare
                  R : constant Integer := Bit_Or;
               begin
                  V := (if V /= 0 or else R /= 0 then 1 else 0);
               end;
            else
               return V;
            end if;
         end loop;
      end Parse_Or;

      V : Integer;
   begin
      V := Parse_Or;
      Skip;
      if P <= S'Last then
         Fail ("unexpected " & S (P .. S'Last) & " in expression");
      end if;
      return V;
   exception
      when Constraint_Error =>
         Fail ("value out of range in " & S);
         return 0;
   end Eval;

   ---------------------------------------------------------------------
   --  Output
   ---------------------------------------------------------------------

   procedure Emit (B : Integer) is
      A : constant Integer := Out_PC mod 65_536;
   begin
      if Final then
         Mem (A) := Byte (B mod 256);
         if Used (A) then
            Add_Error ("address $" & Disasm_Hex (A) & " written twice", True);
         end if;
         Used (A) := True;
         Code_At (A) := Code_At (A) or else
           (Is_Instruction and then Out_PC = PC);
         if Line_File (A) = 0 or else Out_PC = PC then
            Line_File (A) := Cur_File;
            Line_No (A) := Cur_Line;
         end if;
         if Lowest < 0 or else A < Lowest then
            Lowest := A;
         end if;
         if A > Highest then
            Highest := A;
         end if;
      end if;
      Out_PC := Out_PC + 1;
   end Emit;

   procedure Emit_Word (V : Integer) is
   begin
      Emit (V mod 256);
      Emit ((V mod 65536) / 256);     --  (mod: right for negative values)
   end Emit_Word;

   ---------------------------------------------------------------------
   --  Lexical helpers
   ---------------------------------------------------------------------

   --  Split operands at top-level commas
   type Op_List is array (1 .. 64) of Unbounded_String;

   procedure Split (S : String; Ops : out Op_List; N : out Natural) is
      Depth : Natural := 0;
      Quote : Character := ASCII.NUL;
      Start : Natural := S'First;
   begin
      N := 0;
      if Trim (S, Ada.Strings.Both)'Length = 0 then
         return;
      end if;
      for K in S'Range loop
         declare
            C : constant Character := S (K);
         begin
            if Quote /= ASCII.NUL then
               if C = Quote then
                  Quote := ASCII.NUL;
               end if;
            elsif C = '"' then
               Quote := C;
            elsif C = ''' and then K + 2 <= S'Last and then S (K + 2) = '''
              and then not (K > S'First and then Is_Alphanumeric (S (K - 1)))
            then
               Quote := C;
            elsif C = '(' then
               Depth := Depth + 1;
            elsif C = ')' and then Depth > 0 then
               Depth := Depth - 1;
            elsif C = ',' and then Depth = 0 then
               N := N + 1;
               Ops (N) := To_Unbounded_String
                 (Trim (S (Start .. K - 1), Ada.Strings.Both));
               Start := K + 1;
            end if;
         end;
      end loop;
      N := N + 1;
      Ops (N) := To_Unbounded_String (Trim (S (Start .. S'Last),
                                            Ada.Strings.Both));
   end Split;

   --  Remove a comment (outside strings / character constants)
   function Strip_Comment (S : String) return String is
      Quote : Character := ASCII.NUL;
   begin
      for K in S'Range loop
         declare
            C : constant Character := S (K);
         begin
            if Quote /= ASCII.NUL then
               if C = Quote then
                  Quote := ASCII.NUL;
               end if;
            elsif C = '"' then
               Quote := C;
            elsif C = ''' and then K + 2 <= S'Last and then S (K + 2) = '''
              and then not (K > S'First and then Is_Alphanumeric (S (K - 1)))
            then
               Quote := C;
            elsif C = ';' then
               return S (S'First .. K - 1);
            end if;
         end;
      end loop;
      return S;
   end Strip_Comment;

   ---------------------------------------------------------------------
   --  Operands
   ---------------------------------------------------------------------

   type Op_Kind is (None, R8, R16, Reg_I, Reg_R, Ind_BC, Ind_DE, Ind_HL,
                    Ind_SP, Ind_C, Ind_Idx, Ind_Mem, Imm, Reg_AF2);

   type Operand is record
      Kind : Op_Kind := None;
      Reg : Natural := 0;          --  R8: 0..7, R16: 0 BC 1 DE 2 HL 3 SP 4 AF
      Index : Natural := 0;        --  0 none, 1 IX, 2 IY
      Value : Integer := 0;
      Text : Unbounded_String;
   end record;

   function Is_Wrapped (S : String) return Boolean is
      Depth : Natural := 0;
   begin
      if S'Length < 2 or else S (S'First) /= '(' or else S (S'Last) /= ')'
      then
         return False;
      end if;
      for K in S'Range loop
         if S (K) = '(' then
            Depth := Depth + 1;
         elsif S (K) = ')' then
            Depth := Depth - 1;
            if Depth = 0 and then K /= S'Last then
               return False;
            end if;
         end if;
      end loop;
      return True;
   end Is_Wrapped;

   function Classify (S : String) return Operand is
      U : constant String := To_Upper (S);
      R : Operand;
   begin
      R.Text := To_Unbounded_String (S);
      if U = "" then
         return R;
      end if;
      declare
         Names8 : constant array (0 .. 7) of String (1 .. 1) :=
           ("B", "C", "D", "E", "H", "L", "?", "A");
      begin
         for K in Names8'Range loop
            if U = Names8 (K) then
               R.Kind := R8;
               R.Reg := K;
               return R;
            end if;
         end loop;
      end;
      if U = "IXH" or else U = "XH" or else U = "HX" then
         return (R8, 4, 1, 0, R.Text);
      elsif U = "IXL" or else U = "XL" or else U = "LX" then
         return (R8, 5, 1, 0, R.Text);
      elsif U = "IYH" or else U = "YH" or else U = "HY" then
         return (R8, 4, 2, 0, R.Text);
      elsif U = "IYL" or else U = "YL" or else U = "LY" then
         return (R8, 5, 2, 0, R.Text);
      elsif U = "I" then
         R.Kind := Reg_I;
      elsif U = "R" then
         R.Kind := Reg_R;
      elsif U = "BC" then
         return (R16, 0, 0, 0, R.Text);
      elsif U = "DE" then
         return (R16, 1, 0, 0, R.Text);
      elsif U = "HL" then
         return (R16, 2, 0, 0, R.Text);
      elsif U = "SP" then
         return (R16, 3, 0, 0, R.Text);
      elsif U = "AF" then
         return (R16, 4, 0, 0, R.Text);
      elsif U = "AF'" then
         R.Kind := Reg_AF2;
      elsif U = "IX" then
         return (R16, 2, 1, 0, R.Text);
      elsif U = "IY" then
         return (R16, 2, 2, 0, R.Text);
      elsif Is_Wrapped (S) then
         declare
            Inner : constant String :=
              Trim (S (S'First + 1 .. S'Last - 1), Ada.Strings.Both);
            UI : constant String := To_Upper (Inner);
         begin
            if UI = "BC" then
               R.Kind := Ind_BC;
            elsif UI = "DE" then
               R.Kind := Ind_DE;
            elsif UI = "HL" then
               R.Kind := Ind_HL;
            elsif UI = "SP" then
               R.Kind := Ind_SP;
            elsif UI = "C" then
               R.Kind := Ind_C;
            elsif UI'Length >= 2 and then (UI (UI'First .. UI'First + 1) = "IX"
                                          or else UI (UI'First .. UI'First + 1)
                                          = "IY")
              and then (UI'Length = 2
                        or else UI (UI'First + 2) in '+' | '-' | ' ')
            then
               R.Kind := Ind_Idx;
               R.Index := (if UI (UI'First + 1) = 'X' then 1 else 2);
               declare
                  Rest : constant String :=
                    Trim (Inner (Inner'First + 2 .. Inner'Last),
                          Ada.Strings.Both);
               begin
                  R.Value := (if Rest = "" then 0 else Eval ("0" & Rest));
                  if Final and then R.Value not in -128 .. 127 then
                     Add_Error ("index offset out of range");
                  end if;
               end;
            else
               R.Kind := Ind_Mem;
               R.Value := Eval (Inner);
            end if;
         end;
      else
         R.Kind := Imm;
         R.Value := Eval (S);
      end if;
      return R;
   end Classify;

   function Cond_Code (S : String; Found : out Boolean) return Natural is
      U : constant String := To_Upper (S);
      Names : constant array (0 .. 7) of String (1 .. 2) :=
        ("NZ", "Z ", "NC", "C ", "PO", "PE", "P ", "M ");
   begin
      Found := True;
      for K in Names'Range loop
         if U = Trim (Names (K), Ada.Strings.Right) then
            return K;
         end if;
      end loop;
      Found := False;
      return 0;
   end Cond_Code;

   ---------------------------------------------------------------------
   --  Instructions
   ---------------------------------------------------------------------

   procedure Prefix (Index : Natural) is
   begin
      if Index = 1 then
         Emit (16#DD#);
      elsif Index = 2 then
         Emit (16#FD#);
      end if;
   end Prefix;

   procedure Disp (O : Operand) is
   begin
      Emit (O.Value mod 256);
   end Disp;

   procedure Bad is
   begin
      Fail ("invalid operands");
   end Bad;

   function Byte_Value (V : Integer) return Integer is
   begin
      if Final and then V not in -128 .. 255 then
         Add_Error ("byte value out of range", True);
      end if;
      return V mod 256;
   end Byte_Value;

   --  8-bit "source / target" operand: register, (HL) or (IX+d).
   --  Emits the prefix; returns the register code (6 for memory).
   procedure Check_Index_Mix (A, B : Operand) is
   begin
      if A.Kind = R8 and then B.Kind = R8 and then A.Index /= B.Index
        and then A.Index /= 0 and then B.Index /= 0
      then
         Bad;
      end if;
      if (A.Kind = R8 and then A.Index /= 0 and then B.Kind = R8
          and then B.Index = 0 and then B.Reg in 4 .. 5)
        or else (B.Kind = R8 and then B.Index /= 0 and then A.Kind = R8
                 and then A.Index = 0 and then A.Reg in 4 .. 5)
      then
         Bad;
      end if;
   end Check_Index_Mix;

   procedure Alu_Op (Op : Natural; X : Operand) is
   begin
      case X.Kind is
         when R8 =>
            Prefix (X.Index);
            Emit (16#80# + Op * 8 + X.Reg);
         when Ind_HL =>
            Emit (16#86# + Op * 8);
         when Ind_Idx =>
            Prefix (X.Index);
            Emit (16#86# + Op * 8);
            Disp (X);
         when Imm =>
            Emit (16#C6# + Op * 8);
            Emit (Byte_Value (X.Value));
         when others => Bad;
      end case;
   end Alu_Op;

   procedure CB_Op (Base : Natural; X : Operand; Copy : Operand) is
   begin
      case X.Kind is
         when R8 =>
            if X.Index /= 0 then
               Bad;
            end if;
            Emit (16#CB#);
            Emit (Base + X.Reg);
         when Ind_HL =>
            Emit (16#CB#);
            Emit (Base + 6);
         when Ind_Idx =>
            Prefix (X.Index);
            Emit (16#CB#);
            Disp (X);
            if Copy.Kind = R8 and then Copy.Index = 0 then
               Emit (Base + Copy.Reg);
            elsif Copy.Kind = None then
               Emit (Base + 6);
            else
               Bad;
            end if;
         when others => Bad;
      end case;
   end CB_Op;

   procedure Relative (Op : Natural; Target : Integer) is
      Offset : constant Integer := Target - (PC + 2);
   begin
      Emit (Op);
      if Final and then Offset not in -128 .. 127 then
         Add_Error ("relative jump out of range (" & Offset'Image & ")");
      end if;
      Emit (Offset mod 256);
   end Relative;

   procedure Instruction (Mn : String; Ops : Op_List; N : Natural) is
      function Op (I : Positive) return Operand is
        (if I <= N then Classify (To_String (Ops (I))) else (others => <>));
      function Raw (I : Positive) return String is
        (if I <= N then To_String (Ops (I)) else "");
      procedure Need (Count : Natural) is
      begin
         if N /= Count then
            Fail (Mn & " needs" & Count'Image & " operand" &
                  (if Count = 1 then "" else "s"));
         end if;
      end Need;
   begin
      Is_Instruction := True;
      --  No operands
      declare
         type Pair is record
            Name : String (1 .. 4);
            Code : Natural;      --  > 255: ED prefixed
         end record;
         Table : constant array (Positive range <>) of Pair :=
           (("NOP ", 16#00#), ("HALT", 16#76#), ("DI  ", 16#F3#),
            ("EI  ", 16#FB#), ("EXX ", 16#D9#), ("DAA ", 16#27#),
            ("CPL ", 16#2F#), ("SCF ", 16#37#), ("CCF ", 16#3F#),
            ("RLCA", 16#07#), ("RRCA", 16#0F#), ("RLA ", 16#17#),
            ("RRA ", 16#1F#), ("NEG ", 16#ED44#), ("RETI", 16#ED4D#),
            ("RETN", 16#ED45#), ("RRD ", 16#ED67#), ("RLD ", 16#ED6F#),
            ("LDI ", 16#EDA0#), ("CPI ", 16#EDA1#), ("INI ", 16#EDA2#),
            ("OUTI", 16#EDA3#), ("LDD ", 16#EDA8#), ("CPD ", 16#EDA9#),
            ("IND ", 16#EDAA#), ("OUTD", 16#EDAB#), ("LDIR", 16#EDB0#),
            ("CPIR", 16#EDB1#), ("INIR", 16#EDB2#), ("OTIR", 16#EDB3#),
            ("LDDR", 16#EDB8#), ("CPDR", 16#EDB9#), ("INDR", 16#EDBA#),
            ("OTDR", 16#EDBB#));
      begin
         for E of Table loop
            if Trim (E.Name, Ada.Strings.Right) = Mn then
               if N /= 0 and then not (Mn = "NEG" and then N = 1) then
                  Fail (Mn & " takes no operands");
               end if;
               if E.Code > 255 then
                  Emit (16#ED#);
               end if;
               Emit (E.Code mod 256);
               return;
            end if;
         end loop;
      end;

      if Mn = "LD" then
         Need (2);
         declare
            D : constant Operand := Op (1);
            S : constant Operand := Op (2);
         begin
            Check_Index_Mix (D, S);
            if D.Kind = R8 and then S.Kind = R8 then
               Prefix (Natural'Max (D.Index, S.Index));
               Emit (16#40# + D.Reg * 8 + S.Reg);
            elsif D.Kind = R8 and then S.Kind = Imm then
               Prefix (D.Index);
               Emit (16#06# + D.Reg * 8);
               Emit (Byte_Value (S.Value));
            elsif D.Kind = R8 and then D.Index = 0 and then S.Kind = Ind_HL then
               Emit (16#46# + D.Reg * 8);
            elsif D.Kind = R8 and then D.Index = 0 and then S.Kind = Ind_Idx
            then
               Prefix (S.Index);
               Emit (16#46# + D.Reg * 8);
               Disp (S);
            elsif D.Kind = Ind_HL and then S.Kind = R8 and then S.Index = 0
            then
               Emit (16#70# + S.Reg);
            elsif D.Kind = Ind_Idx and then S.Kind = R8 and then S.Index = 0
            then
               Prefix (D.Index);
               Emit (16#70# + S.Reg);
               Disp (D);
            elsif D.Kind = Ind_HL and then S.Kind = Imm then
               Emit (16#36#);
               Emit (Byte_Value (S.Value));
            elsif D.Kind = Ind_Idx and then S.Kind = Imm then
               Prefix (D.Index);
               Emit (16#36#);
               Disp (D);
               Emit (Byte_Value (S.Value));
            elsif D.Kind = R8 and then D.Reg = 7 and then D.Index = 0 then
               case S.Kind is
                  when Ind_BC => Emit (16#0A#);
                  when Ind_DE => Emit (16#1A#);
                  when Ind_Mem => Emit (16#3A#); Emit_Word (S.Value);
                  when Reg_I => Emit (16#ED#); Emit (16#57#);
                  when Reg_R => Emit (16#ED#); Emit (16#5F#);
                  when others => Bad;
               end case;
            elsif S.Kind = R8 and then S.Reg = 7 and then S.Index = 0 then
               case D.Kind is
                  when Ind_BC => Emit (16#02#);
                  when Ind_DE => Emit (16#12#);
                  when Ind_Mem => Emit (16#32#); Emit_Word (D.Value);
                  when Reg_I => Emit (16#ED#); Emit (16#47#);
                  when Reg_R => Emit (16#ED#); Emit (16#4F#);
                  when others => Bad;
               end case;
            elsif D.Kind = R16 and then D.Reg <= 3 and then S.Kind = Imm then
               Prefix (D.Index);
               Emit (16#01# + D.Reg * 16);
               Emit_Word (S.Value);
            elsif D.Kind = R16 and then D.Reg <= 3 and then S.Kind = Ind_Mem
            then
               if D.Reg = 2 then
                  Prefix (D.Index);
                  Emit (16#2A#);
               else
                  Emit (16#ED#);
                  Emit (16#4B# + D.Reg * 16);
               end if;
               Emit_Word (S.Value);
            elsif D.Kind = Ind_Mem and then S.Kind = R16 and then S.Reg <= 3
            then
               if S.Reg = 2 then
                  Prefix (S.Index);
                  Emit (16#22#);
               else
                  Emit (16#ED#);
                  Emit (16#43# + S.Reg * 16);
               end if;
               Emit_Word (D.Value);
            elsif D.Kind = R16 and then D.Reg = 3 and then S.Kind = R16
              and then S.Reg = 2
            then
               Prefix (S.Index);
               Emit (16#F9#);
            else
               Bad;
            end if;
         end;

      elsif Mn = "PUSH" or else Mn = "POP" then
         Need (1);
         declare
            R : constant Operand := Op (1);
            Base : constant Natural := (if Mn = "PUSH" then 16#C5# else 16#C1#);
         begin
            if R.Kind /= R16 or else R.Reg = 3 then
               Bad;
            end if;
            Prefix (R.Index);
            Emit (Base + (if R.Reg = 4 then 3 else R.Reg) * 16);
         end;

      elsif Mn = "EX" then
         Need (2);
         declare
            A : constant Operand := Op (1);
            B : constant Operand := Op (2);
         begin
            if A.Kind = R16 and then A.Reg = 4 and then B.Kind = Reg_AF2 then
               Emit (16#08#);
            elsif A.Kind = R16 and then A.Reg = 1 and then B.Kind = R16
              and then B.Reg = 2 and then B.Index = 0
            then
               Emit (16#EB#);
            elsif A.Kind = Ind_SP and then B.Kind = R16 and then B.Reg = 2 then
               Prefix (B.Index);
               Emit (16#E3#);
            else
               Bad;
            end if;
         end;

      elsif Mn in "ADD" | "ADC" | "SUB" | "SBC" | "AND" | "XOR" | "OR" | "CP"
      then
         declare
            Code : constant Natural :=
              (if Mn = "ADD" then 0 elsif Mn = "ADC" then 1
               elsif Mn = "SUB" then 2 elsif Mn = "SBC" then 3
               elsif Mn = "AND" then 4 elsif Mn = "XOR" then 5
               elsif Mn = "OR" then 6 else 7);
            A : constant Operand := Op (1);
         begin
            if N = 2 and then A.Kind = R16 and then A.Reg = 2 then
               declare
                  B : constant Operand := Op (2);
                  P : Natural;
               begin
                  if B.Kind /= R16 or else B.Reg > 3 then
                     Bad;
                  end if;
                  P := B.Reg;
                  if P = 2 and then B.Index /= A.Index then
                     Bad;
                  end if;
                  if Code = 0 then
                     Prefix (A.Index);
                     Emit (16#09# + P * 16);
                  elsif (Code = 1 or else Code = 3) and then A.Index = 0 then
                     Emit (16#ED#);
                     Emit ((if Code = 1 then 16#4A# else 16#42#) + P * 16);
                  else
                     Bad;
                  end if;
               end;
            elsif N = 2 then
               if A.Kind /= R8 or else A.Reg /= 7 or else A.Index /= 0 then
                  Bad;
               end if;
               Alu_Op (Code, Op (2));
            else
               Need (1);
               Alu_Op (Code, A);
            end if;
         end;

      elsif Mn = "INC" or else Mn = "DEC" then
         Need (1);
         declare
            X : constant Operand := Op (1);
            D : constant Natural := (if Mn = "INC" then 0 else 1);
         begin
            case X.Kind is
               when R8 =>
                  Prefix (X.Index);
                  Emit (16#04# + X.Reg * 8 + D);
               when Ind_HL => Emit (16#34# + D);
               when Ind_Idx =>
                  Prefix (X.Index);
                  Emit (16#34# + D);
                  Disp (X);
               when R16 =>
                  if X.Reg > 3 then
                     Bad;
                  end if;
                  Prefix (X.Index);
                  Emit (16#03# + X.Reg * 16 + D * 8);
               when others => Bad;
            end case;
         end;

      elsif Mn = "JP" then
         if N = 1 then
            declare
               X : constant Operand := Op (1);
            begin
               if X.Kind = Ind_HL then
                  Emit (16#E9#);
               elsif X.Kind = Ind_Idx and then X.Value = 0 then
                  Prefix (X.Index);
                  Emit (16#E9#);
               elsif X.Kind = R16 and then X.Reg = 2 then
                  Prefix (X.Index);
                  Emit (16#E9#);
               elsif X.Kind in Imm | Ind_Mem then
                  Emit (16#C3#);
                  Emit_Word (X.Value);
               else
                  Bad;
               end if;
            end;
         else
            Need (2);
            declare
               Found : Boolean;
               C : constant Natural := Cond_Code (Raw (1), Found);
            begin
               if not Found then
                  Bad;
               end if;
               Emit (16#C2# + C * 8);
               Emit_Word (Eval (Raw (2)));
            end;
         end if;

      elsif Mn = "JR" then
         if N = 1 then
            Relative (16#18#, Eval (Raw (1)));
         else
            Need (2);
            declare
               Found : Boolean;
               C : constant Natural := Cond_Code (Raw (1), Found);
            begin
               if not Found or else C > 3 then
                  Bad;
               end if;
               Relative (16#20# + C * 8, Eval (Raw (2)));
            end;
         end if;

      elsif Mn = "DJNZ" then
         Need (1);
         Relative (16#10#, Eval (Raw (1)));

      elsif Mn = "CALL" then
         if N = 1 then
            Emit (16#CD#);
            Emit_Word (Eval (Raw (1)));
         else
            Need (2);
            declare
               Found : Boolean;
               C : constant Natural := Cond_Code (Raw (1), Found);
            begin
               if not Found then
                  Bad;
               end if;
               Emit (16#C4# + C * 8);
               Emit_Word (Eval (Raw (2)));
            end;
         end if;

      elsif Mn = "RET" then
         if N = 0 then
            Emit (16#C9#);
         else
            Need (1);
            declare
               Found : Boolean;
               C : constant Natural := Cond_Code (Raw (1), Found);
            begin
               if not Found then
                  Bad;
               end if;
               Emit (16#C0# + C * 8);
            end;
         end if;

      elsif Mn = "RST" then
         Need (1);
         declare
            V : constant Integer := Eval (Raw (1));
         begin
            if V mod 8 /= 0 or else V not in 0 .. 16#38# then
               Fail ("RST needs 0, 8, 16, ... 56");
            end if;
            Emit (16#C7# + V);
         end;

      elsif Mn = "IM" then
         Need (1);
         case Eval (Raw (1)) is
            when 0 => Emit (16#ED#); Emit (16#46#);
            when 1 => Emit (16#ED#); Emit (16#56#);
            when 2 => Emit (16#ED#); Emit (16#5E#);
            when others => Fail ("IM 0, 1 or 2");
         end case;

      elsif Mn = "IN" then
         if N = 1 and then Op (1).Kind = Ind_C then
            Emit (16#ED#);
            Emit (16#70#);
         else
            Need (2);
            declare
               D : constant Operand :=
                 (if To_Upper (Raw (1)) = "F" then (others => <>) else Op (1));
               S : constant Operand := Op (2);
            begin
               if To_Upper (Raw (1)) = "F" and then S.Kind = Ind_C then
                  Emit (16#ED#);
                  Emit (16#70#);
               elsif D.Kind = R8 and then D.Index = 0 and then S.Kind = Ind_C
               then
                  Emit (16#ED#);
                  Emit (16#40# + D.Reg * 8);
               elsif D.Kind = R8 and then D.Reg = 7 and then D.Index = 0
                 and then S.Kind = Ind_Mem
               then
                  Emit (16#DB#);
                  Emit (Byte_Value (S.Value));
               else
                  Bad;
               end if;
            end;
         end if;

      elsif Mn = "OUT" then
         Need (2);
         declare
            D : constant Operand := Op (1);
            S : constant Operand := Op (2);
         begin
            if D.Kind = Ind_C and then S.Kind = R8 and then S.Index = 0 then
               Emit (16#ED#);
               Emit (16#41# + S.Reg * 8);
            elsif D.Kind = Ind_C and then S.Kind = Imm and then S.Value = 0
            then
               Emit (16#ED#);
               Emit (16#71#);
            elsif D.Kind = Ind_Mem and then S.Kind = R8 and then S.Reg = 7
              and then S.Index = 0
            then
               Emit (16#D3#);
               Emit (Byte_Value (D.Value));
            else
               Bad;
            end if;
         end;

      elsif Mn in "RLC" | "RRC" | "RL" | "RR" | "SLA" | "SRA" | "SLL" | "SL1"
        | "SLI" | "SRL"
      then
         declare
            Code : constant Natural :=
              (if Mn = "RLC" then 0 elsif Mn = "RRC" then 1
               elsif Mn = "RL" then 2 elsif Mn = "RR" then 3
               elsif Mn = "SLA" then 4 elsif Mn = "SRA" then 5
               elsif Mn = "SRL" then 7 else 6);
         begin
            if N < 1 or else N > 2 then
               Bad;
            end if;
            CB_Op (Code * 8, Op (1), Op (2));
         end;

      elsif Mn in "BIT" | "RES" | "SET" then
         if N < 2 or else N > 3 then
            Bad;
         end if;
         declare
            B : constant Integer := Eval (Raw (1));
            Base : constant Natural :=
              (if Mn = "BIT" then 16#40# elsif Mn = "RES" then 16#80#
               else 16#C0#);
         begin
            if B not in 0 .. 7 then
               Fail ("bit number must be 0 .. 7");
            end if;
            if Mn = "BIT" and then N = 3 then
               Bad;
            end if;
            CB_Op (Base + B * 8, Op (2), Op (3));
         end;

      else
         Fail ("unknown instruction " & Mn);
      end if;
   end Instruction;

   ---------------------------------------------------------------------
   --  Source files, macros and directives
   ---------------------------------------------------------------------

   type Line_Array is array (Positive range <>) of Unbounded_String;
   type Line_Array_Access is access Line_Array;

   type Source_File is record
      Lines : Line_Array_Access;
   end record;
   Sources : array (1 .. 64) of Source_File;

   type Macro is record
      Name : Unbounded_String;
      Params : Op_List;
      N_Params : Natural := 0;
      Body_Lines : Line_Array_Access;
      File, First_Line : Natural := 0;
   end record;
   Macros : array (1 .. 256) of Macro;
   N_Macros : Natural := 0;
   Macro_Counter : Natural := 0;

   Main_Text : Unbounded_String;
   Main_Is_Text : Boolean := False;

   function Split_Lines (Text : String) return Line_Array_Access is
      Count : Natural := 1;
   begin
      for C of Text loop
         if C = ASCII.LF then
            Count := Count + 1;
         end if;
      end loop;
      declare
         R : constant Line_Array_Access := new Line_Array (1 .. Count);
         Start : Natural := Text'First;
         K : Natural := 1;
      begin
         for I in Text'Range loop
            if Text (I) = ASCII.LF then
               R (K) := To_Unbounded_String (Text (Start .. I - 1));
               K := K + 1;
               Start := I + 1;
            end if;
         end loop;
         R (K) := To_Unbounded_String (Text (Start .. Text'Last));
         for L of R.all loop
            declare
               S : String := To_String (L);
            begin
               for Ch of S loop
                  if Ch = ASCII.HT or else Ch = ASCII.CR then
                     Ch := ' ';
                  end if;
               end loop;
               L := To_Unbounded_String (S);
            end;
         end loop;
         return R;
      end;
   end Split_Lines;

   function Read_Text (Path : String) return String is
      F : SIO.File_Type;
   begin
      SIO.Open (F, SIO.In_File, Path);
      declare
         S : String (1 .. Natural (SIO.Size (F)));
      begin
         String'Read (SIO.Stream (F), S);
         SIO.Close (F);
         return S;
      end;
   end Read_Text;

   function Load_File (Path : String) return Natural is
      Full : constant String := Ada.Directories.Full_Name (Path);
   begin
      for I in 1 .. N_Files loop
         if To_String (Files (I)) = Full then
            return I;
         end if;
      end loop;
      if N_Files = Files'Last then
         Fail ("too many files");
      end if;
      N_Files := N_Files + 1;
      Files (N_Files) := To_Unbounded_String (Full);
      if N_Files = 1 and then Main_Is_Text then
         Sources (1).Lines := Split_Lines (To_String (Main_Text));
      else
         Sources (N_Files).Lines := Split_Lines (Read_Text (Path));
      end if;
      return N_Files;
   exception
      when Asm_Error => raise;
      when others =>
         N_Files := N_Files - 1;
         Fail ("cannot read " & Path);
         return 0;
   end Load_File;

   function Relative_Path (Name : String) return String is
   begin
      if Name'Length > 0 and then Name (Name'First) = '/' then
         return Name;
      end if;
      if Cur_File > 0 then
         return Ada.Directories.Containing_Directory
           (To_String (Files (Cur_File))) & "/" & Name;
      end if;
      return Name;
   end Relative_Path;

   function Unquote (S : String) return String is
      T : constant String := Trim (S, Ada.Strings.Both);
   begin
      if T'Length >= 2 and then T (T'First) = '"' and then T (T'Last) = '"'
      then
         return T (T'First + 1 .. T'Last - 1);
      end if;
      Fail ("string expected: " & S);
      return "";
   end Unquote;

   --  DB-style data: numbers, "strings"
   procedure Data_Bytes (Ops : Op_List; N : Natural; Mode : Character) is
      Last_At : Integer := -1;
   begin
      for I in 1 .. N loop
         declare
            S : constant String := To_String (Ops (I));
         begin
            if S'Length >= 2 and then S (S'First) = '"'
              and then S (S'Last) = '"'
            then
               for C of S (S'First + 1 .. S'Last - 1) loop
                  Last_At := Out_PC;
                  Emit (Character'Pos (C));
               end loop;
            elsif S'Length > 0 then
               Last_At := Out_PC;
               Emit (Byte_Value (Eval (S)));
            end if;
         end;
      end loop;
      if Mode = 'Z' then
         Emit (0);
      elsif Mode = 'C' and then Last_At >= 0 and then Final then
         Mem (Last_At mod 65536) := Mem (Last_At mod 65536) or 16#80#;
      end if;
   end Data_Bytes;

   --  Conditional assembly
   type Cond_State is record
      Active : Boolean;        --  this branch assembles
      Done : Boolean;          --  a branch was taken
      Parent : Boolean;        --  enclosing block active
   end record;
   Conds : array (1 .. 64) of Cond_State;
   N_Conds : Natural := 0;

   function Active return Boolean is
     (N_Conds = 0 or else Conds (N_Conds).Active);

   Ended : Boolean := False;

   procedure Process_Lines (Lines : Line_Array; File : Natural;
                            First_Line : Natural; Depth : Natural;
                            Macro_Args : Op_List; N_Args : Natural;
                            Arg_Names : Op_List; N_Names : Natural);

   function Substitute (S : String; Args : Op_List; N_Args : Natural;
                        Names : Op_List; N_Names : Natural) return String is
      R : Unbounded_String;
      I : Natural := S'First;
   begin
      while I <= S'Last loop
         if S (I) = '\' and then I < S'Last and then Is_Digit (S (I + 1)) then
            declare
               K : constant Natural := Character'Pos (S (I + 1)) - 48;
            begin
               if K = 0 then
                  Append (R, Trim (Macro_Counter'Image, Ada.Strings.Left));
               elsif K <= N_Args then
                  Append (R, Args (K));
               end if;
               I := I + 2;
            end;
         elsif Is_Ident_Start (S (I)) then
            declare
               B : constant Natural := I;
               Replaced : Boolean := False;
            begin
               while I <= S'Last and then Is_Ident (S (I)) loop
                  I := I + 1;
               end loop;
               for K in 1 .. N_Names loop
                  if S (B .. I - 1) = To_String (Names (K)) then
                     Append (R, (if K <= N_Args then Args (K)
                                 else Null_Unbounded_String));
                     Replaced := True;
                     exit;
                  end if;
               end loop;
               if not Replaced then
                  Append (R, S (B .. I - 1));
               end if;
            end;
         else
            Append (R, S (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (R);
   end Substitute;

   function Find_Macro (Name : String) return Natural is
   begin
      for I in 1 .. N_Macros loop
         if To_Upper (To_String (Macros (I).Name)) = To_Upper (Name) then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Macro;

   --  Find the matching end of a block (ENDM / ENDR) starting after Line
   function Block_End (Lines : Line_Array; From : Positive;
                       Open_Words, Close_Words : String) return Natural is
      Depth : Natural := 1;
   begin
      for I in From .. Lines'Last loop
         declare
            S : constant String :=
              To_Upper (Trim (Strip_Comment (To_String (Lines (I))),
                              Ada.Strings.Both));
            function Has_Word (Words : String) return Boolean is
              (Index (" " & S & " ", Words) > 0);
         begin
            if Has_Word (Open_Words) then
               Depth := Depth + 1;
            elsif Has_Word (Close_Words) then
               Depth := Depth - 1;
               if Depth = 0 then
                  return I;
               end if;
            end if;
         end;
      end loop;
      return 0;
   end Block_End;

   function Is_Keyword (W : String) return Boolean is
      U0 : constant String := To_Upper (W);
      U : constant String :=
        (if U0'Length > 1 and then U0 (U0'First) = '.'
         then U0 (U0'First + 1 .. U0'Last) else U0);
      Words : constant String :=
        " MACRO ENDM IF IFDEF IFNDEF ELSE ENDIF ENDC REPT ENDR ORG EQU DB" &
        " DEFB DEFM DM BYTE TEXT DZ ASCIZ DC DW DEFW WORD DS DEFS BLOCK" &
        " SPACE ALIGN INCLUDE INCBIN BINARY END ENT ENTRY OUTPUT LOADER" &
        " NOLOADER ERROR WARNING WARN ASSERT DEVICE LIST NOLIST" &
        " NOP HALT DI EI EXX DAA CPL SCF CCF RLCA RRCA RLA RRA NEG RETI" &
        " RETN RRD RLD LDI CPI INI OUTI LDD CPD IND OUTD LDIR CPIR INIR" &
        " OTIR LDDR CPDR INDR OTDR LD PUSH POP EX ADD ADC SUB SBC AND XOR" &
        " OR CP INC DEC JP JR DJNZ CALL RET RST IM IN OUT RLC RRC RL RR" &
        " SLA SRA SLL SL1 SLI SRL BIT RES SET ";
   begin
      return U'Length > 0 and then Index (Words, " " & U & " ") > 0;
   end Is_Keyword;

   procedure Statement (Line : String; Lines : Line_Array;
                        Index : in out Positive; File : Natural;
                        First_Line : Natural; Depth : Natural) is
      S : constant String := Trim (Strip_Comment (Line), Ada.Strings.Right);
      P : Natural := S'First;
      Label : Unbounded_String;
      Word_Start, Word_End : Natural;
   begin
      Is_Instruction := False;
      PC := Out_PC;
      if Trim (S, Ada.Strings.Both) = "" then
         return;
      end if;
      --  Label: in column 1 (unless it is a directive or mnemonic
      --  without a colon), or any word followed by ':'
      declare
         Q : Natural := S'First;
      begin
         while Q <= S'Last and then Is_Ident (S (Q)) loop
            Q := Q + 1;
         end loop;
         if S (S'First) /= ' ' and then not
           (Is_Keyword (S (S'First .. Q - 1))
            and then (Q > S'Last or else S (Q) /= ':'))
         then
            P := Q;
            Label := To_Unbounded_String (S (S'First .. P - 1));
            if P <= S'Last and then S (P) = ':' then
               P := P + 1;
            end if;
            goto Label_Done;
         end if;
      end;
      if True then
         declare
            Q : Natural := P;
         begin
            while Q <= S'Last and then S (Q) = ' ' loop
               Q := Q + 1;
            end loop;
            P := Q;
            while Q <= S'Last and then Is_Ident (S (Q)) loop
               Q := Q + 1;
            end loop;
            if Q <= S'Last and then S (Q) = ':' and then Q > P then
               Label := To_Unbounded_String (S (P .. Q - 1));
               P := Q + 1;
            end if;
         end;
      end if;
      <<Label_Done>>
      while P <= S'Last and then S (P) = ' ' loop
         P := P + 1;
      end loop;
      Word_Start := P;
      while P <= S'Last and then (Is_Ident (S (P)) or else S (P) = '=')
        and then not (P > Word_Start and then S (P) = '=')
      loop
         P := P + 1;
      end loop;
      Word_End := P - 1;
      declare
         Word : constant String := S (Word_Start .. Word_End);
         U0 : constant String := To_Upper (Word);
         U : constant String :=
           (if U0'Length > 1 and then U0 (U0'First) = '.'
            then U0 (U0'First + 1 .. U0'Last) else U0);
         Rest : constant String :=
           Trim (S (Word_End + 1 .. S'Last), Ada.Strings.Both);
         Ops : Op_List;
         N : Natural;
         L : constant String := To_String (Label);
      begin
         --  Conditionals are handled even when inactive
         if U = "IF" or else U = "IFDEF" or else U = "IFNDEF" then
            declare
               Cond : Boolean := False;
               Dummy : Integer;
            begin
               if Active then
                  if U = "IF" then
                     Cond := Eval (Rest) /= 0;
                  elsif U = "IFDEF" then
                     Cond := Find_Symbol (Rest, Dummy);
                  else
                     Cond := not Find_Symbol (Rest, Dummy);
                  end if;
               end if;
               N_Conds := N_Conds + 1;
               Conds (N_Conds) := (Active => Active and then Cond,
                                   Done => Cond, Parent => Active);
            end;
            return;
         elsif U = "ELSE" then
            if N_Conds = 0 then
               Fail ("ELSE without IF");
            end if;
            Conds (N_Conds).Active := Conds (N_Conds).Parent
              and then not Conds (N_Conds).Done;
            Conds (N_Conds).Done := True;
            return;
         elsif U = "ENDIF" or else U = "ENDC" then
            if N_Conds = 0 then
               Fail ("ENDIF without IF");
            end if;
            N_Conds := N_Conds - 1;
            return;
         end if;
         if not Active then
            if U = "MACRO" or else U = "REPT" then
               --  skip the whole block
               declare
                  E : constant Natural :=
                    Block_End (Lines, Index + 1,
                               (if U = "MACRO" then " MACRO " else " REPT "),
                               (if U = "MACRO" then " ENDM " else " ENDR "));
               begin
                  if E > 0 then
                     Index := E;
                  end if;
               end;
            end if;
            return;
         end if;

         --  name EQU value / name = value
         if (U = "EQU" or else U = "DEFL" or else Word = "=") and then L /= ""
         then
            Define (L, Eval (Rest), Redefinable => U /= "EQU");
            return;
         end if;
         if Word = "" and then Rest'Length > 0 and then Rest (Rest'First) = '='
           and then L /= ""
         then
            Define (L, Eval (Rest (Rest'First + 1 .. Rest'Last)),
                    Redefinable => True);
            return;
         end if;

         if U = "MACRO" then
            --  "name MACRO args" or "MACRO name args"
            declare
               M : Macro;
               E : constant Natural :=
                 Block_End (Lines, Index + 1, " MACRO ", " ENDM ");
               Arg_Text : Unbounded_String := To_Unbounded_String (Rest);
            begin
               if E = 0 then
                  Fail ("MACRO without ENDM");
               end if;
               if L /= "" then
                  M.Name := Label;
               else
                  declare
                     Q : Natural := Rest'First;
                  begin
                     while Q <= Rest'Last and then Is_Ident (Rest (Q)) loop
                        Q := Q + 1;
                     end loop;
                     M.Name := To_Unbounded_String (Rest (Rest'First .. Q - 1));
                     Arg_Text := To_Unbounded_String
                       (Trim (Rest (Q .. Rest'Last), Ada.Strings.Both));
                  end;
               end if;
               Split (To_String (Arg_Text), M.Params, M.N_Params);
               M.Body_Lines := new Line_Array'(Lines (Index + 1 .. E - 1));
               M.File := File;
               M.First_Line := First_Line + Index;
               if Find_Macro (To_String (M.Name)) = 0 then
                  if N_Macros < Macros'Last then
                     N_Macros := N_Macros + 1;
                     Macros (N_Macros) := M;
                  end if;
               end if;
               Index := E;
            end;
            return;
         end if;

         if L /= "" then
            if L (L'First) /= '.' then
               Global_Label := Label;
            end if;
            Define (L, Out_PC, Is_Label => True);
         end if;
         if Word = "" then
            return;
         end if;

         if U = "REPT" then
            declare
               E : constant Natural :=
                 Block_End (Lines, Index + 1, " REPT ", " ENDR ");
               Count : constant Integer := Eval (Rest);
               Empty : Op_List;
            begin
               if E = 0 then
                  Fail ("REPT without ENDR");
               end if;
               for K in 1 .. Count loop
                  Process_Lines (Lines (Index + 1 .. E - 1), File,
                                 First_Line, Depth + 1, Empty, 0, Empty, 0);
               end loop;
               Index := E;
            end;
            return;
         end if;

         Split (Rest, Ops, N);

         if U = "ORG" then
            Out_PC := Eval (Rest) mod 65_536;
         elsif U in "DB" | "DEFB" | "DEFM" | "DM" | "BYTE" | "TEXT" then
            Data_Bytes (Ops, N, 'B');
         elsif U = "DZ" or else U = "ASCIZ" then
            Data_Bytes (Ops, N, 'Z');
         elsif U = "DC" then
            Data_Bytes (Ops, N, 'C');
         elsif U in "DW" | "DEFW" | "WORD" then
            for I in 1 .. N loop
               Emit_Word (Eval (To_String (Ops (I))));
            end loop;
         elsif U in "DS" | "DEFS" | "BLOCK" | "SPACE" then
            declare
               Count : constant Integer := Eval (To_String (Ops (1)));
               Fill : constant Integer :=
                 (if N >= 2 then Eval (To_String (Ops (2))) else 0);
            begin
               for K in 1 .. Count loop
                  Emit (Fill);
               end loop;
            end;
         elsif U = "ALIGN" then
            declare
               A : constant Integer := Eval (To_String (Ops (1)));
               Fill : constant Integer :=
                 (if N >= 2 then Eval (To_String (Ops (2))) else 0);
            begin
               if A > 0 then
                  while Out_PC mod A /= 0 loop
                     Emit (Fill);
                  end loop;
               end if;
            end;
         elsif U = "INCLUDE" then
            declare
               F : constant Natural :=
                 Load_File (Relative_Path (Unquote (Rest)));
               Empty : Op_List;
               Save_File : constant Natural := Cur_File;
            begin
               if Depth > 16 then
                  Fail ("INCLUDE nested too deeply");
               end if;
               Process_Lines (Sources (F).Lines.all, F, 0, Depth + 1,
                              Empty, 0, Empty, 0);
               Cur_File := Save_File;
            end;
         elsif U = "INCBIN" or else U = "BINARY" then
            declare
               Path : constant String :=
                 Relative_Path (Unquote (To_String (Ops (1))));
               F : SIO.File_Type;
            begin
               SIO.Open (F, SIO.In_File, Path);
               declare
                  D : Byte_Array (0 .. Natural (SIO.Size (F)) - 1);
                  Skip : constant Integer :=
                    (if N >= 2 then Eval (To_String (Ops (2))) else 0);
                  Len : constant Integer :=
                    (if N >= 3 then Eval (To_String (Ops (3)))
                     else D'Length - Skip);
               begin
                  Byte_Array'Read (SIO.Stream (F), D);
                  SIO.Close (F);
                  for K in Skip .. Integer'Min (Skip + Len, D'Length) - 1 loop
                     Emit (Integer (D (K)));
                  end loop;
               end;
            exception
               when Asm_Error => raise;
               when others => Fail ("cannot read " & Path);
            end;
         elsif U = "END" then
            if Rest /= "" then
               Start := Eval (Rest);
            end if;
            Ended := True;
         elsif U = "ENT" or else U = "ENTRY" or else U = "START" then
            Start := Eval (Rest);
         elsif U = "OUTPUT" then
            Out_Name := To_Unbounded_String (Unquote (Rest));
         elsif U = "LOADER" then
            Loader := True;
         elsif U = "NOLOADER" then
            Loader := False;
         elsif U = "ERROR" then
            Fail (Unquote (Rest));
         elsif U = "WARNING" or else U = "WARN" then
            Add_Error (Unquote (Rest), True);
         elsif U = "ASSERT" then
            if Final and then Eval (Rest) = 0 then
               Add_Error ("assertion failed: " & Rest);
            end if;
         elsif U = "DEVICE" or else U = "LIST" or else U = "NOLIST" then
            null;
         else
            declare
               M : constant Natural := Find_Macro (Word);
            begin
               if M > 0 then
                  Macro_Counter := Macro_Counter + 1;
                  if Depth > 32 then
                     Fail ("macros nested too deeply");
                  end if;
                  Process_Lines (Macros (M).Body_Lines.all, File,
                                 Natural'Last, Depth + 1, Ops, N,
                                 Macros (M).Params, Macros (M).N_Params);
                  Cur_File := File;
               else
                  Instruction (U, Ops, N);
               end if;
            end;
         end if;
      end;
   end Statement;

   procedure Process_Lines (Lines : Line_Array; File : Natural;
                            First_Line : Natural; Depth : Natural;
                            Macro_Args : Op_List; N_Args : Natural;
                            Arg_Names : Op_List; N_Names : Natural) is
      I : Positive := Lines'First;
   begin
      while I <= Lines'Last and then not Ended loop
         Cur_File := File;
         if First_Line /= Natural'Last then
            Cur_Line := First_Line + I;
         end if;
         declare
            Text : constant String :=
              (if N_Args > 0 or else N_Names > 0
               then Substitute (To_String (Lines (I)), Macro_Args, N_Args,
                                Arg_Names, N_Names)
               else To_String (Lines (I)));
         begin
            Statement (Text, Lines, I, File, First_Line, Depth);
         exception
            when Asm_Error => null;
         end;
         I := I + 1;
      end loop;
   end Process_Lines;

   ---------------------------------------------------------------------

   procedure Run_Passes (Path : String) is
      Main : Natural;
      Empty : Op_List;
   begin
      Symbols.Clear;
      N_Errors := 0;
      Real_Errors := 0;
      N_Files := 0;
      Changed_Last := True;
      for P in 1 .. 8 loop
         Pass := P;
         Changed := False;
         Unknown := False;
         Out_PC := 0;
         PC := 0;
         Start := -1;
         Loader := True;
         Out_Name := Null_Unbounded_String;
         Ended := False;
         N_Conds := 0;
         N_Macros := 0;
         Macro_Counter := 0;
         Global_Label := Null_Unbounded_String;
         Final := P > 1 and then not Changed_Last;
         if Final then
            Mem := (others => 0);
            Used := (others => False);
            Code_At := (others => False);
            Line_File := (others => 0);
            Line_No := (others => 0);
            Lowest := -1;
            Highest := -1;
         end if;
         begin
            Cur_File := 0;
            Cur_Line := 0;
            Main := Load_File (Path);
            Process_Lines (Sources (Main).Lines.all, Main, 0, 0,
                           Empty, 0, Empty, 0);
         exception
            when Asm_Error => null;
         end;
         if N_Conds > 0 then
            Add_Error ("IF without ENDIF");
         end if;
         exit when Final;
         Changed_Last := Changed or else (Unknown and then P < 3);
      end loop;
      --  sorted symbol list
      N_Sorted := 0;
      for C in Symbols.Iterate loop
         if N_Sorted < Sorted'Last then
            N_Sorted := N_Sorted + 1;
            Sorted (N_Sorted) := To_Unbounded_String (Symbol_Maps.Key (C));
         end if;
      end loop;
      for I in 2 .. N_Sorted loop
         declare
            K : constant Unbounded_String := Sorted (I);
            J : Natural := I - 1;
         begin
            while J >= 1 and then Sorted (J) > K loop
               Sorted (J + 1) := Sorted (J);
               J := J - 1;
            end loop;
            Sorted (J + 1) := K;
         end;
      end loop;
   end Run_Passes;

   procedure Assemble (Path : String) is
   begin
      Main_Is_Text := False;
      Run_Passes (Path);
   end Assemble;

   procedure Assemble_Text (Text : String; Name : String := "source") is
   begin
      Main_Is_Text := True;
      Main_Text := To_Unbounded_String (Text);
      Run_Passes (Name);
   end Assemble_Text;

   ---------------------------------------------------------------------
   --  Queries
   ---------------------------------------------------------------------

   function Is_Source (Path : String) return Boolean is
      E : constant String := To_Lower (File_Ext.Of_Path (Path));
   begin
      return E = "asm" or else E = "z80s" or else E = "s" or else E = "a80";
   end Is_Source;

   function Base_Of (Source : String) return String is
     (if Ada.Directories.Extension (Source) = "" then Source
      else Source (Source'First .. Source'Last
                   - Ada.Directories.Extension (Source)'Length - 1));

   function Default_Output (Source : String) return String is
   begin
      if Length (Out_Name) > 0 then
         return Relative_Path (To_String (Out_Name));
      end if;
      return Base_Of (Source) & ".bin";
   end Default_Output;

   function Error_Count return Natural is (N_Errors);
   function Has_Errors return Boolean is (Real_Errors > 0);
   function Error_File (I : Positive) return String is
     (if Errors (I).File in 1 .. N_Files
      then To_String (Files (Errors (I).File)) else "");
   function Error_Line (I : Positive) return Natural is (Errors (I).Line);
   function Error_Text (I : Positive) return String is
     (To_String (Errors (I).Text));
   function Is_Warning (I : Positive) return Boolean is
     (Errors (I).Warning);

   function Has_Output return Boolean is (Lowest >= 0);
   function Low_Address return Word is (Word (Integer'Max (Lowest, 0)));
   function High_Address return Word is (Word (Integer'Max (Highest, 0)));
   function Output_Byte (A : Word) return Byte is (Mem (Natural (A)));
   function Start_Address return Word is
     (Word ((if Start >= 0 then Start else Integer'Max (Lowest, 0))
            mod 65_536));
   function Has_Loader return Boolean is (Loader);
   function Output_Name return String is (To_String (Out_Name));

   function Code_Bytes return Byte_Array is
     (if Lowest < 0 then (1 .. 0 => 0) else Mem (Lowest .. Highest));

   function File_Count return Natural is (N_Files);
   function File_Name (I : Positive) return String is
     (To_String (Files (I)));

   procedure Line_Of (A : Word; File : out Natural; Line : out Natural) is
   begin
      File := Line_File (Natural (A));
      Line := Line_No (Natural (A));
   end Line_Of;

   procedure Address_Of (File : String; Line : Positive;
                         Found : out Boolean; A : out Word;
                         Code_Only : Boolean := False) is
      F : Natural := 0;
      Full : constant String :=
        (if File = "" then "" else Ada.Directories.Full_Name (File));
   begin
      Found := False;
      A := 0;
      for I in 1 .. N_Files loop
         if To_String (Files (I)) = Full then
            F := I;
         end if;
      end loop;
      if F = 0 or else Lowest < 0 then
         return;
      end if;
      for Addr in Lowest .. Highest loop
         if Line_File (Addr) = F and then Line_No (Addr) = Line
           and then (not Code_Only or else Code_At (Addr))
         then
            Found := True;
            A := Word (Addr);
            return;
         end if;
      end loop;
   end Address_Of;

   function Is_Code (A : Word) return Boolean is (Code_At (Natural (A)));

   function Label_At (A : Word) return String is
   begin
      for I in 1 .. N_Sorted loop
         declare
            S : constant Symbol := Symbols.Element (To_String (Sorted (I)));
         begin
            if S.Is_Label and then S.Value = Integer (A) then
               return To_String (Sorted (I));
            end if;
         end;
      end loop;
      return "";
   end Label_At;

   function Symbol_Count return Natural is (N_Sorted);
   function Symbol_Name (I : Positive) return String is
     (To_String (Sorted (I)));
   function Symbol_Value (I : Positive) return Integer is
     (Symbols.Element (To_String (Sorted (I))).Value);

   function Lookup (Name : String; Value : out Integer) return Boolean is
      C : constant Symbol_Maps.Cursor := Symbols.Find (Name);
   begin
      if Symbol_Maps.Has_Element (C) then
         Value := Symbol_Maps.Element (C).Value;
         return True;
      end if;
      Value := 0;
      return False;
   end Lookup;

   ---------------------------------------------------------------------
   --  Output files
   ---------------------------------------------------------------------

   procedure Write_File (Path : String; D : Byte_Array; Ok : out Boolean) is
      F : SIO.File_Type;
   begin
      SIO.Create (F, SIO.Out_File, Path);
      Byte_Array'Write (SIO.Stream (F), D);
      SIO.Close (F);
      Ok := True;
   exception
      when others =>
         Ok := False;
   end Write_File;

   procedure Write_Binary (Path : String; Ok : out Boolean) is
   begin
      Write_File (Path, Code_Bytes, Ok);
   end Write_Binary;

   procedure Write_Labels (Path : String; Ok : out Boolean) is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      for I in 1 .. N_Sorted loop
         Ada.Text_IO.Put_Line
           (F, Symbol_Name (I) & " EQU $" &
              Disasm_Hex (Symbol_Value (I) mod 65_536));
      end loop;
      Ada.Text_IO.Close (F);
      Ok := True;
   exception
      when others =>
         Ok := False;
   end Write_Labels;

   function Tap_Block (Data : Byte_Array) return Byte_Array is
      R : Byte_Array (0 .. Data'Length + 1);
      Parity : Byte := 0;
   begin
      R (0) := Byte ((Data'Length + 1) mod 256);
      R (1) := Byte ((Data'Length + 1) / 256);
      R (2 .. Data'Length + 1) := Data;
      for B of Data loop
         Parity := Parity xor B;
      end loop;
      return R (0 .. Data'Length + 1) & Byte_Array'(1 => Parity);
   end Tap_Block;

   function Header (Kind : Byte; Name : String; Len, P1, P2 : Natural)
                    return Byte_Array is
      H : Byte_Array (0 .. 17) := (others => 32);
   begin
      H (0) := 0;
      H (1) := Kind;
      for K in 1 .. Natural'Min (10, Name'Length) loop
         H (1 + K) := Character'Pos (Name (Name'First + K - 1));
      end loop;
      H (12) := Byte (Len mod 256);
      H (13) := Byte (Len / 256);
      H (14) := Byte (P1 mod 256);
      H (15) := Byte (P1 / 256);
      H (16) := Byte (P2 mod 256);
      H (17) := Byte (P2 / 256);
      return Tap_Block (H);
   end Header;

   Tape_Name : Unbounded_String := To_Unbounded_String ("code");

   function Spectrum_Tape return Byte_Array is
      Code : constant Byte_Array := Code_Bytes;
      Low : constant Natural := Natural (Low_Address);
      Code_Part : constant Byte_Array :=
        Header (3, To_String (Tape_Name), Code'Length, Low, 32768)
        & Tap_Block (Byte_Array'(1 => 16#FF#) & Code);
   begin
      if not Loader then
         return Code_Part;
      end if;
      declare
         Clear : constant String :=
           (if Low > 24_000 then "CLEAR " & Trim (Natural'Image (Low - 1),
                                                    Ada.Strings.Left) & ": "
            else "");
         Src : constant String :=
           "10 " & Clear & "LOAD """"CODE : RANDOMIZE USR " &
           Trim (Natural (Start_Address)'Image, Ada.Strings.Left);
      begin
         Basic.Tokenize_Text (Src, Basic.Spectrum);
         declare
            Prog : constant Byte_Array := Basic.Program;
         begin
            return Header (0, "loader", Prog'Length, 10, Prog'Length)
              & Tap_Block (Byte_Array'(1 => 16#FF#) & Prog)
              & Code_Part;
         end;
      end;
   end Spectrum_Tape;

   function ZX81_Program return Byte_Array is
      Code : constant Byte_Array := Code_Bytes;
      Line1_Len : constant Natural := Code'Length + 2;   --  REM ... NEWLINE
      Line1 : constant Byte_Array :=
        (0, 1, Byte (Line1_Len mod 256), Byte (Line1_Len / 256), 16#EA#)
        & Code & Byte_Array'(1 => 16#76#);
   begin
      Basic.Tokenize_Text ("2 RAND USR " & Trim (Natural (Start_Address)'Image,
                                                Ada.Strings.Left),
                           Basic.ZX81);
      return Line1 & Basic.Program;
   end ZX81_Program;

   function ZX80_Program return Byte_Array is
      Code : constant Byte_Array := Code_Bytes;
      L2, E : Unbounded_String;
   begin
      Basic_ZX80.Tokenize_Line
        ("PRINT USR(" & Trim (Natural (Start_Address)'Image,
                                  Ada.Strings.Left) & ")", 2, L2, E);
      declare
         Line2 : Byte_Array (1 .. Length (L2));
      begin
         for K in Line2'Range loop
            Line2 (K) := Character'Pos (Element (L2, K));
         end loop;
         return Byte_Array'(0, 1, 16#FE#) & Code & Byte_Array'(1 => 16#76#)
           & Line2;
      end;
   end ZX80_Program;

   procedure Build (Source : String; Output : out Ada_String; Ok : out Boolean)
   is
      Base : constant String := Base_Of (Source);
   begin
      Assemble (Source);
      for I in 1 .. N_Errors loop
         if Report /= null then
            Report (Error_File (I) & ":" &
                    Trim (Error_Line (I)'Image, Ada.Strings.Left) & ": " &
                    (if Is_Warning (I) then "warning: " else "error: ") &
                    Error_Text (I));
         end if;
      end loop;
      Ok := not Has_Errors and then Has_Output;
      if not Ok then
         if not Has_Errors and then Report /= null then
            Report (Source & ": error: no code");
         end if;
         return;
      end if;
      declare
         Bin : constant String := Default_Output (Source);
         Out_Ok, Lbl_Ok : Boolean;
      begin
         Write_Binary (Bin, Out_Ok);
         Write_Labels (Base & ".lbl", Lbl_Ok);
         Tape_Name := To_Unbounded_String (Ada.Directories.Base_Name (Source));
         if Target = Spectrum then
            Write_File (Base & ".tap", Spectrum_Tape, Out_Ok);
            Output := To_Unbounded_String (Base & ".tap");
         elsif Target = ZX80 and then Low_Address = 16#402B# then
            Write_File (Base & ".o",
                        Basic_ZX80.Make_O (ZX80_Program,
                                           Basic_ZX80.Default_Sysvars),
                        Out_Ok);
            Output := To_Unbounded_String (Base & ".o");
         elsif Target = ZX81 and then Low_Address = 16#4082# then
            Write_File (Base & ".p", Basic.Make_P (ZX81_Program, 2), Out_Ok);
            Output := To_Unbounded_String (Base & ".p");
         else
            Output := To_Unbounded_String (Bin);
         end if;
         Ok := Out_Ok;
         if Report /= null then
            Report ("assembled $" & Disasm_Hex (Natural (Low_Address)) & "-$"
                    & Disasm_Hex (Natural (High_Address)) & " ("
                    & Trim (Natural'Image (Code_Bytes'Length), Ada.Strings.Left)
                    & " bytes), wrote " & To_String (Output));
         end if;
         pragma Unreferenced (Lbl_Ok);
      end;
   end Build;

end Asm;
