-- ***************************************************************************
--                                AdaZX - Ay
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

with Interfaces; use Interfaces;

package body AY is

   Volume : constant array (0 .. 15) of Float :=
     (0.0, 0.0106, 0.0150, 0.0222, 0.0320, 0.0466, 0.0665, 0.1039,
      0.1237, 0.1986, 0.2803, 0.3548, 0.4702, 0.5937, 0.7739, 1.0);

   Tone_Count : array (0 .. 2) of Natural := (others => 0);
   Tone_Out   : array (0 .. 2) of Boolean := (others => False);
   Noise_Count : Natural := 0;
   Noise_LFSR  : Unsigned_32 := 1;
   Noise_Out   : Boolean := False;
   Env_Count   : Natural := 0;
   Env_Step    : Integer := 0;      --  0 .. 15 position in the ramp
   Env_Holding : Boolean := False;
   Env_Attack  : Boolean := False;
   Half_Tick   : Boolean := False;
   Phase : Float := 0.0;            --  fractional ticks carried over

   procedure Reset is
   begin
      Regs := (others => 0);
      Regs (7) := 16#FF#;
      Selected := 0;
      Tone_Count := (others => 0);
      Noise_LFSR := 1;
      Env_Step := 0;
      Env_Holding := True;
   end Reset;

   procedure Select_Register (V : Byte) is
   begin
      if V < 16 then
         Selected := Natural (V);
      end if;
   end Select_Register;

   procedure Start_Envelope is
   begin
      Env_Attack := (Regs (13) and 4) /= 0;
      Env_Step := 0;
      Env_Count := 0;
      Env_Holding := False;
   end Start_Envelope;

   procedure Write (V : Byte) is
      Masks : constant array (0 .. 15) of Byte :=
        (16#FF#, 16#0F#, 16#FF#, 16#0F#, 16#FF#, 16#0F#, 16#1F#, 16#FF#,
         16#1F#, 16#1F#, 16#1F#, 16#FF#, 16#FF#, 16#0F#, 16#FF#, 16#FF#);
   begin
      Regs (Selected) := V and Masks (Selected);
      if Selected = 13 then
         Start_Envelope;
      end if;
   end Write;

   function Read return Byte is (Regs (Selected));

   function Env_Level return Natural is
     (if Env_Attack then Env_Step else 15 - Env_Step);

   procedure Env_Tick is
      Period : constant Natural :=
        Natural (Regs (11)) + 256 * Natural (Regs (12));
   begin
      if Env_Holding then
         return;
      end if;
      Env_Count := Env_Count + 1;
      if Env_Count < Natural'Max (Period, 1) then
         return;
      end if;
      Env_Count := 0;
      Env_Step := Env_Step + 1;
      if Env_Step > 15 then
         declare
            Shape : constant Byte := Regs (13);
         begin
            if (Shape and 8) = 0 then          --  0 .. 7: once, then 0
               Env_Holding := True;
               Env_Attack := True;            --  level = step = 0
               Env_Step := 0;
            elsif (Shape and 1) /= 0 then      --  hold
               if (Shape and 2) /= 0 then
                  Env_Attack := not Env_Attack;
               end if;
               Env_Step := 15;
               Env_Holding := True;
            else
               if (Shape and 2) /= 0 then      --  alternate
                  Env_Attack := not Env_Attack;
               end if;
               Env_Step := 0;
            end if;
         end;
      end if;
   end Env_Tick;

   procedure Tick is
      Mixer : constant Byte := Regs (7);
   begin
      for Ch in 0 .. 2 loop
         declare
            Period : constant Natural :=
              Natural (Regs (2 * Ch)) + 256 * Natural (Regs (2 * Ch + 1));
         begin
            Tone_Count (Ch) := Tone_Count (Ch) + 1;
            if Tone_Count (Ch) >= Natural'Max (Period, 1) then
               Tone_Count (Ch) := 0;
               Tone_Out (Ch) := not Tone_Out (Ch);
            end if;
         end;
      end loop;
      Half_Tick := not Half_Tick;
      if Half_Tick then
         Noise_Count := Noise_Count + 1;
         if Noise_Count >= Natural'Max (Natural (Regs (6) and 16#1F#), 1) then
            Noise_Count := 0;
            declare
               Bit : constant Unsigned_32 :=
                 (Noise_LFSR xor Shift_Right (Noise_LFSR, 3)) and 1;
            begin
               Noise_LFSR := Shift_Right (Noise_LFSR, 1)
                 or Shift_Left (Bit, 16);
               Noise_Out := (Noise_LFSR and 1) /= 0;
            end;
         end if;
         Env_Tick;
      end if;
      pragma Unreferenced (Mixer);
   end Tick;

   function Channel_Level return Float is
      Mixer : constant Byte := Regs (7);
      Sum : Float := 0.0;
   begin
      for Ch in 0 .. 2 loop
         declare
            Tone_Off : constant Boolean :=
              (Mixer and Shift_Left (Byte'(1), Ch)) /= 0;
            Noise_Off : constant Boolean :=
              (Mixer and Shift_Left (Byte'(8), Ch)) /= 0;
            On : constant Boolean :=
              (Tone_Off or else Tone_Out (Ch))
              and then (Noise_Off or else Noise_Out);
            Amp : constant Byte := Regs (8 + Ch);
            Level : constant Natural :=
              (if (Amp and 16#10#) /= 0 then Env_Level
               else Natural (Amp and 15));
         begin
            if On then
               Sum := Sum + Volume (Level);
            end if;
         end;
      end loop;
      return Sum / 3.0;
   end Channel_Level;

   function Next_Sample (Rate : Positive) return Float is
      Ticks_Per_Sample : constant Float := Float (Clock_Hz) / 8.0
        / Float (Rate);
      Sum : Float := 0.0;
      N : Natural := 0;
   begin
      Phase := Phase + Ticks_Per_Sample;
      while Phase >= 1.0 loop
         Tick;
         Sum := Sum + Channel_Level;
         N := N + 1;
         Phase := Phase - 1.0;
      end loop;
      return (if N = 0 then Channel_Level else Sum / Float (N));
   end Next_Sample;

end AY;
