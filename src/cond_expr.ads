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

--  Expressions for breakpoint conditions, e.g.
--     a = 3 and [hl] <> 0        b > 10 || zf        {sp} = $1234
--  Values: numbers ($ff, #ff, 0xff, 0ffh, %1010, 255, 'c'), the registers
--  a f b c d e h l i r af bc de hl ix iy sp pc af' bc' de' hl' ixh ixl
--  iyh iyl, the flags sf zf hf pf nf cf (0 / 1), [expr] (a byte in
--  memory), {expr} (a word), and other names through Lookup (labels).
--  Operators, loosest first: or || ; and && ; = == != <> < > <= >= ;
--  + - | ^ ; * / & << >> ; unary - ~ ! not.  Comparisons give 0 / 1;
--  a condition holds when the value is not 0.  Case does not matter for
--  registers, flags and operators.

package Cond_Expr is

   type Register_Func is access function (Name : String; Value : out Integer)
                                          return Boolean;
   --  Registers and flags (lower case names), or labels: False when unknown
   type Peek_Func is access function (Addr : Natural) return Natural;

   Syntax_Error : exception;     --  with a message

   function Evaluate (Text : String; Names : Register_Func;
                      Labels : Register_Func; Peek : Peek_Func)
                      return Integer;

   function Error_Of (Text : String; Labels : Register_Func) return String;
   --  "" when Text is a valid expression, else what is wrong (registers
   --  are given dummy values, memory reads give 0).

end Cond_Expr;
