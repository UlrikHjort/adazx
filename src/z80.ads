-- ***************************************************************************
--                                AdaZX - Z80
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

--  Zilog Z80 CPU core with per-access timing.
--
--  Every memory and I/O access happens at its own T-state: the core keeps
--  the T-state counter Tstates.T and calls Contend / Contend_No_MREQ at
--  each bus cycle so the machine can add the ULA's contention delay for
--  that exact moment (the same model as Fuse, whose per-cycle test suite
--  this core passes).  All documented instructions, the undocumented
--  ones (IXH/IXL/IYH/IYL, SLL, DDCB register copies, ED mirrors, OUT (C),0),
--  the undocumented flags 3 and 5 including MEMPTR (WZ) and Q, interrupt
--  modes 0, 1 and 2, NMI, HALT and the EI delay.
--
--  Fetch is called for opcode fetches (M1) instead of Read, so a machine
--  can see or replace the opcode (the ZX81 builds its picture that way).
--  In_Port / Out_Port must advance Tstates.T by the 4 T-states of the I/O
--  cycle (plus any contention).

with Types; use Types;

generic
   with function Read (Addr : Word) return Byte;
   with procedure Write (Addr : Word; Value : Byte);
   with function Fetch (Addr : Word) return Byte;
   with function Contend (Addr : Word) return Natural;
   with function Contend_No_MREQ (Addr : Word) return Natural;
   with function In_Port (Port : Word) return Byte;
   with procedure Out_Port (Port : Word; Value : Byte);
   with function Int_Data return Byte;
   --  The byte on the data bus during an interrupt acknowledge (IM 2
   --  vector low byte, IM 0 instruction): &FF on a Spectrum.
package Z80 is

   A, F, B, C, D, E, H, L : Byte := 16#FF#;
   A2, F2, B2, C2, D2, E2, H2, L2 : Byte := 16#FF#;   --  alternate set
   IX, IY : Word := 16#FFFF#;
   SP : Word := 16#FFFF#;
   PC : Word := 0;
   I, R : Byte := 0;        --  R includes bit 7 (set by LD R,A)
   MEMPTR : Word := 0;      --  the internal WZ register
   Q : Byte := 0;           --  F if the last instruction changed it, else 0
   IFF1, IFF2 : Boolean := False;
   IM : Natural range 0 .. 2 := 0;
   Halted : Boolean := False;

   INT_Line    : Boolean := False;   --  level, active when True
   NMI_Pending : Boolean := False;   --  set on the NMI edge
   After_EI    : Boolean := False;   --  no interrupt before the next one

   procedure Reset;
   --  Power-on / RESET: PC = 0, interrupts off, IM 0, I = R = 0.

   procedure Step;
   --  Execute one instruction (with its prefixes), or accept a pending
   --  interrupt; Tstates.T advances by its length.

   function Interrupt_Accepted return Boolean;
   --  The last Step took a maskable interrupt (not an instruction).

   function AF return Word is (Make_Word (F, A));
   function BC return Word is (Make_Word (C, B));
   function DE return Word is (Make_Word (E, D));
   function HL return Word is (Make_Word (L, H));

end Z80;
