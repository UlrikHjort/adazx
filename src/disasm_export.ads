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

--  Reverse engineering: a memory range as assembler source that the
--  Forge assembler turns back into the same bytes.
--
--  Code is found by following the program from entry points (jumps, calls
--  and RSTs; JP / JR / RET without a condition end a path) and from the
--  addresses the profiler saw executing; the rest is data (db lines, text
--  as strings).  Jump / call targets and (nn) operands in the range get
--  labels (Lxxxx); a label inside an instruction becomes an equ.

with Types; use Types;
with Disasm;

package Disasm_Export is

   type Address_List is array (Positive range <>) of Word;
   type Executed_Func is access function (Addr : Word) return Boolean;

   procedure Export (Read : Disasm.Reader; From, To : Word;
                     Entries : Address_List; Executed : Executed_Func;
                     Path : String; Ok : out Boolean;
                     Code_Bytes : out Natural);
   --  From .. To inclusive; Code_Bytes: how many were taken as code

end Disasm_Export;
