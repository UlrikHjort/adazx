-- ***************************************************************************
--                               AdaZX - Sound
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

--  Sound output: the beeper (ULA port &FE bits 3 and 4), the tape signal
--  (optionally heard while loading, as on the real machine) and the AY
--  chip of the 128K models, mixed and resampled to 44.1 kHz in step with
--  the CPU's T-states.

package Sound is

   Sample_Rate : constant := 44_100;

   type Sample is range -32768 .. 32767;
   for Sample'Size use 16;

   type Sink_Proc is access procedure (S : Sample);
   Sink : Sink_Proc := null;

   AY_Enabled : Boolean := False;   --  set for the 128K models
   Tape_Noise : Boolean := True;    --  hear the tape while it plays
   Volume : Float := 0.6;

   procedure Reset;
   --  Silence; uses Config.CPU_Clock for the sample timing.

   procedure Set_Beeper (Level : Float; T : Integer);
   --  New beeper level (0.0 .. 1.0) from T-state T on.
   procedure Set_Tape (Level : Boolean; T : Integer);

   procedure Update (T : Integer);
   --  Produce the samples up to T-state T.

   procedure End_Frame (Frame_T : Natural);
   --  Produce the rest of the frame; T-states restart at 0.

end Sound;
