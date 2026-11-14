-- ***************************************************************************
--                         AdaZX - Machine.Snapshots
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

--  Snapshot files: .z80 (versions 1 - 3, 48K / 128K / +2 / +2A / +3),
--  .szx (Fuse's ZX-State),
--  .sna (48K and 128K) and .azx, AdaZX's own format holding the complete
--  state of any model (including the ZX81).

private package Machine.Snapshots is

   procedure Peek_Model (Path : String; M : out Model_Type; Ok : out Boolean);
   --  The model a snapshot was taken on.

   procedure Load (Path : String; Ok : out Boolean);
   --  The machine must already be the snapshot's model.
   procedure Save (Path : String; Ok : out Boolean);

   procedure Peek_Model_Data (Kind : String; D : Byte_Array;
                              M : out Model_Type; Ok : out Boolean);
   procedure Load_Data (Kind : String; D : Byte_Array; Ok : out Boolean);
   --  The same from memory; Kind is "z80", "sna", "szx" or "azx" (as in
   --  the snapshots RZX recordings carry)

   function Error_Message return String;

end Machine.Snapshots;
