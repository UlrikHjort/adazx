--  ZX80 BASIC (the 4K integer BASIC of the Sinclair ZX80).
--
--  Lines are stored as the line number (high byte first), the text and
--  NEWLINE (&76), without a length.  Statement keywords (&E6 LIST ..
--  &FE REM) and THEN, TO, NOT, AND, OR are tokens, and so are the
--  operators ; , ( ) - + * / ** = > < (&D7 .. &E5).  Numbers are plain
--  digits (integers), functions such as PEEK or CHR$ are spelt out.
--  The character set differs from the ZX81's: " is 1, the block graphics
--  2 - 11, then £ $ : ? ( ) - + * / = > < ; , . and the digits / letters.
--  A .o file is the memory from &4000 (system variables) up to E_LINE;
--  the program starts at &4028.

with Types; use Types;
with Ada.Strings.Unbounded;

package Basic_ZX80 is

   function To_Code (C : Character) return Byte;
   function From_Code (B : Byte) return Character;
   function Token_Text (Code : Byte) return String;

   --  How a token is typed: Kind 1 = in K mode with Key (a letter),
   --  2 = with SHIFT + Key, 0 = not a token
   procedure Key_Of (Code : Byte; Kind : out Natural; Key : out Character);

   procedure Tokenize_Line
     (Text : String; Number : Natural;
      Line : out Ada.Strings.Unbounded.Unbounded_String;  --  the bytes
      Error : out Ada.Strings.Unbounded.Unbounded_String);
   --  One line in memory form (number, text, NEWLINE); bytes are held as
   --  Character'Val values in Line.

   function List (Data : Byte_Array) return String;

   function Make_O (Prog : Byte_Array; Sysvars : Byte_Array) return Byte_Array;
   --  A .o image of Prog with the system variables Sysvars (40 bytes from
   --  &4000) and VARS / E_LINE set for the program.
   function Default_Sysvars return Byte_Array;
   --  Those of a ZX80 just switched on.

end Basic_ZX80;
