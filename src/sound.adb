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

with Config;
with AY;

package body Sound is

   T_Per_Sample : Float := 3_500_000.0 / Float (Sample_Rate);
   Pos   : Float := 0.0;       --  T-state reached by the output
   Next  : Float := 0.0;       --  T-state where the current sample ends
   Acc   : Float := 0.0;       --  integral of the level in this sample
   Beeper : Float := 0.0;
   Tape_Level : Float := 0.0;
   DC_In, DC_Out : Float := 0.0;

   procedure Reset is
   begin
      T_Per_Sample := Float (Config.CPU_Clock) / Float (Sample_Rate);
      Pos := 0.0;
      Next := T_Per_Sample;
      Acc := 0.0;
      Beeper := 0.0;
      Tape_Level := 0.0;
      AY_Enabled := Config.Is_128;
   end Reset;

   function Level return Float is
     (Beeper + (if Tape_Noise then Tape_Level * 0.15 else 0.0));

   procedure Emit is
      Mean : Float := Acc / T_Per_Sample;
      V : Float;
   begin
      if AY_Enabled then
         Mean := Mean * 0.6 + AY.Next_Sample (Sample_Rate) * 0.8;
      end if;
      --  Remove the DC level (the beeper idles at 0 or 1)
      V := Mean - DC_In + 0.995 * DC_Out;
      DC_In := Mean;
      DC_Out := V;
      V := V * Volume * 32767.0;
      if Sink /= null then
         Sink (Sample (Float'Max (-32767.0, Float'Min (32767.0, V))));
      end if;
   end Emit;

   procedure Update (T : Integer) is
      Target : constant Float := Float (T);
   begin
      while Next <= Target loop
         Acc := Acc + (Next - Pos) * Level;
         Emit;
         Pos := Next;
         Next := Next + T_Per_Sample;
         Acc := 0.0;
      end loop;
      if Target > Pos then
         Acc := Acc + (Target - Pos) * Level;
         Pos := Target;
      end if;
   end Update;

   procedure Set_Beeper (Level : Float; T : Integer) is
   begin
      if Level /= Beeper then
         Update (T);
         Beeper := Level;
      end if;
   end Set_Beeper;

   procedure Set_Tape (Level : Boolean; T : Integer) is
      L : constant Float := (if Level then 1.0 else 0.0);
   begin
      if L /= Tape_Level then
         Update (T);
         Tape_Level := L;
      end if;
   end Set_Tape;

   procedure End_Frame (Frame_T : Natural) is
   begin
      Update (Frame_T);
      Pos := Pos - Float (Frame_T);
      Next := Next - Float (Frame_T);
   end End_Frame;

end Sound;
