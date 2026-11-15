-- ***************************************************************************
--                               AdaZX - Basic
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
with Ada.Streams.Stream_IO;
with Ada.Directories;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Interfaces; use Interfaces;
with Basic_ZX80;

package body Basic is

   use Ada.Strings.Unbounded;
   package SIO renames Ada.Streams.Stream_IO;

   ---------------------------------------------------------------------
   --  Keyword tables
   ---------------------------------------------------------------------

   type Name_Access is access constant String;
   function "+" (S : String) return Name_Access is (new String'(S));
   type Name_List is array (Positive range <>) of Name_Access;

   Spec_First : constant := 16#A3#;
   Spec_Names : constant array (Byte range 16#A3# .. 16#FF#) of Name_Access :=
     (+"SPECTRUM", +"PLAY", +"RND", +"INKEY$", +"PI", +"FN", +"POINT",
      +"SCREEN$", +"ATTR", +"AT", +"TAB", +"VAL$", +"CODE", +"VAL", +"LEN",
      +"SIN", +"COS", +"TAN", +"ASN", +"ACS", +"ATN", +"LN", +"EXP", +"INT",
      +"SQR", +"SGN", +"ABS", +"PEEK", +"IN", +"USR", +"STR$", +"CHR$",
      +"NOT", +"BIN", +"OR", +"AND", +"<=", +">=", +"<>", +"LINE", +"THEN",
      +"TO", +"STEP", +"DEF FN", +"CAT", +"FORMAT", +"MOVE", +"ERASE",
      +"OPEN #", +"CLOSE #", +"MERGE", +"VERIFY", +"BEEP", +"CIRCLE",
      +"INK", +"PAPER", +"FLASH", +"BRIGHT", +"INVERSE", +"OVER", +"OUT",
      +"LPRINT", +"LLIST", +"STOP", +"READ", +"DATA", +"RESTORE", +"NEW",
      +"BORDER", +"CONTINUE", +"DIM", +"REM", +"FOR", +"GO TO", +"GO SUB",
      +"INPUT", +"LOAD", +"LIST", +"LET", +"PAUSE", +"NEXT", +"POKE",
      +"PRINT", +"PLOT", +"RUN", +"SAVE", +"RANDOMIZE", +"IF", +"CLS",
      +"DRAW", +"CLEAR", +"RETURN", +"COPY");

   ZX81_Names : constant array (Byte range 16#C0# .. 16#FF#) of Name_Access :=
     (+"""""", +"AT", +"TAB", +"?", +"CODE", +"VAL", +"LEN", +"SIN", +"COS",
      +"TAN", +"ASN", +"ACS", +"ATN", +"LN", +"EXP", +"INT", +"SQR", +"SGN",
      +"ABS", +"PEEK", +"USR", +"STR$", +"CHR$", +"NOT", +"**", +"OR",
      +"AND", +"<=", +">=", +"<>", +"THEN", +"TO", +"STEP", +"LPRINT",
      +"LLIST", +"STOP", +"SLOW", +"FAST", +"NEW", +"SCROLL", +"CONT",
      +"DIM", +"REM", +"FOR", +"GOTO", +"GOSUB", +"INPUT", +"LOAD", +"LIST",
      +"LET", +"PAUSE", +"NEXT", +"POKE", +"PRINT", +"PLOT", +"RUN", +"SAVE",
      +"RAND", +"IF", +"CLS", +"UNPLOT", +"CLEAR", +"RETURN", +"COPY");

   function Token_Text (Code : Byte; D : Dialect) return String is
   begin
      case D is
         when ZX80 =>
            return Basic_ZX80.Token_Text (Code);
         when Spectrum =>
            if Code >= Spec_First then
               return Spec_Names (Code).all;
            end if;
         when ZX81 =>
            if Code >= 16#C0# and then Code /= 16#C3# then
               return ZX81_Names (Code).all;
            elsif Code = 16#40# then
               return "RND";
            elsif Code = 16#41# then
               return "INKEY$";
            elsif Code = 16#42# then
               return "PI";
            end if;
      end case;
      return "";
   end Token_Text;

   type Key_Entry is record
      Name : Name_Access;
      Kind : Key_Kind;
      Key  : Character;
   end record;

   Spec_Keys : constant array (Positive range <>) of Key_Entry :=
     ((+"NEW", K_Mode, 'A'), (+"BORDER", K_Mode, 'B'),
      (+"CONTINUE", K_Mode, 'C'), (+"DIM", K_Mode, 'D'),
      (+"REM", K_Mode, 'E'), (+"FOR", K_Mode, 'F'),
      (+"GO TO", K_Mode, 'G'), (+"GO SUB", K_Mode, 'H'),
      (+"INPUT", K_Mode, 'I'), (+"LOAD", K_Mode, 'J'),
      (+"LIST", K_Mode, 'K'), (+"LET", K_Mode, 'L'),
      (+"PAUSE", K_Mode, 'M'), (+"NEXT", K_Mode, 'N'),
      (+"POKE", K_Mode, 'O'), (+"PRINT", K_Mode, 'P'),
      (+"PLOT", K_Mode, 'Q'), (+"RUN", K_Mode, 'R'),
      (+"SAVE", K_Mode, 'S'), (+"RANDOMIZE", K_Mode, 'T'),
      (+"IF", K_Mode, 'U'), (+"CLS", K_Mode, 'V'),
      (+"DRAW", K_Mode, 'W'), (+"CLEAR", K_Mode, 'X'),
      (+"RETURN", K_Mode, 'Y'), (+"COPY", K_Mode, 'Z'),
      (+"STOP", Symbol_Shift, 'A'), (+"NOT", Symbol_Shift, 'S'),
      (+"STEP", Symbol_Shift, 'D'), (+"TO", Symbol_Shift, 'F'),
      (+"THEN", Symbol_Shift, 'G'), (+"<=", Symbol_Shift, 'Q'),
      (+"<>", Symbol_Shift, 'W'), (+">=", Symbol_Shift, 'E'),
      (+"AT", Symbol_Shift, 'I'), (+"OR", Symbol_Shift, 'U'),
      (+"AND", Symbol_Shift, 'Y'),
      (+"READ", Extended, 'A'), (+"BIN", Extended, 'B'),
      (+"LPRINT", Extended, 'C'), (+"DATA", Extended, 'D'),
      (+"TAN", Extended, 'E'), (+"SGN", Extended, 'F'),
      (+"ABS", Extended, 'G'), (+"SQR", Extended, 'H'),
      (+"CODE", Extended, 'I'), (+"VAL", Extended, 'J'),
      (+"LEN", Extended, 'K'), (+"USR", Extended, 'L'),
      (+"PI", Extended, 'M'), (+"INKEY$", Extended, 'N'),
      (+"PEEK", Extended, 'O'), (+"TAB", Extended, 'P'),
      (+"SIN", Extended, 'Q'), (+"INT", Extended, 'R'),
      (+"RESTORE", Extended, 'S'), (+"RND", Extended, 'T'),
      (+"CHR$", Extended, 'U'), (+"LLIST", Extended, 'V'),
      (+"COS", Extended, 'W'), (+"EXP", Extended, 'X'),
      (+"STR$", Extended, 'Y'), (+"LN", Extended, 'Z'),
      (+"BRIGHT", Extended_Symbol, 'B'), (+"PAPER", Extended_Symbol, 'C'),
      (+"ATN", Extended_Symbol, 'E'), (+"CIRCLE", Extended_Symbol, 'H'),
      (+"IN", Extended_Symbol, 'I'), (+"VAL$", Extended_Symbol, 'J'),
      (+"SCREEN$", Extended_Symbol, 'K'), (+"ATTR", Extended_Symbol, 'L'),
      (+"INVERSE", Extended_Symbol, 'M'), (+"OVER", Extended_Symbol, 'N'),
      (+"OUT", Extended_Symbol, 'O'), (+"ASN", Extended_Symbol, 'Q'),
      (+"VERIFY", Extended_Symbol, 'R'), (+"MERGE", Extended_Symbol, 'T'),
      (+"FLASH", Extended_Symbol, 'V'), (+"ACS", Extended_Symbol, 'W'),
      (+"INK", Extended_Symbol, 'X'), (+"BEEP", Extended_Symbol, 'Z'),
      (+"DEF FN", Extended_Symbol, '1'), (+"FN", Extended_Symbol, '2'),
      (+"LINE", Extended_Symbol, '3'), (+"OPEN #", Extended_Symbol, '4'),
      (+"CLOSE #", Extended_Symbol, '5'), (+"MOVE", Extended_Symbol, '6'),
      (+"ERASE", Extended_Symbol, '7'), (+"POINT", Extended_Symbol, '8'),
      (+"CAT", Extended_Symbol, '9'), (+"FORMAT", Extended_Symbol, '0'));

   ZX81_Keys : constant array (Positive range <>) of Key_Entry :=
     ((+"NEW", K_Mode, 'A'), (+"SCROLL", K_Mode, 'B'),
      (+"CONT", K_Mode, 'C'), (+"DIM", K_Mode, 'D'),
      (+"REM", K_Mode, 'E'), (+"FOR", K_Mode, 'F'),
      (+"GOTO", K_Mode, 'G'), (+"GOSUB", K_Mode, 'H'),
      (+"INPUT", K_Mode, 'I'), (+"LOAD", K_Mode, 'J'),
      (+"LIST", K_Mode, 'K'), (+"LET", K_Mode, 'L'),
      (+"PAUSE", K_Mode, 'M'), (+"NEXT", K_Mode, 'N'),
      (+"POKE", K_Mode, 'O'), (+"PRINT", K_Mode, 'P'),
      (+"PLOT", K_Mode, 'Q'), (+"RUN", K_Mode, 'R'),
      (+"SAVE", K_Mode, 'S'), (+"RAND", K_Mode, 'T'),
      (+"IF", K_Mode, 'U'), (+"CLS", K_Mode, 'V'),
      (+"UNPLOT", K_Mode, 'W'), (+"CLEAR", K_Mode, 'X'),
      (+"RETURN", K_Mode, 'Y'), (+"COPY", K_Mode, 'Z'),
      (+"STOP", Symbol_Shift, 'A'), (+"LPRINT", Symbol_Shift, 'S'),
      (+"SLOW", Symbol_Shift, 'D'), (+"FAST", Symbol_Shift, 'F'),
      (+"LLIST", Symbol_Shift, 'G'), (+"""""", Symbol_Shift, 'Q'),
      (+"OR", Symbol_Shift, 'W'), (+"STEP", Symbol_Shift, 'E'),
      (+"<=", Symbol_Shift, 'R'), (+"<>", Symbol_Shift, 'T'),
      (+">=", Symbol_Shift, 'Y'), (+"**", Symbol_Shift, 'H'),
      (+"AND", Symbol_Shift, '2'), (+"THEN", Symbol_Shift, '3'),
      (+"TO", Symbol_Shift, '4'),
      (+"SIN", Extended, 'Q'), (+"COS", Extended, 'W'),
      (+"TAN", Extended, 'E'), (+"INT", Extended, 'R'),
      (+"RND", Extended, 'T'), (+"STR$", Extended, 'Y'),
      (+"CHR$", Extended, 'U'), (+"CODE", Extended, 'I'),
      (+"PEEK", Extended, 'O'), (+"TAB", Extended, 'P'),
      (+"ASN", Extended, 'A'), (+"ACS", Extended, 'S'),
      (+"ATN", Extended, 'D'), (+"SGN", Extended, 'F'),
      (+"ABS", Extended, 'G'), (+"SQR", Extended, 'H'),
      (+"VAL", Extended, 'J'), (+"LEN", Extended, 'K'),
      (+"USR", Extended, 'L'), (+"LN", Extended, 'Z'),
      (+"EXP", Extended, 'X'), (+"AT", Extended, 'C'),
      (+"INKEY$", Extended, 'B'), (+"NOT", Extended, 'N'),
      (+"PI", Extended, 'M'));

   procedure Keyword_Key (Code : Byte; D : Dialect; Kind : out Key_Kind;
                          Key : out Character) is
      Name : constant String := Token_Text (Code, D);
   begin
      Kind := Not_Keyword;
      Key := ' ';
      if D = ZX80 then
         declare
            K : Natural;
         begin
            Basic_ZX80.Key_Of (Code, K, Key);
            Kind := (case K is when 1 => K_Mode, when 2 => Symbol_Shift,
                        when others => Not_Keyword);
         end;
         return;
      end if;
      if Name = "" then
         return;
      end if;
      if D = Spectrum then
         for E of Spec_Keys loop
            if E.Name.all = Name then
               Kind := E.Kind;
               Key := E.Key;
               return;
            end if;
         end loop;
      else
         for E of ZX81_Keys loop
            if E.Name.all = Name then
               Kind := E.Kind;
               Key := E.Key;
               return;
            end if;
         end loop;
      end if;
   end Keyword_Key;

   ---------------------------------------------------------------------
   --  Character sets
   ---------------------------------------------------------------------

   ZX81_Chars : constant String :=
     " ??????????""`$:?()><=+-*/;,.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

   function To_ZX81 (C : Character) return Byte is
      U : constant Character := To_Upper (C);
   begin
      for K in 12 .. ZX81_Chars'Last loop
         if ZX81_Chars (K) = U then
            return Byte (K - 1);
         end if;
      end loop;
      if U = '"' then
         return 11;
      elsif U = ' ' then
         return 0;
      end if;
      return 15;      --  ?
   end To_ZX81;

   function From_ZX81 (B : Byte) return Character is
     (ZX81_Chars (Natural (B and 16#3F#) + 1));

   --  ZX81 block graphics codes 1 .. 10 and their inverses 128 .. 138,
   --  written as two quadrant characters (top, bottom): ' . : and space
   --  for the left / right halves as in zmakebas
   function Block_Code_Spectrum (Pair : String) return Integer is
      function Q (C : Character) return Integer is
        (case C is when ' ' => 0, when ''' => 1, when '.' => 2,
            when ':' => 3, when others => -1);
      L : constant Integer := Q (Pair (Pair'First));
      R : constant Integer := Q (Pair (Pair'First + 1));
   begin
      if L < 0 or else R < 0 then
         return -1;
      end if;
      --  bit 0 top right, 1 top left, 2 bottom right, 3 bottom left
      return 16#80# + (if L mod 2 = 1 then 2 else 0)
        + (if L >= 2 then 8 else 0)
        + (if R mod 2 = 1 then 1 else 0) + (if R >= 2 then 4 else 0);
   end Block_Code_Spectrum;

   --  Spectrum quadrant bits (0 TR, 1 TL, 2 BR, 3 BL) -> ZX81 code
   ZX81_Block : constant array (0 .. 15) of Byte :=
     (0, 2, 1, 3, 135, 133, 134, 132, 4, 6, 5, 7, 131, 129, 130, 128);

   function Block_Code_ZX81 (Pair : String) return Integer is
      S : constant Integer := Block_Code_Spectrum (Pair);
   begin
      if S < 0 then
         return -1;
      end if;
      return Integer (ZX81_Block (S - 16#80#));
   end Block_Code_ZX81;

   ---------------------------------------------------------------------
   --  Numbers
   ---------------------------------------------------------------------

   function Number_Bytes (Value : Long_Float; D : Dialect) return Byte_Array is
      R : Byte_Array (0 .. 4) := (others => 0);
   begin
      if D = Spectrum and then Value = Long_Float'Truncation (Value)
        and then abs Value <= 65535.0
      then
         declare
            I : constant Integer := Integer (Value);
            U : constant Natural := (if I < 0 then 65536 + I else I);
         begin
            R (1) := (if I < 0 then 16#FF# else 0);
            R (2) := Byte (U mod 256);
            R (3) := Byte (U / 256);
            return R;
         end;
      end if;
      if Value = 0.0 then
         return R;
      end if;
      declare
         M : constant Long_Float := abs Value;
         E : Integer := Long_Float'Exponent (M);
         Frac : constant Long_Float := Long_Float'Fraction (M);
         Mant : Long_Long_Integer :=
           Long_Long_Integer (Long_Float'Rounding (Frac * 2.0 ** 32));
      begin
         if Mant >= 2 ** 32 then
            Mant := Mant / 2;
            E := E + 1;
         end if;
         if E + 128 not in 1 .. 255 then
            return R;    --  out of range (an error in the ROM too)
         end if;
         R (0) := Byte (E + 128);
         R (1) := Byte ((Mant / 2 ** 24) mod 128)
           or (if Value < 0.0 then 16#80# else 0);
         R (2) := Byte ((Mant / 2 ** 16) mod 256);
         R (3) := Byte ((Mant / 2 ** 8) mod 256);
         R (4) := Byte (Mant mod 256);
      end;
      return R;
   end Number_Bytes;

   ---------------------------------------------------------------------
   --  Tokenizer
   ---------------------------------------------------------------------

   Out_Buf : Byte_Array (0 .. 65_535);
   Out_Len : Natural := 0;

   type Err_Entry is record
      Line : Natural;
      Text : Unbounded_String;
   end record;
   Errors : array (1 .. 100) of Err_Entry;
   N_Errors : Natural := 0;

   Max_Lines : constant := 10_000;
   Line_Map : array (1 .. Max_Lines) of Integer := (others => -1);
   N_Map : Natural := 0;
   Autorun : Integer := -1;

   procedure Error (Line : Natural; Text : String) is
   begin
      if N_Errors < Errors'Last then
         N_Errors := N_Errors + 1;
         Errors (N_Errors) := (Line, To_Unbounded_String (Text));
      end if;
   end Error;

   function Error_Count return Natural is (N_Errors);
   function Error_Line (I : Positive) return Natural is (Errors (I).Line);
   function Error_Text (I : Positive) return String is
     (To_String (Errors (I).Text));
   function Program return Byte_Array is (Out_Buf (0 .. Out_Len - 1));
   function Auto_Run_Line return Integer is (Autorun);

   function Basic_Line_Of (Source_Line : Positive) return Integer is
     (if Source_Line <= N_Map then Line_Map (Source_Line) else -1);

   function Source_Line_Of (Basic_Line : Natural) return Natural is
   begin
      for I in 1 .. N_Map loop
         if Line_Map (I) = Basic_Line then
            return I;
         end if;
      end loop;
      return 0;
   end Source_Line_Of;

   function Is_Alnum (C : Character) return Boolean is
     (Is_Letter (C) or else Is_Digit (C));

   --  Match keyword Name at Text (P ..): spaces inside Name are optional
   --  in Text; returns the position after the match or 0
   function Match (Text : String; P : Positive; Name : String) return Natural
   is
      I : Natural := P;
   begin
      for K in Name'Range loop
         if Name (K) = ' ' then
            while I <= Text'Last and then Text (I) = ' ' loop
               I := I + 1;
            end loop;
         else
            if I > Text'Last or else To_Upper (Text (I)) /= Name (K) then
               return 0;
            end if;
            I := I + 1;
         end if;
      end loop;
      --  a word keyword must end the word
      if Is_Letter (Name (Name'Last)) and then I <= Text'Last
        and then (Is_Alnum (Text (I)) or else Text (I) = '$')
      then
         return 0;
      end if;
      return I;
   end Match;

   Trail : Natural := 0;     --  space characters at the end of Out_Buf

   procedure Emit (B : Byte) is
   begin
      Trail := 0;
      if Out_Len <= Out_Buf'Last then
         Out_Buf (Out_Len) := B;
         Out_Len := Out_Len + 1;
      end if;
   end Emit;

   procedure Tokenize_Line (Text : String; Src_Line : Natural;
                            D : Dialect; Number : Natural) is
      Start : constant Natural := Out_Len;
      P : Natural := Text'First;
      In_Rem : Boolean := False;
      Rem_K : Boolean := False;      --  a ':' in a REM: K mode
      Inverse : Boolean := False;
      Def_Fn : Natural := 0;    --  1: after DEF FN, 2: in its parameters

      procedure Emit_Char (C : Character) is
         N : constant Natural := Trail;
      begin
         if D = Spectrum then
            Emit (Character'Pos (C));
         else
            Emit (To_ZX81 (C) or (if Inverse then 16#80# else 0));
            Inverse := False;
         end if;
         if C = ' ' then
            Trail := N + 1;
         end if;
      end Emit_Char;

      --  One literal character with escapes, at P
      procedure Literal is
         C : constant Character := Text (P);
      begin
         if C = '\' and then P < Text'Last then
            declare
               N : constant Character := Text (P + 1);
            begin
               if N = '{' then
                  declare
                     Close : constant Natural :=
                       Ada.Strings.Fixed.Index (Text (P .. Text'Last), "}");
                  begin
                     if Close > 0 then
                        Emit (Byte (Natural'Value (Text (P + 2 .. Close - 1))
                              mod 256));
                        P := Close + 1;
                        return;
                     end if;
                  end;
               elsif N = '\' then
                  Emit_Char ('\');
                  P := P + 2;
                  return;
               elsif N = '*' and then D = Spectrum then
                  Emit (16#7F#);
                  P := P + 2;
                  return;
               elsif N = '`' then
                  Emit ((if D = Spectrum then 16#60# else 12));
                  P := P + 2;
                  return;
               elsif N = '@' then
                  Emit_Char ('@');
                  P := P + 2;
                  return;
               elsif N in 'a' .. 'u' and then D = Spectrum then
                  Emit (16#90# + Character'Pos (N) - Character'Pos ('a'));
                  P := P + 2;
                  return;
               elsif P + 2 <= Text'Last then
                  declare
                     G : constant Integer :=
                       (if D = Spectrum
                        then Block_Code_Spectrum (Text (P + 1 .. P + 2))
                        else Block_Code_ZX81 (Text (P + 1 .. P + 2)));
                  begin
                     if G >= 0 then
                        Emit (Byte (G));
                        P := P + 3;
                        return;
                     end if;
                  end;
               end if;
            end;
         end if;
         if D = ZX81 and then C = '%' and then P < Text'Last then
            Inverse := True;
            P := P + 1;
            return;
         end if;
         if D = Spectrum and then Character'Pos (C) > 127 then
            Emit (Character'Pos ('?'));
         else
            Emit_Char (C);
         end if;
         P := P + 1;
      end Literal;

      procedure Number_Literal is
         S : constant Natural := P;
         Value : Long_Float;
      begin
         while P <= Text'Last and then Is_Digit (Text (P)) loop
            P := P + 1;
         end loop;
         if P <= Text'Last and then Text (P) = '.' then
            P := P + 1;
            while P <= Text'Last and then Is_Digit (Text (P)) loop
               P := P + 1;
            end loop;
         end if;
         if P < Text'Last and then To_Upper (Text (P)) = 'E'
           and then (Is_Digit (Text (P + 1))
                     or else (P + 1 < Text'Last
                              and then Text (P + 1) in '+' | '-'
                              and then Is_Digit (Text (P + 2))))
         then
            P := P + 2;
            while P <= Text'Last and then Is_Digit (Text (P)) loop
               P := P + 1;
            end loop;
         end if;
         declare
            Lit : constant String := Text (S .. P - 1);
            Lit1 : constant String (1 .. Lit'Length) := Lit;
            Fixed : constant String :=
              (if Lit1 (1) = '.' then "0" & Lit1 else Lit1);
         begin
            for C of Lit loop
               Emit_Char (C);
            end loop;
            begin
               if Ada.Strings.Fixed.Index (Fixed, ".") = 0
                 and then Ada.Strings.Fixed.Index (To_Upper (Fixed), "E") = 0
               then
                  Value := Long_Float (Long_Long_Integer'Value (Fixed));
               else
                  declare
                     F : constant String :=
                       (if Ada.Strings.Fixed.Index (Fixed, ".") = 0
                        then Fixed (Fixed'First .. Ada.Strings.Fixed.Index
                                      (To_Upper (Fixed), "E") - 1) & ".0" &
                          Fixed (Ada.Strings.Fixed.Index
                                   (To_Upper (Fixed), "E") .. Fixed'Last)
                        elsif Fixed (Fixed'Last) = '.' then Fixed & "0"
                        else Fixed);
                  begin
                     Value := Long_Float'Value (F);
                  end;
               end if;
            exception
               when others =>
                  Error (Src_Line, "bad number " & Lit);
                  Value := 0.0;
            end;
            Emit ((if D = Spectrum then 16#0E# else 16#7E#));
            for B of Number_Bytes (Value, D) loop
               Emit (B);
            end loop;
         end;
      end Number_Literal;

      --  BIN 0101: a binary literal
      procedure Binary_Number is
         S : constant Natural := P;
         V : Long_Float := 0.0;
      begin
         while P <= Text'Last and then Text (P) in '0' | '1' loop
            V := V * 2.0 + (if Text (P) = '1' then 1.0 else 0.0);
            Emit_Char (Text (P));
            P := P + 1;
         end loop;
         if P = S then
            return;
         end if;
         Emit (16#0E#);
         for B of Number_Bytes (V, D) loop
            Emit (B);
         end loop;
      end Binary_Number;

      function Try_Keyword return Boolean is
         Best_End : Natural := 0;
         Best_Code : Byte := 0;
         Prev_Ok : constant Boolean :=
           P = Text'First or else not Is_Alnum (Text (P - 1))
           or else not Is_Letter (Text (P));
      begin
         if not Prev_Ok then
            return False;
         end if;
         if D = Spectrum then
            for Code in Spec_Names'Range loop
               declare
                  E : constant Natural := Match (Text, P, Spec_Names (Code).all);
               begin
                  if E > Best_End then
                     Best_End := E;
                     Best_Code := Code;
                  end if;
               end;
            end loop;
            for Alias of Name_List'(+"GOTO", +"GOSUB") loop
               declare
                  E : constant Natural := Match (Text, P, Alias.all);
               begin
                  if E > Best_End then
                     Best_End := E;
                     Best_Code := (if Alias.all = "GOTO" then 16#EC# else 16#ED#);
                  end if;
               end;
            end loop;
         else
            for Code in ZX81_Names'Range loop
               if Code /= 16#C3# and then Code /= 16#C0# then
                  declare
                     E : constant Natural :=
                       Match (Text, P, ZX81_Names (Code).all);
                  begin
                     if E > Best_End then
                        Best_End := E;
                        Best_Code := Code;
                     end if;
                  end;
               end if;
            end loop;
            for Code in Byte range 16#40# .. 16#42# loop
               declare
                  E : constant Natural := Match (Text, P, Token_Text (Code, D));
               begin
                  if E > Best_End then
                     Best_End := E;
                     Best_Code := Code;
                  end if;
               end;
            end loop;
            for Alias of Name_List'(+"GO TO", +"GO SUB", +"RANDOMIZE",
                                    +"CONTINUE") loop
               declare
                  E : constant Natural := Match (Text, P, Alias.all);
               begin
                  if E > Best_End then
                     Best_End := E;
                     Best_Code :=
                       (if Alias.all = "GO TO" then 16#EC#
                        elsif Alias.all = "GO SUB" then 16#ED#
                        elsif Alias.all = "RANDOMIZE" then 16#F9#
                        else 16#E8#);
                  end if;
               end;
            end loop;
         end if;
         if Best_End = 0 then
            return False;
         end if;
         --  drop the spaces typed before the keyword
         Out_Len := Out_Len - Trail;
         Emit (Best_Code);
         P := Best_End;
         while P <= Text'Last and then Text (P) = ' ' loop
            P := P + 1;
         end loop;
         if Best_Code = 16#CE# and then D = Spectrum then
            Def_Fn := 1;
         end if;
         if Best_Code = 16#EA# then
            In_Rem := True;
         elsif Best_Code = 16#C4# and then D = Spectrum then
            Binary_Number;
         end if;
         return True;
      end Try_Keyword;

   begin
      if D = ZX80 then
         declare
            L, E : Unbounded_String;
         begin
            Basic_ZX80.Tokenize_Line (Text, Number, L, E);
            for C of To_String (L) loop
               Emit (Character'Pos (C));
            end loop;
            if Length (E) > 0 then
               Error (Src_Line, To_String (E));
            end if;
         end;
         return;
      end if;
      Trail := 0;
      Emit (Byte (Number / 256));
      Emit (Byte (Number mod 256));
      Emit (0);
      Emit (0);
      while P <= Text'Last loop
         declare
            C : constant Character := Text (P);
         begin
            if In_Rem then
               --  after a ':' the editor is in K mode even in a REM (TR-DOS
               --  and other extensions read their commands from there)
               if D = Spectrum and then Rem_K and then C /= ' '
                 and then Try_Keyword
               then
                  In_Rem := True;
                  Rem_K := False;
               else
                  if C = ':' then
                     Rem_K := True;
                  elsif C /= ' ' then
                     Rem_K := False;
                  end if;
                  Literal;
               end if;
            elsif Def_Fn > 0 and then C in '(' | ')' | ',' | '$'
              | 'a' .. 'z' | 'A' .. 'Z' | ' '
            then
               --  DEF FN f(a,b$): a hidden 5-byte slot after each parameter
               Emit_Char (C);
               P := P + 1;
               if C = '(' then
                  Def_Fn := 2;
               elsif C = ')' then
                  Def_Fn := 0;
               elsif Def_Fn = 2 and then C /= ',' and then C /= ' '
                 and then (P > Text'Last or else Text (P) /= '$')
               then
                  Emit (16#0E#);
                  for K in 1 .. 5 loop
                     Emit (0);
                  end loop;
               end if;
            elsif C = '"' then
               Emit_Char ('"');
               P := P + 1;
               while P <= Text'Last loop
                  if Text (P) = '"' then
                     if D = ZX81 and then P < Text'Last
                       and then Text (P + 1) = '"'
                     then
                        Emit (16#C0#);       --  quote image
                        P := P + 2;
                     elsif D = Spectrum and then P < Text'Last
                       and then Text (P + 1) = '"'
                     then
                        Emit_Char ('"');
                        Emit_Char ('"');
                        P := P + 2;
                     else
                        exit;
                     end if;
                  else
                     Literal;
                  end if;
               end loop;
               if P <= Text'Last then
                  Emit_Char ('"');
                  P := P + 1;
               else
                  Error (Src_Line, "missing closing quote");
               end if;
            elsif (Is_Digit (C) or else (C = '.' and then P < Text'Last
                                          and then Is_Digit (Text (P + 1))))
              and then (P = Text'First or else not Is_Letter (Text (P - 1)))
              and then (P = Text'First or else not Is_Digit (Text (P - 1)))
            then
               Number_Literal;
            elsif Try_Keyword then
               null;
            else
               Literal;
            end if;
         end;
      end loop;
      --  drop trailing spaces
      if not In_Rem then
         Out_Len := Out_Len - Trail;
      end if;
      Emit ((if D = Spectrum then 16#0D# else 16#76#));
      declare
         Len : constant Natural := Out_Len - Start - 4;
      begin
         Out_Buf (Start + 2) := Byte (Len mod 256);
         Out_Buf (Start + 3) := Byte (Len / 256);
      end;
   end Tokenize_Line;

   procedure Tokenize_Text (Text : String; D : Dialect) is
      Line_Start : Natural := Text'First;
      Src : Natural := 0;
      Last_Number : Integer := 0;
   begin
      Out_Len := 0;
      N_Errors := 0;
      N_Map := 0;
      Autorun := -1;
      while Line_Start <= Text'Last loop
         declare
            E : Natural := Line_Start;
         begin
            while E <= Text'Last and then Text (E) /= ASCII.LF loop
               E := E + 1;
            end loop;
            Src := Src + 1;
            declare
               Raw : String := Text (Line_Start .. E - 1);
               L : constant String := Ada.Strings.Fixed.Trim
                 (Raw, Ada.Strings.Both);
               P : Natural := L'First;
               Num : Integer := -1;
            begin
               for K in Raw'Range loop
                  if Raw (K) = ASCII.CR or else Raw (K) = ASCII.HT then
                     Raw (K) := ' ';
                  end if;
               end loop;
               if Src <= Max_Lines then
                  N_Map := Src;
                  Line_Map (Src) := -1;
               end if;
               if L'Length = 0 or else L (L'First) = ';'
                 or else (L'Length > 1 and then L (L'First .. L'First + 1) = "--")
               then
                  null;      --  blank or comment line
               elsif L (L'First) = '#' then
                  if L'Length > 10
                    and then To_Lower (L (L'First .. L'First + 9)) = "#autostart"
                  then
                     begin
                        Autorun := Integer'Value (L (L'First + 10 .. L'Last));
                     exception
                        when others => Error (Src, "bad #autostart");
                     end;
                  end if;
               else
                  while P <= L'Last and then Is_Digit (L (P)) loop
                     P := P + 1;
                  end loop;
                  if P > L'First then
                     Num := Integer'Value (L (L'First .. P - 1));
                  else
                     Num := Last_Number + 10;
                  end if;
                  if Num < 1 or else Num > 9999 then
                     Error (Src, "line number out of range");
                  elsif Num <= Last_Number then
                     Error (Src, "line numbers must increase");
                  else
                     while P <= L'Last and then L (P) = ' ' loop
                        P := P + 1;
                     end loop;
                     Tokenize_Line (L (P .. L'Last), Src, D, Num);
                     Last_Number := Num;
                     if Src <= Max_Lines then
                        Line_Map (Src) := Num;
                     end if;
                  end if;
               end if;
            end;
            Line_Start := E + 1;
         end;
      end loop;
   end Tokenize_Text;

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

   procedure Tokenize_File (Path : String; D : Dialect) is
   begin
      Tokenize_Text (Read_Text (Path), D);
   exception
      when others =>
         Out_Len := 0;
         N_Errors := 0;
         Error (0, "cannot read " & Path);
   end Tokenize_File;

   function Is_Source (Path : String) return Boolean is
      E : constant String := To_Lower (File_Ext.Of_Path (Path));
   begin
      return E = "bas" or else E = "zxb" or else E = "b81" or else E = "b80";
   end Is_Source;

   ---------------------------------------------------------------------
   --  Lister
   ---------------------------------------------------------------------

   function List_Sinclair (Data : Byte_Array; D : Dialect) return String;

   function List (Data : Byte_Array; D : Dialect) return String is
   begin
      if D = ZX80 then
         return Basic_ZX80.List (Data);
      end if;
      return List_Sinclair (Data, D);
   end List;

   function List_Sinclair (Data : Byte_Array; D : Dialect) return String is
      R : Unbounded_String;
      P : Natural := Data'First;
      End_Mark : constant Byte := (if D = Spectrum then 16#0D# else 16#76#);
   begin
      while P + 3 <= Data'Last loop
         declare
            Num : constant Natural :=
              Natural (Data (P)) * 256 + Natural (Data (P + 1));
            Len : constant Natural :=
              Natural (Data (P + 2)) + 256 * Natural (Data (P + 3));
            Q : Natural := P + 4;
            Last : constant Natural := Natural'Min (P + 3 + Len, Data'Last);
            In_Quote, In_Rem : Boolean := False;
            Line : Unbounded_String;
            procedure Put (S : String) is
            begin
               Append (Line, S);
            end Put;
            function Last_Char return Character is
              (if Length (Line) = 0 then ' '
               else Element (Line, Length (Line)));
         begin
            exit when Num > 9999;
            while Q <= Last loop
               declare
                  B : constant Byte := Data (Q);
               begin
                  exit when B = End_Mark and then Q = Last;
                  if D = Spectrum then
                     if B = 16#0E# and then not In_Quote and then not In_Rem
                     then
                        Q := Q + 5;
                     elsif B >= Spec_First and then not In_Quote
                       and then not In_Rem
                     then
                        declare
                           K : constant String := Spec_Names (B).all;
                        begin
                           if Last_Char /= ' ' and then Is_Letter (K (K'First))
                           then
                              Put (" ");
                           end if;
                           Put (K);
                           if Is_Letter (K (K'Last)) or else K (K'Last) in '$' | '#'
                           then
                              Put (" ");
                           end if;
                           In_Rem := B = 16#EA#;
                        end;
                     elsif B in 16#10# .. 16#17# and then Q < Last then
                        Put ("\{" & Ada.Strings.Fixed.Trim
                               (B'Image, Ada.Strings.Both) & "}\{" &
                             Ada.Strings.Fixed.Trim
                               (Data (Q + 1)'Image, Ada.Strings.Both) & "}");
                        Q := Q + 1;
                     elsif B = 16#60# then
                        Put ("\`");
                     elsif B = 16#7F# then
                        Put ("\*");
                     elsif B = Character'Pos ('\') then
                        Put ("\\");
                     elsif B in 16#80# .. 16#8F# then
                        declare
                           V : constant Natural := Natural (B - 16#80#);
                           Quad : constant String := " '.:";
                           L : constant Natural :=
                             (if V / 2 mod 2 = 1 then 1 else 0)
                             + (if V / 8 mod 2 = 1 then 2 else 0);
                           Rt : constant Natural :=
                             (if V mod 2 = 1 then 1 else 0)
                             + (if V / 4 mod 2 = 1 then 2 else 0);
                        begin
                           Put ("\" & Quad (L + 1) & Quad (Rt + 1));
                        end;
                     elsif B in 16#90# .. 16#A4# then
                        Put ("\" & Character'Val (Character'Pos ('a')
                                                  + Natural (B - 16#90#)));
                     elsif B in 32 .. 126 then
                        if B = Character'Pos ('"') and then not In_Rem then
                           In_Quote := not In_Quote;
                        end if;
                        Put ((1 => Character'Val (B)));
                     else
                        Put ("\{" & Ada.Strings.Fixed.Trim
                               (B'Image, Ada.Strings.Both) & "}");
                     end if;
                  else
                     if B = 16#7E# and then not In_Rem and then not In_Quote
                     then
                        Q := Q + 5;
                     elsif (B >= 16#C0# or else B in 16#40# .. 16#42#)
                       and then not In_Rem
                       and then (not In_Quote or else B = 16#C0#)
                     then
                        if B = 16#C0# then
                           Put ("""""");
                        else
                           declare
                              K : constant String := Token_Text (B, D);
                           begin
                              if Last_Char /= ' '
                                and then Is_Letter (K (K'First))
                              then
                                 Put (" ");
                              end if;
                              Put (K);
                              if Is_Letter (K (K'Last)) or else K (K'Last) = '$'
                              then
                                 Put (" ");
                              end if;
                              In_Rem := B = 16#EA#;
                           end;
                        end if;
                     elsif (B and 16#7F#) < 64 then
                        if B = 11 and then not In_Rem then
                           In_Quote := not In_Quote;
                        end if;
                        if B in 1 .. 7 | 128 .. 135 then
                           for Idx in ZX81_Block'Range loop
                              if ZX81_Block (Idx) = B then
                                 declare
                                    Quad : constant String := " '.:";
                                    L : constant Natural :=
                                      (if Idx / 2 mod 2 = 1 then 1 else 0)
                                      + (if Idx / 8 mod 2 = 1 then 2 else 0);
                                    Rt : constant Natural :=
                                      (if Idx mod 2 = 1 then 1 else 0)
                                      + (if Idx / 4 mod 2 = 1 then 2 else 0);
                                 begin
                                    Put ("\" & Quad (L + 1) & Quad (Rt + 1));
                                 end;
                              end if;
                           end loop;
                        elsif (B and 16#7F#) in 8 .. 10 then
                           Put ("\{" & Ada.Strings.Fixed.Trim
                                  (B'Image, Ada.Strings.Both) & "}");
                        else
                           if B >= 128 then
                              Put ("%");
                           end if;
                           Put ((1 => From_ZX81 (B)));
                        end if;
                     else
                        Put ("\{" & Ada.Strings.Fixed.Trim
                               (B'Image, Ada.Strings.Both) & "}");
                     end if;
                  end if;
               end;
               Q := Q + 1;
            end loop;
            declare
               S : String := To_String (Line);
               L : Natural := S'Last;
            begin
               while L >= S'First and then S (L) = ' ' loop
                  L := L - 1;
               end loop;
               Append (R, Ada.Strings.Fixed.Trim (Num'Image, Ada.Strings.Left)
                         & " " & S (S'First .. L) & ASCII.LF);
               pragma Unreferenced (S);
            end;
            P := P + 4 + Len;
         end;
      end loop;
      return To_String (R);
   end List_Sinclair;

   function Read_Bytes (Path : String) return Byte_Array is
      F : SIO.File_Type;
   begin
      SIO.Open (F, SIO.In_File, Path);
      declare
         D : Byte_Array (0 .. Natural (SIO.Size (F)) - 1);
      begin
         Byte_Array'Read (SIO.Stream (F), D);
         SIO.Close (F);
         return D;
      end;
   end Read_Bytes;

   function List_File (Path : String; Ok : out Boolean) return String is
   begin
      if not Ada.Directories.Exists (Path) then
         Ok := False;
         return "";
      end if;
      declare
         D : constant Byte_Array := Read_Bytes (Path);
         E : constant String := To_Lower (File_Ext.Of_Path (Path));
      begin
      Ok := True;
      if E = "o" or else E = "80" then
         declare
            Vars : constant Natural :=
              Natural (D (D'First + 8)) + 256 * Natural (D (D'First + 9))
              - 16#4000#;
         begin
            return List (D (D'First + 40 .. D'First + Vars - 1), ZX80);
         end;
      end if;
      if E = "p" or else E = "81" then
         declare
            D_File : constant Natural :=
              Natural (D (3)) + 256 * Natural (D (4)) - 16#4009#;
         begin
            return List (D (16#407D# - 16#4009# .. D_File - 1), ZX81);
         end;
      end if;
      --  .tap: a program header followed by its data block
      declare
         P : Natural := 0;
      begin
         while P + 1 < D'Length loop
            declare
               Len : constant Natural := Natural (D (P)) + 256 * Natural (D (P + 1));
            begin
               if Len = 19 and then D (P + 2) = 0 and then D (P + 3) = 0 then
                  declare
                     Prog_Len : constant Natural :=
                       Natural (D (P + 2 + 16)) + 256 * Natural (D (P + 2 + 17));
                     Q : constant Natural := P + 2 + Len;
                  begin
                     return List (D (Q + 3 .. Q + 2 + Prog_Len), Spectrum);
                  end;
               end if;
               P := P + 2 + Len;
            end;
         end loop;
      end;
      Ok := False;
      return "";
      end;
   exception
      when others =>
         Ok := False;
         return "";
   end List_File;

   ---------------------------------------------------------------------
   --  Building tapes
   ---------------------------------------------------------------------

   procedure Build (Source : String; D : Dialect;
                    Output : out Unbounded_String; Ok : out Boolean) is
      Base : constant String :=
        (if Ada.Directories.Extension (Source) = "" then Source
         else Source (Source'First .. Source'Last
                      - Ada.Directories.Extension (Source)'Length - 1));
      Path : constant String := Base & (case D is
                                           when Spectrum => ".tap",
                                           when ZX81 => ".p",
                                           when ZX80 => ".o");
      F : SIO.File_Type;
   begin
      Tokenize_File (Source, D);
      for I in 1 .. N_Errors loop
         if Report /= null then
            Report (Source & ":" & Ada.Strings.Fixed.Trim
                      (Errors (I).Line'Image, Ada.Strings.Left) &
                      ": error: " & To_String (Errors (I).Text));
         end if;
      end loop;
      Ok := N_Errors = 0;
      if not Ok then
         return;
      end if;
      SIO.Create (F, SIO.Out_File, Path);
      if D = Spectrum then
         declare
            Name : String (1 .. 10) := (others => ' ');
            Simple : constant String := Ada.Directories.Base_Name (Source);
            Header : Byte_Array (0 .. 18);
            Prog : constant Byte_Array := Program;
            Parity : Byte := 0;
            Line : constant Natural :=
              (if Autorun >= 0 then Autorun else 32768);
         begin
            for K in 1 .. Natural'Min (10, Simple'Length) loop
               Name (K) := Simple (Simple'First + K - 1);
            end loop;
            Header (0) := 0;
            Header (1) := 0;
            for K in 1 .. 10 loop
               Header (1 + K) := Character'Pos (Name (K));
            end loop;
            Header (12) := Byte (Prog'Length mod 256);
            Header (13) := Byte (Prog'Length / 256);
            Header (14) := Byte (Line mod 256);
            Header (15) := Byte (Line / 256);
            Header (16) := Byte (Prog'Length mod 256);
            Header (17) := Byte (Prog'Length / 256);
            for B of Header (0 .. 17) loop
               Parity := Parity xor B;
            end loop;
            Header (18) := Parity;
            Byte_Array'Write (SIO.Stream (F), (19, 0));
            Byte_Array'Write (SIO.Stream (F), Header);
            Byte_Array'Write (SIO.Stream (F),
                              (Byte ((Prog'Length + 2) mod 256),
                               Byte ((Prog'Length + 2) / 256), 16#FF#));
            Parity := 16#FF#;
            for B of Prog loop
               Parity := Parity xor B;
            end loop;
            Byte_Array'Write (SIO.Stream (F), Prog);
            Byte_Array'Write (SIO.Stream (F), (1 => Parity));
         end;
      elsif D = ZX80 then
         Byte_Array'Write (SIO.Stream (F),
                           Basic_ZX80.Make_O (Program,
                                              Basic_ZX80.Default_Sysvars));
      else
         Byte_Array'Write (SIO.Stream (F), Make_P (Program, Autorun));
      end if;
      SIO.Close (F);
      Output := To_Unbounded_String (Path);
      if Report /= null then
         Report ("wrote " & Path & " (" &
                 Ada.Strings.Fixed.Trim (Out_Len'Image, Ada.Strings.Left) &
                 " bytes of BASIC)");
      end if;
   exception
      when others =>
         Ok := False;
         if Report /= null then
            Report (Source & ": error: cannot write " & Path);
         end if;
   end Build;

   --  A .p image (system variables from &4009 up to the end of VARS) of a
   --  ZX81 with the program loaded; Run_Line >= 0 makes it run itself
   function Make_P (Prog : Byte_Array; Run_Line : Integer) return Byte_Array is
      Prog_At : constant := 16#407D#;
      D_File : constant Natural := Prog_At + Prog'Length;
      DF_Len : constant := 1 + 24 * 33;
      Vars : constant Natural := D_File + DF_Len;
      E_Line : constant Natural := Vars + 1;
      Img : Byte_Array (0 .. E_Line - 16#4009# - 1) := (others => 0);
      procedure W (Addr : Natural; V : Natural) is
      begin
         Img (Addr - 16#4009#) := Byte (V mod 256);
         Img (Addr - 16#4009# + 1) := Byte (V / 256 mod 256);
      end W;
      procedure B (Addr : Natural; V : Byte) is
      begin
         Img (Addr - 16#4009#) := V;
      end B;
      Next_Line : Natural := D_File;
   begin
      if Run_Line >= 0 then
         --  NXTLIN: the first line at or after Run_Line
         declare
            P : Natural := 0;
         begin
            while P + 3 < Prog'Length loop
               if Natural (Prog (P)) * 256 + Natural (Prog (P + 1)) >= Run_Line
               then
                  Next_Line := Prog_At + P;
                  exit;
               end if;
               P := P + 4 + Natural (Prog (P + 2))
                 + 256 * Natural (Prog (P + 3));
            end loop;
         end;
      end if;
      B (16#4009#, 0);                  --  VERSN
      W (16#400A#, 0);                  --  E_PPC
      W (16#400C#, D_File);
      W (16#400E#, D_File + 1);         --  DF_CC
      W (16#4010#, Vars);
      W (16#4012#, 0);                  --  DEST
      W (16#4014#, E_Line);
      W (16#4016#, E_Line);             --  CH_ADD
      W (16#4018#, 0);                  --  X_PTR
      W (16#401A#, E_Line);             --  STKBOT
      W (16#401C#, E_Line);             --  STKEND
      B (16#401E#, 0);                  --  BERG
      W (16#401F#, 16#405D#);           --  MEM
      B (16#4022#, 2);                  --  DF_SZ
      W (16#4023#, 0);                  --  S_TOP
      W (16#4025#, 16#FFFF#);           --  LAST_K
      B (16#4027#, 16#FF#);             --  DB_ST
      B (16#4028#, 55);                 --  MARGIN
      W (16#4029#, Next_Line);          --  NXTLIN
      W (16#402B#, 0);                  --  OLDPPC
      B (16#402D#, 0);                  --  FLAGX
      W (16#402E#, 0);                  --  STRLEN
      W (16#4030#, 16#0C8D#);           --  T_ADDR
      W (16#4032#, 0);                  --  SEED
      W (16#4034#, 16#FFFF#);           --  FRAMES
      W (16#4036#, 0);                  --  COORDS
      B (16#4038#, 16#BC#);             --  PR_CC
      B (16#4039#, 16#21#);             --  S_POSN
      B (16#403A#, 16#18#);
      B (16#403B#, 16#40#);             --  CDFLAG: SLOW
      B (16#405C#, 16#76#);             --  end of PRBUFF
      Img (Prog_At - 16#4009# .. Prog_At - 16#4009# + Prog'Length - 1) := Prog;
      B (D_File, 16#76#);
      for R in 0 .. 23 loop
         B (D_File + 1 + R * 33 + 32, 16#76#);
      end loop;
      B (Vars, 16#80#);
      return Img;
   end Make_P;

end Basic;
