-- ***************************************************************************
--                             AdaZX - Cond_Expr
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
with Ada.Exceptions;
with Interfaces; use Interfaces;

package body Cond_Expr is

   function U (V : Integer) return Unsigned_32 is
     (Unsigned_32 (V mod 2 ** 30));
   function And_Bits (A, B : Integer) return Integer is
     (Integer (U (A) and U (B)));
   function Or_Bits (A, B : Integer) return Integer is
     (Integer (U (A) or U (B)));
   function Xor_Bits (A, B : Integer) return Integer is
     (Integer (U (A) xor U (B)));

   function Evaluate (Text : String; Names : Register_Func;
                      Labels : Register_Func; Peek : Peek_Func)
                      return Integer is
      P : Natural := Text'First;

      procedure Fail (Msg : String) is
      begin
         Ada.Exceptions.Raise_Exception (Syntax_Error'Identity, Msg);
      end Fail;

      procedure Skip is
      begin
         while P <= Text'Last and then Text (P) in ' ' | ASCII.HT loop
            P := P + 1;
         end loop;
      end Skip;

      function At_Op (S : String) return Boolean is
      begin
         Skip;
         return P + S'Length - 1 <= Text'Last
           and then To_Lower (Text (P .. P + S'Length - 1)) = S;
      end At_Op;

      --  A word operator ("and", "or", "not") followed by a non-name char
      function At_Word (S : String) return Boolean is
      begin
         return At_Op (S)
           and then (P + S'Length > Text'Last
                     or else not (Is_Alphanumeric (Text (P + S'Length))
                                  or else Text (P + S'Length) = '_'));
      end At_Word;

      function Expr return Integer;

      function Number return Integer is
         Start : constant Natural := P;
         Base : Integer := 10;
         V : Integer := 0;
         Digits_Start : Natural;
         Last : Natural;
      begin
         if Text (P) = '$' or else Text (P) = '#' then
            Base := 16;
            P := P + 1;
         elsif Text (P) = '%' then
            Base := 2;
            P := P + 1;
         elsif P < Text'Last and then Text (P) = '0'
           and then (Text (P + 1) = 'x' or else Text (P + 1) = 'X')
         then
            Base := 16;
            P := P + 2;
         end if;
         Digits_Start := P;
         while P <= Text'Last and then Is_Hexadecimal_Digit (Text (P)) loop
            P := P + 1;
         end loop;
         Last := P - 1;
         if Base = 10 and then P <= Text'Last
           and then (Text (P) = 'h' or else Text (P) = 'H')
         then
            Base := 16;          --  0ffh
            P := P + 1;
         elsif Base = 10 and then Last >= Digits_Start
           and then To_Lower (Text (Last)) in 'b'
           and then (for all C of Text (Digits_Start .. Last - 1) =>
                       C in '0' | '1')
           and then Last > Digits_Start
         then
            Base := 2;           --  1010b
            Last := Last - 1;
         end if;
         if Last < Digits_Start then
            Fail ("number expected at """ & Text (Start .. Text'Last) & """");
         end if;
         for C of Text (Digits_Start .. Last) loop
            declare
               D : constant Integer :=
                 (if Is_Digit (C) then Character'Pos (C) - 48
                  else Character'Pos (To_Lower (C)) - 87);
            begin
               if D >= Base then
                  Fail ("bad digit in """ & Text (Start .. P - 1) & """");
               end if;
               V := (V * Base + D) mod 2 ** 30;
            end;
         end loop;
         return V;
      end Number;

      function Primary return Integer is
      begin
         Skip;
         if P > Text'Last then
            Fail ("value expected at the end");
         end if;
         declare
            C : constant Character := Text (P);
         begin
            if C = '(' then
               P := P + 1;
               return V : constant Integer := Expr do
                  if not At_Op (")") then
                     Fail ("')' expected");
                  end if;
                  P := P + 1;
               end return;
            elsif C = '[' or else C = '{' then
               P := P + 1;
               declare
                  A : constant Integer := Expr mod 65536;
                  Close : constant String := (if C = '[' then "]" else "}");
               begin
                  if not At_Op (Close) then
                     Fail ("'" & Close & "' expected");
                  end if;
                  P := P + 1;
                  if Peek = null then
                     return 0;
                  elsif C = '[' then
                     return Peek (A);
                  else
                     return Peek (A) + 256 * Peek ((A + 1) mod 65536);
                  end if;
               end;
            elsif C = ''' and then P + 2 <= Text'Last
              and then Text (P + 2) = '''
            then
               P := P + 3;
               return Character'Pos (Text (P - 2));
            elsif Is_Digit (C) or else C = '$' or else C = '#'
              or else C = '%'
            then
               return Number;
            elsif Is_Letter (C) or else C = '_' or else C = '.' then
               declare
                  Start : constant Natural := P;
                  V : Integer;
               begin
                  P := P + 1;
                  while P <= Text'Last
                    and then (Is_Alphanumeric (Text (P))
                              or else Text (P) in '_' | '.')
                  loop
                     P := P + 1;
                  end loop;
                  if P <= Text'Last and then Text (P) = ''' then
                     P := P + 1;          --  af' bc' de' hl'
                  end if;
                  declare
                     Name : constant String := Text (Start .. P - 1);
                  begin
                     if Names /= null
                       and then Names (To_Lower (Name), V)
                     then
                        return V;
                     elsif Labels /= null and then Labels (Name, V) then
                        return V;
                     end if;
                     Fail ("unknown name """ & Name & """");
                  end;
               end;
            end if;
            Fail ("unexpected """ & Text (P .. Text'Last) & """");
         end;
         return 0;
      end Primary;

      function Unary return Integer is
      begin
         if At_Op ("-") then
            P := P + 1;
            return -Unary;
         elsif At_Op ("~") then
            P := P + 1;
            return (-Unary - 1) mod 65536;
         elsif At_Op ("!") and then not At_Op ("!=") then
            P := P + 1;
            return (if Unary = 0 then 1 else 0);
         elsif At_Word ("not") then
            P := P + 3;
            return (if Unary = 0 then 1 else 0);
         end if;
         return Primary;
      end Unary;

      function Term return Integer is
         V : Integer := Unary;
      begin
         loop
            if At_Op ("*") then
               P := P + 1;
               V := (V * Unary) mod 2 ** 30;
            elsif At_Op ("/") then
               P := P + 1;
               declare
                  D : constant Integer := Unary;
               begin
                  V := (if D = 0 then 0 else V / D);
               end;
            elsif At_Op ("<<") then
               P := P + 2;
               V := (V * 2 ** (Unary mod 16)) mod 2 ** 30;
            elsif At_Op (">>") then
               P := P + 2;
               V := V / 2 ** (Unary mod 16);
            elsif At_Op ("&") and then not At_Op ("&&") then
               P := P + 1;
               V := And_Bits (V, Unary);
            else
               return V;
            end if;
         end loop;
      end Term;

      function Sum return Integer is
         V : Integer := Term;
      begin
         loop
            if At_Op ("+") then
               P := P + 1;
               V := V + Term;
            elsif At_Op ("-") then
               P := P + 1;
               V := V - Term;
            elsif At_Op ("|") and then not At_Op ("||") then
               P := P + 1;
               V := Or_Bits (V, Term);
            elsif At_Op ("^") then
               P := P + 1;
               V := Xor_Bits (V, Term);
            else
               return V;
            end if;
         end loop;
      end Sum;

      function Compare return Integer is
         L : constant Integer := Sum;
         function B (X : Boolean) return Integer is (if X then 1 else 0);
      begin
         if At_Op ("==") then
            P := P + 2;
            return B (L = Sum);
         elsif At_Op ("!=") or else At_Op ("<>") then
            P := P + 2;
            return B (L /= Sum);
         elsif At_Op ("<=") then
            P := P + 2;
            return B (L <= Sum);
         elsif At_Op (">=") then
            P := P + 2;
            return B (L >= Sum);
         elsif At_Op ("=") then
            P := P + 1;
            return B (L = Sum);
         elsif At_Op ("<") and then not At_Op ("<<") then
            P := P + 1;
            return B (L < Sum);
         elsif At_Op (">") and then not At_Op (">>") then
            P := P + 1;
            return B (L > Sum);
         end if;
         return L;
      end Compare;

      function Conj return Integer is
         V : Integer := Compare;
      begin
         loop
            if At_Op ("&&") then
               P := P + 2;
            elsif At_Word ("and") then
               P := P + 3;
            else
               return V;
            end if;
            declare
               R : constant Integer := Compare;
            begin
               V := (if V /= 0 and then R /= 0 then 1 else 0);
            end;
         end loop;
      end Conj;

      function Expr return Integer is
         V : Integer := Conj;
      begin
         loop
            if At_Op ("||") then
               P := P + 2;
            elsif At_Word ("or") then
               P := P + 2;
            else
               return V;
            end if;
            declare
               R : constant Integer := Conj;
            begin
               V := (if V /= 0 or else R /= 0 then 1 else 0);
            end;
         end loop;
      end Expr;

      V : Integer;
   begin
      V := Expr;
      Skip;
      if P <= Text'Last then
         Fail ("unexpected """ & Text (P .. Text'Last) & """");
      end if;
      return V;
   end Evaluate;

   function Dummy_Name (Name : String; Value : out Integer) return Boolean is
   begin
      Value := 1;
      return Name in "a" | "f" | "b" | "c" | "d" | "e" | "h" | "l" | "i"
        | "r" | "af" | "bc" | "de" | "hl" | "ix" | "iy" | "sp" | "pc"
        | "af'" | "bc'" | "de'" | "hl'" | "ixh" | "ixl" | "iyh" | "iyl"
        | "sf" | "zf" | "hf" | "pf" | "nf" | "cf";
   end Dummy_Name;

   function Error_Of (Text : String; Labels : Register_Func) return String is
      V : Integer;
      pragma Unreferenced (V);
   begin
      V := Evaluate (Text, Dummy_Name'Access, Labels, null);
      return "";
   exception
      when E : Syntax_Error =>
         return Ada.Exceptions.Exception_Message (E);
   end Error_Of;

end Cond_Expr;
