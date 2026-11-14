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

--  Z80 cross assembler for the forge (pasmo / sjasmplus style syntax).
--
--  Source syntax (case-insensitive mnemonics, directives and registers):
--    label / label:             global label (case sensitive)
--    .local                     local to the previous global label
--    name EQU expr, name = expr constants (DEFL / "=" may be redefined)
--    ; comment
--  Expressions: $FF #FF 0xFF 0FFh, %1010 0b1010, decimal, 'c', $ (address
--  of the current instruction), + - * / % & | ^ ~ << >> ! < > <= >= = ==
--  != <> && ||, ( ), LOW (x) / HIGH (x).
--  Directives (also with a leading '.'):
--    ORG addr          DB / DEFB / DEFM / DM / BYTE  bytes and "strings"
--    DW / DEFW / WORD  DS / DEFS / BLOCK n [, fill]  DZ (string + 0)
--    DC (last character with bit 7 set)              ALIGN n [, fill]
--    INCLUDE "file"    INCBIN "file" [, skip [, length]]
--    IF e / IFDEF n / IFNDEF n / ELSE / ENDIF        REPT n / ENDR
--    MACRO name [args] ... ENDM (called as "name a, b"; \1 or the
--    argument names inside)    END [start]     ENT expr (start address)
--    OUTPUT "file"     ERROR "text"  WARNING "text"   ASSERT e
--    LOADER / NOLOADER  Spectrum: a BASIC loader before the code (default)
--  All documented and undocumented instructions (IXH/IXL/IYH/IYL, SLL,
--  OUT (C),0, IN (C), "RLC (IX+d),B" register copies).
--
--  Building (Build) writes the binary and, for the Spectrum, a .tap with
--  a BASIC loader (CLEAR, LOAD ""CODE, RANDOMIZE USR start); for the
--  ZX81 (when assembling at 16514 = $4082) a .p with the code in a REM
--  line and RAND USR 16514.

with Types; use Types;
with Ada.Strings.Unbounded;

package Asm is

   subtype Ada_String is Ada.Strings.Unbounded.Unbounded_String;

   type Target_Type is (Spectrum, ZX81);
   Target : Target_Type := Spectrum;

   procedure Assemble (Path : String);
   --  Assemble the main source file; results are queried below.
   procedure Assemble_Text (Text : String; Name : String := "source");

   function Is_Source (Path : String) return Boolean;   --  .asm .z80 .s
   function Default_Output (Source : String) return String;

   procedure Build (Source : String; Output : out Ada_String; Ok : out Boolean);
   --  Assemble and write the binary, the tape (.tap / .p) and a label
   --  file (.lbl).  Writes "file:line: error: text" lines to Report.

   type Report_Proc is access procedure (Line : String);
   Report : Report_Proc := null;

   function Error_Count return Natural;      --  errors and warnings
   function Has_Errors return Boolean;       --  errors (not warnings)
   function Error_File (I : Positive) return String;
   function Error_Line (I : Positive) return Natural;
   function Error_Text (I : Positive) return String;
   function Is_Warning (I : Positive) return Boolean;

   function Has_Output return Boolean;
   function Low_Address return Word;
   function High_Address return Word;        --  inclusive
   function Output_Byte (A : Word) return Byte;
   function Start_Address return Word;       --  ENT / END / first byte
   function Has_Loader return Boolean;
   function Output_Name return String;       --  OUTPUT file ("" = none)
   function Code_Bytes return Byte_Array;    --  Low .. High
   procedure Write_Binary (Path : String; Ok : out Boolean);
   procedure Write_Labels (Path : String; Ok : out Boolean);

   function Spectrum_Tape return Byte_Array;
   --  The .tap image (loader + CODE block, or only the CODE block).
   function ZX81_Program return Byte_Array;
   --  The BASIC program of the ZX81 .p (REM line with the code, RAND USR).

   --  Debug information
   function File_Count return Natural;
   function File_Name (I : Positive) return String;   --  full path
   procedure Line_Of (A : Word; File : out Natural; Line : out Natural);
   --  Source line of the instruction starting at A (File = 0: none).
   procedure Address_Of (File : String; Line : Positive;
                         Found : out Boolean; A : out Word;
                         Code_Only : Boolean := False);
   --  First address generated by that line (Code_Only: by an instruction).
   function Is_Code (A : Word) return Boolean;
   function Label_At (A : Word) return String;   --  "" when none
   function Symbol_Count return Natural;
   function Symbol_Name (I : Positive) return String;
   function Symbol_Value (I : Positive) return Integer;
   function Lookup (Name : String; Value : out Integer) return Boolean;

end Asm;
