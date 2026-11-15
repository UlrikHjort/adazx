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

--  Sinclair BASIC (ZX Spectrum 48K / 128K and ZX81) tokenizer and lister.
--
--  Text form: one line per text line, "10 PRINT AT 0,0;""HI""".  Keywords
--  are recognised in upper or lower case as whole words ("GO TO" and
--  "GOTO" both work); numbers get their hidden 5-byte form; lines
--  without a number are numbered automatically (previous + 10).
--  Escapes (as zmakebas): \a .. \u  UDG characters, \' \. \: and \
--  pairs for block graphics ("\:'" ...), \* copyright, \` pound,
--  \{n} any character code, \\ a backslash.  ZX81: %X is X in inverse
--  video.
--
--  Memory form (Spectrum): line number (2 bytes, high first), length
--  (2 bytes, low first, including the ENTER), text, &0D.  ZX81: the same
--  with NEWLINE (&76) and the ZX81 character set.

with Types; use Types;
with Ada.Strings.Unbounded;

package Basic is

   type Dialect is (Spectrum, ZX81, ZX80);
   --  ZX80: see Basic_ZX80

   function Is_Source (Path : String) return Boolean;
   --  .bas .zxb (Spectrum), .b81 (ZX81), .b80 (ZX80)

   procedure Tokenize_Text (Text : String; D : Dialect);
   procedure Tokenize_File (Path : String; D : Dialect);
   function Error_Count return Natural;
   function Error_Line (I : Positive) return Natural;
   function Error_Text (I : Positive) return String;
   function Program return Byte_Array;          --  the tokenised lines
   function Source_Line_Of (Basic_Line : Natural) return Natural;
   function Basic_Line_Of (Source_Line : Positive) return Integer;
   --  BASIC line number of a text line (1-based) of the last tokenised
   --  source, -1 when it has none.
   function Auto_Run_Line return Integer;
   --  From a first line "#autostart N" (-1 = none).

   procedure Build (Source : String; D : Dialect;
                    Output : out Ada.Strings.Unbounded.Unbounded_String;
                    Ok : out Boolean);
   --  Tokenize Source and write a tape: Source.tap with one BASIC program
   --  (Spectrum), or Source.p (ZX81).
   type Report_Proc is access procedure (Line : String);
   Report : Report_Proc := null;

   function List (Data : Byte_Array; D : Dialect) return String;
   --  The program in text form.
   function List_File (Path : String; Ok : out Boolean) return String;
   --  List a .tap (first BASIC program) or .p file.

   --  Keywords
   function Token_Text (Code : Byte; D : Dialect) return String;
   --  The keyword of a token ("" when Code is not a keyword).

   type Key_Kind is (Not_Keyword, K_Mode, Symbol_Shift, Extended,
                     Extended_Symbol);
   procedure Keyword_Key (Code : Byte; D : Dialect; Kind : out Key_Kind;
                          Key : out Character);
   --  How the keyword is entered on a 48K Spectrum / ZX81: in K mode with
   --  a letter (PRINT = P), with SYMBOL SHIFT (THEN = SS+G; ZX81: SHIFT),
   --  in E mode (CODE = E, I; ZX81: FUNCTION, I) or in E mode with SYMBOL
   --  SHIFT (INK = E, SS+X).  Key is a letter or digit.

   function Number_Bytes (Value : Long_Float; D : Dialect) return Byte_Array;
   --  The 5-byte floating point form (Spectrum small integers as
   --  00 sign low high 00).

   function Make_P (Prog : Byte_Array; Run_Line : Integer) return Byte_Array;
   --  A ZX81 .p image (system variables from &4009 to the end of the
   --  variables) holding the program; Run_Line >= 0 makes it run itself.

   function To_ZX81 (C : Character) return Byte;
   function From_ZX81 (B : Byte) return Character;

end Basic;
