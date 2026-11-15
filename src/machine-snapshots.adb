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

with File_Ext;
with Ada.Streams.Stream_IO;
with Ada.Directories;
with Ada.Characters.Handling;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces; use Interfaces;
with Memory;
with ULA;
with AY;
with Tstates;
with Interfaces.C;
with System;

package body Machine.Snapshots is

   package SIO renames Ada.Streams.Stream_IO;
   use type Config.Model_Type;

   Err : Unbounded_String;
   function Error_Message return String is (To_String (Err));

   function Ext (Path : String) return String is
     (Ada.Characters.Handling.To_Lower (File_Ext.Of_Path (Path)));

   function Read_File (Path : String) return Byte_Array is
      F : SIO.File_Type;
   begin
      SIO.Open (F, SIO.In_File, Path);
      declare
         D : Byte_Array (0 .. Natural (SIO.Size (F)) - 1);
      begin
         Byte_Array'Read (SIO.Stream (F), D);
         SIO.Close (F);
         return D;
      end;
   end Read_File;

   procedure Write_File (Path : String; D : Byte_Array) is
      F : SIO.File_Type;
   begin
      SIO.Create (F, SIO.Out_File, Path);
      Byte_Array'Write (SIO.Stream (F), D);
      SIO.Close (F);
   end Write_File;

   function W (D : Byte_Array; I : Natural) return Word is
     (Make_Word (D (D'First + I), D (D'First + I + 1)));

   ---------------------------------------------------------------------
   --  .z80 header facts
   ---------------------------------------------------------------------

   function Z80_Model (D : Byte_Array) return Model_Type is
   begin
      if W (D, 6) /= 0 then
         return Config.ZX48;          --  version 1
      end if;
      declare
         Extra : constant Natural := Natural (W (D, 30));
         HW : constant Byte := D (D'First + 34);
         Modified : constant Boolean := (D (D'First + 37) and 16#80#) /= 0;
      begin
         if Extra = 23 then
            return (if HW in 3 .. 4 then
                      (if Modified then Config.Plus2 else Config.ZX128)
                    else Config.ZX48);
         end if;
         case HW is
            when 4 .. 6 =>
               return (if Modified then Config.Plus2 else Config.ZX128);
            when 7 | 8 =>
               return (if Modified then Config.Plus2A else Config.Plus3);
            when 9 => return Config.Pentagon;
            when 12 => return Config.Plus2;
            when 13 => return Config.Plus2A;
            when 14 => return Config.TC2048;
            when others => return Config.ZX48;
         end case;
      end;
   end Z80_Model;

   procedure Peek_Model (Path : String; M : out Model_Type; Ok : out Boolean)
   is
   begin
      Peek_Model_Data (Ext (Path), Read_File (Path), M, Ok);
   exception
      when others =>
         Ok := False;
         M := Config.ZX48;
         Err := To_Unbounded_String ("cannot read " & Path);
   end Peek_Model;

   ---------------------------------------------------------------------
   --  Common register handling
   ---------------------------------------------------------------------

   procedure Set_Bank (Bank : Natural; D : Byte_Array) is
   begin
      for K in 0 .. Natural'Min (D'Length, 16#4000#) - 1 loop
         Memory.Store (Memory.RAM_Base (Bank) + K) := D (D'First + K);
      end loop;
   end Set_Bank;

   procedure After_Load (Border : Natural) is
   begin
      ULA.Border_Colour := Border mod 8;
      Last_FE := Byte (Border mod 8);
      Tstates.T := 0;
      Restart_Frame_State;
      CPU.Halted := False;
      CPU.After_EI := False;
   end After_Load;

   ---------------------------------------------------------------------
   --  .sna
   ---------------------------------------------------------------------

   procedure Load_SNA (D : Byte_Array; Ok : out Boolean) is
      H : constant Natural := D'First;
   begin
      Ok := D'Length >= 49179;
      if not Ok then
         Err := To_Unbounded_String ("short .sna file");
         return;
      end if;
      CPU.I := D (H);
      CPU.L2 := D (H + 1); CPU.H2 := D (H + 2);
      CPU.E2 := D (H + 3); CPU.D2 := D (H + 4);
      CPU.C2 := D (H + 5); CPU.B2 := D (H + 6);
      CPU.F2 := D (H + 7); CPU.A2 := D (H + 8);
      CPU.L := D (H + 9); CPU.H := D (H + 10);
      CPU.E := D (H + 11); CPU.D := D (H + 12);
      CPU.C := D (H + 13); CPU.B := D (H + 14);
      CPU.IY := W (D, 15);
      CPU.IX := W (D, 17);
      CPU.IFF2 := (D (H + 19) and 4) /= 0;
      CPU.IFF1 := CPU.IFF2;
      CPU.R := D (H + 20);
      CPU.F := D (H + 21); CPU.A := D (H + 22);
      CPU.SP := W (D, 23);
      CPU.IM := Natural (D (H + 25) and 3) mod 3;
      Set_Bank (5, D (H + 27 .. H + 27 + 16#3FFF#));
      Set_Bank (2, D (H + 27 + 16#4000# .. H + 27 + 16#7FFF#));
      if D'Length = 49179 then
         Set_Bank (0, D (H + 27 + 16#8000# .. H + 27 + 16#BFFF#));
         Memory.Reset_Paging;
         --  PC on the stack (RETN)
         CPU.PC := Make_Word (Memory.Read (CPU.SP), Memory.Read (CPU.SP + 1));
         CPU.SP := CPU.SP + 2;
      else
         declare
            P : constant Natural := H + 27 + 16#C000#;
            Port : constant Byte := D (P + 2);
            Paged : constant Natural := Natural (Port and 7);
            Q : Natural := P + 4;
         begin
            Set_Bank (Paged, D (H + 27 + 16#8000# .. H + 27 + 16#BFFF#));
            CPU.PC := W (D, P - H);
            for Bank in 0 .. 7 loop
               if Bank /= 5 and then Bank /= 2 and then Bank /= Paged
                 and then Q + 16#3FFF# <= D'Last
               then
                  Set_Bank (Bank, D (Q .. Q + 16#3FFF#));
                  Q := Q + 16#4000#;
               end if;
            end loop;
            Memory.Paging_Locked := False;
            Memory.Write_7FFD (Port);
         end;
      end if;
      After_Load (Natural (D (H + 26)));
   end Load_SNA;

   function Save_SNA return Byte_Array is
      Is48 : constant Boolean := Config.Is_48_Type;
      Size : constant Natural := (if Is48 then 49179 else 131103);
      D : Byte_Array (0 .. Size - 1) := (others => 0);
      SP : Word := CPU.SP;
      Paged : constant Natural := Natural (Memory.Port_7FFD and 7);
      function Bank_Byte (Bank, Ofs : Natural) return Byte is
        (Memory.Store (Memory.RAM_Base (Bank) + Ofs));
   begin
      if Is48 then
         SP := SP - 2;            --  push PC
         Memory.Write (SP, Lo (CPU.PC));
         Memory.Write (SP + 1, Hi (CPU.PC));
      end if;
      D (0 .. 26) :=
        (CPU.I, CPU.L2, CPU.H2, CPU.E2, CPU.D2, CPU.C2, CPU.B2, CPU.F2,
         CPU.A2, CPU.L, CPU.H, CPU.E, CPU.D, CPU.C, CPU.B, Lo (CPU.IY),
         Hi (CPU.IY), Lo (CPU.IX), Hi (CPU.IX),
         (if CPU.IFF2 then 4 else 0), CPU.R, CPU.F, CPU.A, Lo (SP), Hi (SP),
         Byte (CPU.IM), Byte (ULA.Border_Colour));
      for K in 0 .. 16#3FFF# loop
         D (27 + K) := Bank_Byte (5, K);
         D (27 + 16#4000# + K) := Bank_Byte (2, K);
         D (27 + 16#8000# + K) := Bank_Byte ((if Is48 then 0 else Paged), K);
      end loop;
      if Is48 then
         Memory.Write (SP, 0);
         Memory.Write (SP + 1, 0);
         return D;
      end if;
      declare
         P : constant Natural := 27 + 16#C000#;
         Q : Natural := P + 4;
      begin
         D (P) := Lo (CPU.PC);
         D (P + 1) := Hi (CPU.PC);
         D (P + 2) := Memory.Port_7FFD;
         D (P + 3) := 0;
         for Bank in 0 .. 7 loop
            if Bank /= 5 and then Bank /= 2 and then Bank /= Paged then
               for K in 0 .. 16#3FFF# loop
                  D (Q + K) := Bank_Byte (Bank, K);
               end loop;
               Q := Q + 16#4000#;
            end if;
         end loop;
         return D (0 .. Q - 1);
      end;
   end Save_SNA;

   ---------------------------------------------------------------------
   --  .z80
   ---------------------------------------------------------------------

   --  Decompress (ED ED n b = n times b) Src into Dst
   procedure Unpack (Src : Byte_Array; Dst : out Byte_Array;
                     Stop_At_End_Mark : Boolean) is
      I : Natural := Src'First;
      O : Natural := Dst'First;
   begin
      Dst := (others => 0);
      while I <= Src'Last and then O <= Dst'Last loop
         if Stop_At_End_Mark and then I + 3 <= Src'Last
           and then Src (I .. I + 3) = (0, 16#ED#, 16#ED#, 0)
         then
            exit;
         end if;
         if I + 3 <= Src'Last and then Src (I) = 16#ED#
           and then Src (I + 1) = 16#ED#
         then
            for K in 1 .. Natural (Src (I + 2)) loop
               exit when O > Dst'Last;
               Dst (O) := Src (I + 3);
               O := O + 1;
            end loop;
            I := I + 4;
         else
            Dst (O) := Src (I);
            O := O + 1;
            I := I + 1;
         end if;
      end loop;
   end Unpack;

   procedure Load_Z80 (D : Byte_Array; Ok : out Boolean) is
      H : constant Natural := D'First;
      Flags1 : Byte := D (H + 12);
      Version1 : constant Boolean := W (D, 6) /= 0;
   begin
      Ok := True;
      if Flags1 = 255 then
         Flags1 := 1;
      end if;
      CPU.A := D (H); CPU.F := D (H + 1);
      CPU.C := D (H + 2); CPU.B := D (H + 3);
      CPU.L := D (H + 4); CPU.H := D (H + 5);
      CPU.SP := W (D, 8);
      CPU.I := D (H + 10);
      CPU.R := (D (H + 11) and 16#7F#) or Shift_Left (Flags1 and 1, 7);
      CPU.E := D (H + 13); CPU.D := D (H + 14);
      CPU.C2 := D (H + 15); CPU.B2 := D (H + 16);
      CPU.E2 := D (H + 17); CPU.D2 := D (H + 18);
      CPU.L2 := D (H + 19); CPU.H2 := D (H + 20);
      CPU.A2 := D (H + 21); CPU.F2 := D (H + 22);
      CPU.IY := W (D, 23);
      CPU.IX := W (D, 25);
      CPU.IFF1 := D (H + 27) /= 0;
      CPU.IFF2 := D (H + 28) /= 0;
      CPU.IM := Natural (D (H + 29) and 3) mod 3;
      Memory.Reset_Paging;
      if Version1 then
         CPU.PC := W (D, 6);
         declare
            Mem : Byte_Array (0 .. 16#BFFF#);
         begin
            if (Flags1 and 16#20#) /= 0 then
               Unpack (D (H + 30 .. D'Last), Mem, True);
            else
               Mem := D (H + 30 .. H + 30 + 16#BFFF#);
            end if;
            Set_Bank (5, Mem (0 .. 16#3FFF#));
            Set_Bank (2, Mem (16#4000# .. 16#7FFF#));
            Set_Bank (0, Mem (16#8000# .. 16#BFFF#));
         end;
      else
         declare
            Extra : constant Natural := Natural (W (D, 30));
            P : Natural := H + 32 + Extra;
            Is128 : constant Boolean := Config.Is_128;
         begin
            CPU.PC := W (D, 32);
            if Is128 then
               AY.Reset;
               for K in 0 .. 15 loop
                  AY.Select_Register (Byte (K));
                  AY.Write (D (H + 39 + K));
               end loop;
               AY.Select_Register (D (H + 38));
            end if;
            while P + 2 < D'Last loop
               declare
                  Len : constant Natural := Natural (W (D, P - H));
                  Page : constant Natural := Natural (D (P + 2));
                  Data_Len : constant Natural :=
                    (if Len = 16#FFFF# then 16#4000# else Len);
                  Block : Byte_Array (0 .. 16#3FFF#);
                  Bank : Integer := -1;
               begin
                  exit when P + 3 + Data_Len - 1 > D'Last;
                  if Len = 16#FFFF# then
                     Block := D (P + 3 .. P + 3 + 16#3FFF#);
                  else
                     Unpack (D (P + 3 .. P + 3 + Len - 1), Block, False);
                  end if;
                  if Is128 then
                     if Page in 3 .. 10 then
                        Bank := Page - 3;
                     end if;
                  else
                     Bank := (case Page is when 4 => 2, when 5 => 0,
                                 when 8 => 5, when others => -1);
                  end if;
                  if Bank >= 0 then
                     Set_Bank (Bank, Block);
                  end if;
                  P := P + 3 + Data_Len;
               end;
            end loop;
            if Is128 then
               Memory.Paging_Locked := False;
               if Config.Is_Plus3_Type and then Extra >= 55 then
                  Memory.Write_1FFD (D (H + 86));
               end if;
               Memory.Write_7FFD (D (H + 35));
            end if;
            if Model = Config.TC2048 then
               ULA.SCLD := D (H + 36);      --  last OUT to &FF
            end if;
         end;
      end if;
      After_Load (Natural (Shift_Right (Flags1, 1) and 7));
   end Load_Z80;

   function Pack (Src : Byte_Array) return Byte_Array is
      R : Byte_Array (0 .. Src'Length * 2);
      N : Natural := 0;
      I : Natural := Src'First;
   begin
      while I <= Src'Last loop
         declare
            Run : Natural := 1;
         begin
            while I + Run <= Src'Last and then Src (I + Run) = Src (I)
              and then Run < 255
            loop
               Run := Run + 1;
            end loop;
            if (Run >= 5 or else (Src (I) = 16#ED# and then Run >= 2)) then
               R (N .. N + 3) := (16#ED#, 16#ED#, Byte (Run), Src (I));
               N := N + 4;
               I := I + Run;
            elsif Src (I) = 16#ED# then
               --  a single ED: the next byte must not start a run
               R (N) := 16#ED#;
               N := N + 1;
               I := I + 1;
               if I <= Src'Last then
                  R (N) := Src (I);
                  N := N + 1;
                  I := I + 1;
               end if;
            else
               R (N) := Src (I);
               N := N + 1;
               I := I + 1;
            end if;
         end;
      end loop;
      return R (0 .. N - 1);
   end Pack;

   function Save_Z80 return Byte_Array is
      Out_Buf : Byte_Array (0 .. 200_000);
      N : Natural := 0;
      procedure Put (B : Byte) is
      begin
         Out_Buf (N) := B;
         N := N + 1;
      end Put;
      procedure Put_W (V : Word) is
      begin
         Put (Lo (V));
         Put (Hi (V));
      end Put_W;
      Is128 : constant Boolean := Config.Is_128;
   begin
      Put (CPU.A); Put (CPU.F); Put (CPU.C); Put (CPU.B);
      Put (CPU.L); Put (CPU.H);
      Put_W (0);                          --  version 2+
      Put_W (CPU.SP);
      Put (CPU.I);
      Put (CPU.R and 16#7F#);
      Put (Shift_Right (CPU.R, 7) or Shift_Left (Byte (ULA.Border_Colour), 1));
      Put (CPU.E); Put (CPU.D);
      Put (CPU.C2); Put (CPU.B2); Put (CPU.E2); Put (CPU.D2);
      Put (CPU.L2); Put (CPU.H2); Put (CPU.A2); Put (CPU.F2);
      Put_W (CPU.IY);
      Put_W (CPU.IX);
      Put ((if CPU.IFF1 then 1 else 0));
      Put ((if CPU.IFF2 then 1 else 0));
      Put (Byte (CPU.IM));
      Put_W (55);                         --  version 3 with &1FFD
      Put_W (CPU.PC);
      Put ((case Model is
               when Config.ZX128 => 4, when Config.Plus2 => 12,
               when Config.Plus2A => 13, when Config.Plus3 => 7,
               when Config.Pentagon => 9, when Config.TC2048 => 14,
               when others => 0));
      Put ((if Is128 then Memory.Port_7FFD else 0));
      Put ((if Model = Config.TC2048 then ULA.SCLD else 0));  --  IF1 / &FF
      Put ((if Is128 then 4 else 0));     --  AY in use
      Put (Byte (AY.Selected));
      for K in 0 .. 15 loop
         Put (AY.Regs (K));
      end loop;
      for K in 1 .. 31 loop               --  T-states, flags, ...
         Put (0);
      end loop;
      Put ((if Config.Is_Plus3_Type then Memory.Port_1FFD else 0));
      declare
         procedure Block (Bank : Natural; Page : Natural) is
            Raw : Byte_Array (0 .. 16#3FFF#);
         begin
            for K in Raw'Range loop
               Raw (K) := Memory.Store (Memory.RAM_Base (Bank) + K);
            end loop;
            declare
               P : constant Byte_Array := Pack (Raw);
            begin
               if P'Length >= 16#4000# then
                  Put_W (16#FFFF#);
                  Put (Byte (Page));
                  Out_Buf (N .. N + 16#3FFF#) := Raw;
                  N := N + 16#4000#;
               else
                  Put_W (Word (P'Length));
                  Put (Byte (Page));
                  Out_Buf (N .. N + P'Length - 1) := P;
                  N := N + P'Length;
               end if;
            end;
         end Block;
      begin
         if Is128 then
            for Bank in 0 .. 7 loop
               Block (Bank, Bank + 3);
            end loop;
         else
            Block (2, 4);
            Block (0, 5);
            Block (5, 8);
         end if;
      end;
      return Out_Buf (0 .. N - 1);
   end Save_Z80;

   ---------------------------------------------------------------------
   --  .azx
   ---------------------------------------------------------------------

   function Save_AZX return Byte_Array is
      Out_Buf : Byte_Array (0 .. 8 * 16#4000# + 1000);
      N : Natural := 0;
      procedure Put (B : Byte) is
      begin
         Out_Buf (N) := B;
         N := N + 1;
      end Put;
      procedure Put_W (V : Word) is
      begin
         Put (Lo (V));
         Put (Hi (V));
      end Put_W;
      procedure Put_I (V : Integer) is
         U : constant Unsigned_32 := Unsigned_32'Mod (V);
      begin
         Put_W (Word (U and 16#FFFF#));
         Put_W (Word (Shift_Right (U, 16)));
      end Put_I;
      function B (V : Boolean) return Byte is (if V then 1 else 0);
   begin
      Put (65); Put (90); Put (88); Put (49);         --  "AZX1"
      Put (Byte (Model_Type'Pos (Model)));
      Put (CPU.A); Put (CPU.F); Put (CPU.B); Put (CPU.C);
      Put (CPU.D); Put (CPU.E); Put (CPU.H); Put (CPU.L);
      Put (CPU.A2); Put (CPU.F2); Put (CPU.B2); Put (CPU.C2);
      Put (CPU.D2); Put (CPU.E2); Put (CPU.H2); Put (CPU.L2);
      Put_W (CPU.IX); Put_W (CPU.IY); Put_W (CPU.SP); Put_W (CPU.PC);
      Put (CPU.I); Put (CPU.R); Put_W (CPU.MEMPTR); Put (CPU.Q);
      Put (B (CPU.IFF1)); Put (B (CPU.IFF2)); Put (Byte (CPU.IM));
      Put (B (CPU.Halted)); Put (B (CPU.After_EI));
      Put_I (Tstates.T);
      Put (Memory.Port_7FFD); Put (Memory.Port_1FFD);
      Put (B (Memory.Paging_Locked));
      Put (Last_FE); Put (Byte (ULA.Border_Colour));
      Put (Byte (AY.Selected));
      for K in 0 .. 15 loop
         Put (AY.Regs (K));
      end loop;
      Put (B (NMI_Gen)); Put (B (VSync)); Put (Byte (Line_Counter));
      Put_I (Next_HSync);
      Put_I (Memory.ZX81_RAM_Size);
      Put (B (Memory.ZX81_RAM_2000));
      for K in 0 .. 8 * 16#4000# - 1 loop
         Put (Memory.Store (K));
      end loop;
      return Out_Buf (0 .. N - 1);
   end Save_AZX;

   procedure Load_AZX (D : Byte_Array; Ok : out Boolean) is
      P : Natural := D'First + 5;
      function Get return Byte is
         V : constant Byte := D (P);
      begin
         P := P + 1;
         return V;
      end Get;
      function Get_W return Word is
         L : constant Byte := Get;
      begin
         return Make_Word (L, Get);
      end Get_W;
      function Get_I return Integer is
         L : constant Word := Get_W;
         H2 : constant Word := Get_W;
         U : constant Unsigned_32 :=
           Unsigned_32 (L) or Shift_Left (Unsigned_32 (H2), 16);
      begin
         return (if U >= 2 ** 31 then Integer (Long_Long_Integer (U) - 2 ** 32)
                 else Integer (U));
      end Get_I;
      P7, P1 : Byte;
      Border : Natural;
   begin
      CPU.A := Get; CPU.F := Get; CPU.B := Get; CPU.C := Get;
      CPU.D := Get; CPU.E := Get; CPU.H := Get; CPU.L := Get;
      CPU.A2 := Get; CPU.F2 := Get; CPU.B2 := Get; CPU.C2 := Get;
      CPU.D2 := Get; CPU.E2 := Get; CPU.H2 := Get; CPU.L2 := Get;
      CPU.IX := Get_W; CPU.IY := Get_W; CPU.SP := Get_W; CPU.PC := Get_W;
      CPU.I := Get; CPU.R := Get; CPU.MEMPTR := Get_W; CPU.Q := Get;
      CPU.IFF1 := Get /= 0; CPU.IFF2 := Get /= 0;
      CPU.IM := Natural (Get) mod 3;
      CPU.Halted := Get /= 0;
      CPU.After_EI := Get /= 0;
      declare
         Saved_T : constant Integer := Get_I;
      begin
         P7 := Get;
         P1 := Get;
         Memory.Paging_Locked := False;
         Memory.Port_1FFD := 0;
         Memory.Reset_Paging;
         Memory.Write_1FFD (P1);
         Memory.Write_7FFD (P7);
         Memory.Paging_Locked := Get /= 0;
         Last_FE := Get;
         Border := Natural (Get);
         AY.Reset;
         declare
            Sel : constant Byte := Get;
         begin
            for K in 0 .. 15 loop
               AY.Select_Register (Byte (K));
               AY.Write (Get);
            end loop;
            AY.Select_Register (Sel);
         end;
         NMI_Gen := Get /= 0;
         VSync := Get /= 0;
         Line_Counter := Natural (Get) mod 8;
         declare
            NH : constant Integer := Get_I;
         begin
            Memory.ZX81_RAM_Size := Get_I;
            Memory.ZX81_RAM_2000 := Get /= 0;
            for K in 0 .. 8 * 16#4000# - 1 loop
               Memory.Store (K) := Get;
            end loop;
            After_Load (Border);
            Tstates.T := Saved_T;
            Next_HSync := NH;
         end;
      end;
      Ok := True;
   exception
      when others =>
         Ok := False;
         Err := To_Unbounded_String ("damaged .azx snapshot");
   end Load_AZX;

   ---------------------------------------------------------------------
   --  .szx (ZX-State, as written by Fuse and others)
   ---------------------------------------------------------------------

   function Z_Uncompress (Dest : System.Address;
                          Dest_Len : access Interfaces.C.unsigned_long;
                          Source : System.Address;
                          Source_Len : Interfaces.C.unsigned_long)
                          return Interfaces.C.int;
   pragma Import (C, Z_Uncompress, "uncompress");
   function Z_Compress (Dest : System.Address;
                        Dest_Len : access Interfaces.C.unsigned_long;
                        Source : System.Address;
                        Source_Len : Interfaces.C.unsigned_long)
                        return Interfaces.C.int;
   pragma Import (C, Z_Compress, "compress");

   function SZX_Model (Id : Byte) return Model_Type is
     (case Id is
         when 2 => Config.ZX128,
         when 3 => Config.Plus2,
         when 4 => Config.Plus2A,
         when 5 | 6 => Config.Plus3,
         when 7 => Config.Pentagon,
         when 8 => Config.TC2048,
         when others => Config.ZX48);

   function Tag (D : Byte_Array; I : Natural) return String is
     (Character'Val (D (I)) & Character'Val (D (I + 1)) &
      Character'Val (D (I + 2)) & Character'Val (D (I + 3)));

   function L32 (D : Byte_Array; I : Natural) return Natural is
     (Natural (D (I)) + 256 * Natural (D (I + 1))
      + 65536 * Natural (D (I + 2)) + 16777216 * Natural (D (I + 3) and 127));

   procedure Load_SZX (D : Byte_Array; Ok : out Boolean) is
      P : Natural := D'First + 8;
      Border : Natural := 7;
      P7, P1 : Byte := 0;
      use type Interfaces.C.int;
   begin
      Ok := D'Length >= 8 and then Tag (D, D'First) = "ZXST";
      if not Ok then
         Err := To_Unbounded_String ("not an .szx snapshot");
         return;
      end if;
      Memory.Reset_Paging;
      AY.Reset;
      while P + 7 <= D'Last loop
         declare
            Id : constant String := Tag (D, P);
            Size : constant Natural := L32 (D, P + 4);
            B : constant Natural := P + 8;
         begin
            exit when B + Size - 1 > D'Last;
            if Id = "Z80R" and then Size >= 37 then
               declare
                  function RW (I : Natural) return Word is
                    (Make_Word (D (B + I), D (B + I + 1)));
               begin
                  CPU.F := D (B); CPU.A := D (B + 1);
                  CPU.C := D (B + 2); CPU.B := D (B + 3);
                  CPU.E := D (B + 4); CPU.D := D (B + 5);
                  CPU.L := D (B + 6); CPU.H := D (B + 7);
                  CPU.F2 := D (B + 8); CPU.A2 := D (B + 9);
                  CPU.C2 := D (B + 10); CPU.B2 := D (B + 11);
                  CPU.E2 := D (B + 12); CPU.D2 := D (B + 13);
                  CPU.L2 := D (B + 14); CPU.H2 := D (B + 15);
                  CPU.IX := RW (16); CPU.IY := RW (18);
                  CPU.SP := RW (20); CPU.PC := RW (22);
                  CPU.I := D (B + 24); CPU.R := D (B + 25);
                  CPU.IFF1 := D (B + 26) /= 0;
                  CPU.IFF2 := D (B + 27) /= 0;
                  CPU.IM := Natural (D (B + 28)) mod 3;
                  CPU.MEMPTR := RW (35);
               end;
            elsif Id = "SCLD" and then Size >= 2 then
               ULA.SCLD := D (B + 1);         --  chHsr (&F4), chDec (&FF)
            elsif Id = "SPCR" and then Size >= 4 then
               Border := Natural (D (B) and 7);
               P7 := D (B + 1);
               P1 := D (B + 2);
            elsif Id = "AY" & ASCII.NUL & ASCII.NUL and then Size >= 18 then
               for K in 0 .. 15 loop
                  AY.Select_Register (Byte (K));
                  AY.Write (D (B + 2 + K));
               end loop;
               AY.Select_Register (D (B + 1));
            elsif Id = "RAMP" and then Size >= 3 then
               declare
                  Flags : constant Natural := Natural (D (B));
                  Page : constant Natural := Natural (D (B + 2));
                  Block : Byte_Array (0 .. 16#3FFF#) := (others => 0);
               begin
                  if Flags mod 2 = 1 then
                     declare
                        Len : aliased Interfaces.C.unsigned_long :=
                          Block'Length;
                     begin
                        if Z_Uncompress
                          (Block'Address, Len'Access, D (B + 3)'Address,
                           Interfaces.C.unsigned_long (Size - 3)) /= 0
                        then
                           Ok := False;
                           Err := To_Unbounded_String
                             ("damaged memory page in the .szx snapshot");
                           return;
                        end if;
                     end;
                  else
                     Block (0 .. Natural'Min (16#4000#, Size - 3) - 1) :=
                       D (B + 3 .. B + 2 + Natural'Min (16#4000#, Size - 3));
                  end if;
                  if Page <= 7 then
                     Set_Bank (Page, Block);
                  end if;
               end;
            end if;
            P := B + Size;
         end;
      end loop;
      if Config.Is_128 then
         Memory.Paging_Locked := False;
         if Config.Is_Plus3_Type then
            Memory.Write_1FFD (P1);
         end if;
         Memory.Write_7FFD (P7);
      end if;
      After_Load (Border);
   end Load_SZX;

   function Save_SZX return Byte_Array is
      Out_Buf : Byte_Array (0 .. 8 * 16#4100# + 512);
      N : Natural := 0;
      procedure Put (B : Byte) is
      begin
         Out_Buf (N) := B;
         N := N + 1;
      end Put;
      procedure Put_W (V : Word) is
      begin
         Put (Lo (V));
         Put (Hi (V));
      end Put_W;
      procedure Put_Tag (S : String; Size : Natural) is
      begin
         for C of S loop
            Put (Character'Pos (C));
         end loop;
         Put (Byte (Size mod 256));
         Put (Byte (Size / 256 mod 256));
         Put (Byte (Size / 65536 mod 256));
         Put (0);
      end Put_Tag;
      procedure Page (Bank : Natural) is
         Raw : Byte_Array (0 .. 16#3FFF#);
         Packed : Byte_Array (0 .. 16#4100#);
         Len : aliased Interfaces.C.unsigned_long := Packed'Length;
         use type Interfaces.C.int;
      begin
         for K in Raw'Range loop
            Raw (K) := Memory.Store (Memory.RAM_Base (Bank) + K);
         end loop;
         if Z_Compress (Packed'Address, Len'Access, Raw'Address,
                        Raw'Length) = 0
         then
            Put_Tag ("RAMP", Natural (Len) + 3);
            Put_W (1);
            Put (Byte (Bank));
            Out_Buf (N .. N + Natural (Len) - 1) :=
              Packed (0 .. Natural (Len) - 1);
            N := N + Natural (Len);
         else
            Put_Tag ("RAMP", 16#4003#);
            Put_W (0);
            Put (Byte (Bank));
            Out_Buf (N .. N + 16#3FFF#) := Raw;
            N := N + 16#4000#;
         end if;
      end Page;
   begin
      for C of String'("ZXST") loop
         Put (Character'Pos (C));
      end loop;
      Put (1);
      Put (4);
      Put ((case Model is
               when Config.ZX128 => 2, when Config.Plus2 => 3,
               when Config.Plus2A => 4, when Config.Plus3 => 5,
               when Config.Pentagon => 7, when Config.TC2048 => 8,
               when others => 1));
      Put (0);
      Put_Tag ("Z80R", 37);
      Put (CPU.F); Put (CPU.A); Put (CPU.C); Put (CPU.B);
      Put (CPU.E); Put (CPU.D); Put (CPU.L); Put (CPU.H);
      Put (CPU.F2); Put (CPU.A2); Put (CPU.C2); Put (CPU.B2);
      Put (CPU.E2); Put (CPU.D2); Put (CPU.L2); Put (CPU.H2);
      Put_W (CPU.IX); Put_W (CPU.IY); Put_W (CPU.SP); Put_W (CPU.PC);
      Put (CPU.I); Put (CPU.R);
      Put ((if CPU.IFF1 then 1 else 0));
      Put ((if CPU.IFF2 then 1 else 0));
      Put (Byte (CPU.IM));
      declare
         TS : constant Natural := Natural'Max (0, Tstates.T);
      begin
         Put (Byte (TS mod 256)); Put (Byte (TS / 256 mod 256));
         Put (Byte (TS / 65536 mod 256)); Put (0);
      end;
      Put (0);
      Put ((if CPU.After_EI then 1 else 0) or (if CPU.Halted then 2 else 0));
      Put_W (CPU.MEMPTR);
      Put_Tag ("SPCR", 8);
      Put (Byte (ULA.Border_Colour));
      Put (Memory.Port_7FFD);
      Put (Memory.Port_1FFD);
      Put (Last_FE);
      for K in 1 .. 4 loop
         Put (0);
      end loop;
      if Model = Config.TC2048 then
         Put_Tag ("SCLD", 2);
         Put (0);
         Put (ULA.SCLD);
      end if;
      if Config.Is_128 then
         Put_Tag ("AY" & ASCII.NUL & ASCII.NUL, 18);
         Put (0);
         Put (Byte (AY.Selected));
         for K in 0 .. 15 loop
            Put (AY.Regs (K));
         end loop;
         for Bank in 0 .. 7 loop
            Page (Bank);
         end loop;
      else
         Page (5);
         Page (2);
         Page (0);
      end if;
      return Out_Buf (0 .. N - 1);
   end Save_SZX;

   ---------------------------------------------------------------------

   procedure Load_Data (Kind : String; D : Byte_Array; Ok : out Boolean) is
   begin
      if Kind = "sna" then
         Load_SNA (D, Ok);
      elsif Kind = "z80" then
         Load_Z80 (D, Ok);
      elsif Kind = "szx" then
         Load_SZX (D, Ok);
      elsif Kind = "azx" then
         Load_AZX (D, Ok);
      else
         Ok := False;
         Err := To_Unbounded_String ("unknown snapshot type " & Kind);
      end if;
   exception
      when others =>
         Ok := False;
         Err := To_Unbounded_String ("damaged ." & Kind & " snapshot");
   end Load_Data;

   procedure Peek_Model_Data (Kind : String; D : Byte_Array;
                              M : out Model_Type; Ok : out Boolean) is
   begin
      Ok := True;
      M := Config.ZX48;
      if Kind = "sna" then
         M := (if D'Length = 49179 then Config.ZX48 else Config.ZX128);
      elsif Kind = "z80" then
         M := Z80_Model (D);
      elsif Kind = "szx" then
         Ok := D'Length > 8 and then Tag (D, D'First) = "ZXST";
         if Ok then
            M := SZX_Model (D (D'First + 6));
         end if;
      elsif Kind = "azx" then
         Ok := D'Length > 5 and then D (D'First .. D'First + 3)
           = (65, 90, 88, 49);
         if Ok then
            M := Model_Type'Val (Natural (D (D'First + 4)));
         end if;
      else
         Ok := False;
      end if;
      if not Ok then
         Err := To_Unbounded_String ("not a ." & Kind & " snapshot");
      end if;
   exception
      when others =>
         Ok := False;
         Err := To_Unbounded_String ("damaged ." & Kind & " snapshot");
   end Peek_Model_Data;

   function SZX_Data return Byte_Array is (Save_SZX);

   procedure Load (Path : String; Ok : out Boolean) is
   begin
      Load_Data (Ext (Path), Read_File (Path), Ok);
   exception
      when others =>
         Ok := False;
         Err := To_Unbounded_String ("cannot load " & Path);
   end Load;

   procedure Save (Path : String; Ok : out Boolean) is
      E : constant String := Ext (Path);
   begin
      Ok := True;
      if E = "sna" and then Model in Config.ZX48 .. Config.Plus2 then
         Write_File (Path, Save_SNA);
      elsif E = "z80" and then not Config.Is_ZX81 then
         Write_File (Path, Save_Z80);
      elsif E = "szx" and then not Config.Is_ZX81 then
         Write_File (Path, Save_SZX);
      elsif E = "azx" then
         Write_File (Path, Save_AZX);
      else
         Ok := False;
         Err := To_Unbounded_String
           ("snapshots of this machine are saved as ."
            & (if Config.Is_ZX81 then "azx"
               else "z80, .szx, .sna or .azx"));
      end if;
   exception
      when others =>
         Ok := False;
         Err := To_Unbounded_String ("cannot write " & Path);
   end Save;

end Machine.Snapshots;
