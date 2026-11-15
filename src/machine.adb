-- ***************************************************************************
--                              AdaZX - Machine
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
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Streams.Stream_IO;
with Ada.Directories;
with Ada.Characters.Handling;
with Interfaces; use Interfaces;

with Config; use Config;
with Tstates; use Tstates;
with Memory;
with ULA;
with Video;
with Sound;
with AY;
with Keyboard;
use type Keyboard.Joy_Type;
with Tape;
with DSK;
with Interface_1;
with FDC765;
with Disasm;
with Typist;
with Basic;
with Basic_ZX80;
with Asm;
with Machine.Snapshots;
with Machine.Replay;
with P_Files;

package body Machine is

   package SIO renames Ada.Streams.Stream_IO;

   Err : Unbounded_String;
   ROM_Dir_Used : Unbounded_String;
   Frames : Natural := 0;
   Total_Cycles : Long_Long_Integer := 0;
   Powered : Boolean := False;

   ---------------------------------------------------------------------
   --  Debugger state
   ---------------------------------------------------------------------

   BP_Map : array (Word) of Boolean := (others => False);
   Max_BP : constant := 64;
   Breakpoints : array (1 .. Max_BP) of Word;
   BP_Count : Natural := 0;

   type Watch is record
      From, To : Word;
      On_Read, On_Write : Boolean;
   end record;
   Watches : array (1 .. 32) of Watch;
   Watch_Count : Natural := 0;
   Watch_Hit, Watch_Write_Hit : Boolean := False;
   Watch_Addr : Word := 0;

   Break_Flag : Boolean := False;
   Skip_Break : Boolean := False;
   Reason : Stop_Reason := None;
   Temp_Addr : Integer := -1;
   Temp_SP : Word := 0;
   Out_Active : Boolean := False;
   Out_SP : Word := 0;
   Pause_Req : Boolean := False;

   Basic_BPs : array (1 .. 64) of Natural;
   Basic_BP_Count : Natural := 0;
   Basic_Stepping : Boolean := False;
   Basic_Stopped : Integer := -1;
   Basic_Last_Line : Integer := -1;

   function Debugging return Boolean is
     (BP_Count > 0 or else Watch_Count > 0 or else Temp_Addr >= 0
      or else Out_Active or else Pause_Req or else Basic_BP_Count > 0
      or else Basic_Stepping);

   procedure Stop (R : Stop_Reason) is
   begin
      Break_Flag := True;
      Reason := R;
      Temp_Addr := -1;
      Out_Active := False;
      Pause_Req := False;
      Basic_Stepping := False;
   end Stop;

   procedure Check_Watch (Addr : Word; Is_Write : Boolean) is
   begin
      for I in 1 .. Watch_Count loop
         declare
            W : Watch renames Watches (I);
         begin
            if Addr >= W.From and then Addr <= W.To
              and then ((Is_Write and then W.On_Write)
                        or else (not Is_Write and then W.On_Read))
            then
               Watch_Hit := True;
               Watch_Write_Hit := Is_Write;
               Watch_Addr := Addr;
            end if;
         end;
      end loop;
   end Check_Watch;

   ---------------------------------------------------------------------
   --  ZX81 display
   ---------------------------------------------------------------------

   ZX81_Line_T : constant := 207;
   ZX81_Frame_T : constant := 207 * 312;
   Lines_Since_VSync : Natural := 0;
   VSync_Start_T : Integer := 0;
   Skip_Count : Boolean := False;
   --  LINECNTR stays 0 until the second HSYNC after the end of VSYNC
   --  (the ROM's dummy line after the top margin then has LINECNTR 7,
   --  so the first character row starts with 0).  A VSYNC pulse too
   --  short for the television (the per-scanline IN / OUT of pseudo
   --  hi-res displays) does not start a frame.
   Min_VSync_T : constant := 200;
   HSync_Phase_T : constant := 33;
   --  the HSYNC pulse (and the NMI) comes this long after the start of
   --  the line as the interrupt acknowledge sets it; displays timed from
   --  the NMI (pseudo hi-res) are positioned by it
   Line_Start_T : Integer := 0;
   ZX81_Top : constant := 56 - Video.Border + 1;
   --  scanlines after the end of VSYNC before the framebuffer's top row
   ZX81_Left : constant := 98;    --  pixels from HSYNC to the left edge

   function FB_Row return Integer is (Lines_Since_VSync - ZX81_Top);

   procedure Clear_Row (Y : Integer) is
   begin
      if Y in 0 .. Video.Height - 1 then
         for X in 0 .. Video.Width - 1 loop
            Video.FB (Y, X) := Video.ZX81_Paper;
         end loop;
      end if;
   end Clear_Row;

   procedure HSync (At_T : Integer) is
   begin
      Line_Start_T := At_T - HSync_Phase_T;
      if not VSync and then not Skip_Count then
         Line_Counter := (Line_Counter + 1) mod 8;
      end if;
      Skip_Count := False;
      Lines_Since_VSync := Lines_Since_VSync + 1;
      if Lines_Since_VSync > 400 then
         --  no VSYNC (FAST mode): the television shows no picture
         Lines_Since_VSync := 0;
      end if;
      Clear_Row (FB_Row);
      if NMI_Gen then
         CPU.NMI_Pending := True;
      end if;
   end HSync;

   procedure Draw_ZX81_Char (Code : Byte; M1_T : Integer) is
      Y : constant Integer := FB_Row;
      X0 : constant Integer := 2 * (M1_T - Line_Start_T) - ZX81_Left;
      Pattern : Byte;
      IReg : constant Word := Word (CPU.I);
   begin
      if Y not in 0 .. Video.Height - 1 then
         return;
      end if;
      if IReg >= 16#40# then
         --  WRX hi-res: the RAM answers the refresh address itself
         Pattern := Memory.Read
           (Shift_Left (IReg, 8) or Word ((CPU.R - 1) and 16#7F#)
            or Word (CPU.R and 16#80#));
      else
         Pattern := Memory.Read
           ((Shift_Left (IReg, 8) and 16#FE00#)
            or Shift_Left (Word (Code and 16#3F#), 3)
            or Word (Line_Counter));
      end if;
      if (Code and 16#80#) /= 0 then
         Pattern := not Pattern;
      end if;
      for K in 0 .. 7 loop
         declare
            X : constant Integer := X0 + K;
         begin
            if X in 0 .. Video.Width - 1 then
               Video.FB (Y, X) :=
                 (if (Pattern and Shift_Right (Byte'(16#80#), K)) /= 0
                  then Video.ZX81_Ink else Video.ZX81_Paper);
            end if;
         end;
      end loop;
   end Draw_ZX81_Char;

   ---------------------------------------------------------------------
   --  Bus
   ---------------------------------------------------------------------

   function Bus_Read (Addr : Word) return Byte is
   begin
      if Watch_Count > 0 then
         Check_Watch (Addr, False);
      end if;
      return Memory.Read (Addr);
   end Bus_Read;

   procedure Bus_Write (Addr : Word; Value : Byte) is
   begin
      if Watch_Count > 0 then
         Check_Watch (Addr, True);
      end if;
      if not Config.Is_ZX81 and then ULA.Is_Screen_Address (Addr) then
         ULA.Render_To (T);
      end if;
      Memory.Write (Addr, Value);
   end Bus_Write;

   Last_M1_End : Integer := -1;   --  T-state at the end of the last M1
   RZX_Fetches : Natural := 0;    --  opcode fetches in this frame (RZX)
   RZX_On : Boolean := False;     --  playing or recording

   function Fetch_Byte (Addr : Word) return Byte;

   function Bus_Fetch (Addr : Word) return Byte is
   begin
      --  Interface 1: shadow ROM in at &0008 / &1708, out after &0700
      if Interface_1.Enabled and then Model in Config.ZX48 .. Config.Plus2
      then
         if not Interface_1.Paged and then (Addr = 16#0008# or else
                                            Addr = 16#1708#)
           and then Memory.Current_ROM = Memory.Basic48_ROM
         then
            Interface_1.Paged := True;
         elsif Interface_1.Paged and then Addr = 16#0700# then
            declare
               V : constant Byte := Memory.Read (Addr);
            begin
               Interface_1.Paged := False;
               Last_M1_End := T;
               if RZX_On then
                  RZX_Fetches := RZX_Fetches + 1;
               end if;
               return V;
            end;
         end if;
      end if;
      return Fetch_Byte (Addr);
   end Bus_Fetch;

   function Fetch_Byte (Addr : Word) return Byte is
      V : constant Byte := Memory.Read (Addr);
   begin
      Last_M1_End := T;
      if RZX_On then
         RZX_Fetches := RZX_Fetches + 1;
      end if;
      if Config.Is_ZX81 and then (Addr and 16#8000#) /= 0
        and then (V and 16#40#) = 0 and then not CPU.Halted
      then
         Draw_ZX81_Char (V, T - 4);
         return 0;                  --  the ULA puts a NOP on the bus
      end if;
      return V;
   end Fetch_Byte;

   function Contend (Addr : Word) return Natural is
     (if Memory.Contended (Addr) and then not Config.Is_ZX81
      then ULA.Delay_At (T) else 0);

   function Contend_No_MREQ (Addr : Word) return Natural is
     (if Model in Config.ZX48 .. Config.Plus2 and then Memory.Contended (Addr)
      then ULA.Delay_At (T) else 0);

   --  I/O cycle timing of the 48K / 128K (Fuse's model); the +2A / +3
   --  have no I/O contention.
   procedure IO_Pre (Port : Word) is
   begin
      if Model in Config.ZX48 .. Config.Plus2 and then Memory.Contended (Port)
      then
         T := T + ULA.Delay_At (T);
      end if;
      T := T + 1;
   end IO_Pre;

   procedure IO_Post (Port : Word) is
      Contended_IO : constant Boolean := Model in Config.ZX48 .. Config.Plus2;
   begin
      if not Contended_IO then
         T := T + 3;
      elsif (Port and 1) /= 0 then
         if Memory.Contended (Port) then
            for K in 1 .. 3 loop
               T := T + ULA.Delay_At (T) + 1;
            end loop;
         else
            T := T + 3;
         end if;
      else
         T := T + ULA.Delay_At (T) + 3;
      end if;
   end IO_Post;

   function Ear_Bit return Byte is
   begin
      if Tape.Playing then
         return (if Tape.Ear (T) then 16#40# else 0);
      elsif Model = Config.ZX48 and then Issue_2 then
         return (if (Last_FE and 16#18#) /= 0 then 16#40# else 0);
      else
         return (if (Last_FE and 16#10#) /= 0 then 16#40# else 0);
      end if;
   end Ear_Bit;

   function Port_In (Port : Word) return Byte is
      V : Byte := 16#FF#;
   begin
      if Config.Is_ZX81 then
         T := T + 4;
         if (Port and 1) = 0 then
            V := Keyboard.Read_Rows (Hi (Port)) or 16#40#;   --  50 Hz
            if not NMI_Gen then
               if not VSync then
                  VSync_Start_T := T;
               end if;
               VSync := True;          --  start of vertical sync
               Line_Counter := 0;
            end if;
         end if;
         return V;
      end if;
      IO_Pre (Port);
      if Interface_1.Port_Selected (Port)
        and then Model in Config.ZX48 .. Config.Plus2
      then
         V := Interface_1.Port_In (Port);
      elsif (Port and 1) = 0 then
         V := Keyboard.Read_Rows (Hi (Port)) or 16#A0# or Ear_Bit;
      elsif (Port and 16#E0#) = 0
        and then Keyboard.Joystick = Keyboard.Kempston
      then
         V := Keyboard.Kempston_Bits;
      elsif Is_128 and then (Port and 16#C002#) = 16#C000# then
         V := AY.Read;
      elsif Model = Config.Plus3 and then (Port and 16#F002#) = 16#2000# then
         V := FDC765.Read_Status;
      elsif Model = Config.Plus3 and then (Port and 16#F002#) = 16#3000# then
         V := FDC765.Read_Data;
      else
         V := ULA.Floating_Bus (T);
      end if;
      if RZX_On then
         if Replay.Playing then
            V := Replay.Next_In;
         else
            Replay.Record_In (V);
         end if;
      end if;
      IO_Post (Port);
      return V;
   end Port_In;

   procedure Port_Out (Port : Word; Value : Byte) is
   begin
      if Config.Is_ZX81 then
         T := T + 4;
         if VSync then
            VSync := False;             --  end of vertical sync
            if T - VSync_Start_T >= Min_VSync_T then
               Lines_Since_VSync := 0;
            end if;
            Skip_Count := True;
         end if;
         case Lo (Port) is
            when 16#FD# => NMI_Gen := False;
            when 16#FE# => NMI_Gen := True;
            when others => null;
         end case;
         return;
      end if;
      IO_Pre (Port);
      if Interface_1.Port_Selected (Port)
        and then Model in Config.ZX48 .. Config.Plus2
      then
         Interface_1.Port_Out (Port, Value);
      end if;
      if (Port and 1) = 0 then
         ULA.Set_Border (Natural (Value and 7), T);
         Sound.Set_Beeper
           ((if (Value and 16#10#) /= 0 then 0.75 else 0.0)
            + (if (Value and 16#08#) /= 0 then 0.1 else 0.0), T);
         Last_FE := Value;
      end if;
      if Is_128 then
         if (Port and 16#8002#) = 0
           and then (not Is_Plus3_Type or else (Port and 16#4000#) /= 0)
         then
            if ((Value xor Memory.Port_7FFD) and 8) /= 0 then
               ULA.Render_To (T);
            end if;
            Memory.Write_7FFD (Value);
         elsif Is_Plus3_Type and then (Port and 16#F002#) = 16#1000# then
            Memory.Write_1FFD (Value);
            FDC765.Motor := (Value and 8) /= 0;
         elsif Model = Config.Plus3 and then (Port and 16#F002#) = 16#3000#
         then
            FDC765.Write_Data (Value);
         elsif (Port and 16#C002#) = 16#C000# then
            AY.Select_Register (Value);
         elsif (Port and 16#C002#) = 16#8000# then
            Sound.Update (T);
            AY.Write (Value);
         end if;
      end if;
      IO_Post (Port);
   end Port_Out;

   function Int_Data return Byte is (16#FF#);

   procedure Tape_Edge (Level : Boolean; At_T : Integer) is
   begin
      Sound.Set_Tape (Level, At_T);
   end Tape_Edge;

   ---------------------------------------------------------------------
   --  ROMs and reset
   ---------------------------------------------------------------------

   function Find_ROM (Name : String) return String is
      Dirs : constant array (1 .. 4) of Unbounded_String :=
        (ROM_Dir_Used, To_Unbounded_String ("roms"),
         To_Unbounded_String ("/usr/share/spectrum-roms"),
         To_Unbounded_String ("/usr/share/fuse"));
   begin
      for D of Dirs loop
         declare
            P : constant String := To_String (D) & "/" & Name;
         begin
            if Length (D) > 0 and then Ada.Directories.Exists (P) then
               return P;
            end if;
         end;
      end loop;
      return "";
   end Find_ROM;

   procedure Load_ROM (Name : String; Index : Natural; Size : Natural;
                       Ok : in out Boolean) is
      Path : constant String := Find_ROM (Name);
      F : SIO.File_Type;
   begin
      if Path = "" then
         Ok := False;
         Append (Err, "missing ROM " & Name & ASCII.LF);
         return;
      end if;
      SIO.Open (F, SIO.In_File, Path);
      declare
         D : Byte_Array (0 .. Size - 1);
      begin
         Byte_Array'Read (SIO.Stream (F), D);
         for K in 0 .. Memory.Bank_Size - 1 loop
            Memory.Store (Memory.ROM_Base (Index) + K) := D (K mod Size);
         end loop;
      end;
      SIO.Close (F);
   exception
      when others =>
         Ok := False;
         Append (Err, "cannot read " & Path & ASCII.LF);
   end Load_ROM;

   procedure Restart_Frame_State is
   begin
      ULA.Configure;
      Sound.Reset;
      Next_HSync := T + ZX81_Line_T;
   end Restart_Frame_State;

   procedure Reset is
   begin
      if Replay.Playing then
         Replay.Stop_Playing;
      end if;
      RZX_On := Replay.Recording;
      Memory.Clear_RAM;
      Memory.ZX81_RAM_Size := (if ZX81_16K then 16#4000# else 16#400#);
      Memory.ZX81_RAM_2000 := ZX81_RAM_2000;
      Memory.Reset_Paging;
      CPU.Reset;
      T := 0;
      AY.Reset;
      FDC765.Reset;
      Interface_1.Reset;
      FDC765.Motor := False;
      Restart_Frame_State;
      Last_FE := 0;
      ULA.Border_Colour := 7;
      NMI_Gen := False;
      VSync := False;
      Line_Counter := 0;
      Lines_Since_VSync := 0;
      Keyboard.Clear_Typing;
      Keyboard.Release_All;
      Break_Flag := False;
      if Config.Is_ZX81 then
         for Y in 0 .. Video.Height - 1 loop
            Clear_Row (Y);
         end loop;
      end if;
   end Reset;

   procedure NMI_Button is
   begin
      CPU.NMI_Pending := True;
   end NMI_Button;

   procedure Power_On (M : Model_Type; ROM_Dir : String; Ok : out Boolean) is
   begin
      Err := Null_Unbounded_String;
      ROM_Dir_Used := To_Unbounded_String (ROM_Dir);
      Config.Model := M;
      Ok := True;
      Memory.Store (Memory.ROM_Base (0) .. Memory.Store'Last) :=
        (others => 16#FF#);
      case M is
         when Config.ZX48 => Load_ROM ("48.rom", 0, 16#4000#, Ok);
         when Config.ZX128 =>
            Load_ROM ("128-0.rom", 0, 16#4000#, Ok);
            Load_ROM ("128-1.rom", 1, 16#4000#, Ok);
         when Config.Plus2 =>
            Load_ROM ("plus2-0.rom", 0, 16#4000#, Ok);
            Load_ROM ("plus2-1.rom", 1, 16#4000#, Ok);
         when Config.Plus2A | Config.Plus3 =>
            for K in 0 .. 3 loop
               Load_ROM ("plus3-" & Character'Val (48 + K) & ".rom", K,
                         16#4000#, Ok);
            end loop;
         when Config.ZX81 => Load_ROM ("zx81.rom", 0, 16#2000#, Ok);
         when Config.ZX80 => Load_ROM ("zx80.rom", 0, 16#1000#, Ok);
      end case;
      if Interface_1.Enabled and then not Interface_1.ROM_Loaded then
         declare
            P : constant String := Find_ROM ("if1-2.rom");
            Ok2 : Boolean := False;
         begin
            if P /= "" then
               Interface_1.Load_ROM (P, Ok2);
            end if;
            if not Ok2 then
               Append (Err, "missing ROM if1-2.rom (Interface 1)" & ASCII.LF);
               Interface_1.Enabled := False;
            end if;
         end;
      end if;
      Tape.On_Edge := Tape_Edge'Access;
      Powered := True;
      Reset;
   end Power_On;

   function Model return Model_Type is (Config.Model);
   function Is_ZX81 return Boolean is (Config.Is_ZX81);
   function Is_ZX80 return Boolean is (Config.Is_ZX80);
   function Error_Message return String is (To_String (Err));
   function Frame_Count return Natural is (Frames);
   function Frame_Rate return Float is
     (if Config.Is_ZX81 then 3_250_000.0 / Float (ZX81_Frame_T)
      else Float (CPU_Clock) / Float (ULA.Frame_T));
   function Get_PC return Word is (CPU.PC);
   function Cycle_Count return Long_Long_Integer is
     (Total_Cycles + Long_Long_Integer (T));

   function Peek (Addr : Word) return Byte is (Memory.Read (Addr));
   procedure Poke (Addr : Word; Value : Byte) is
   begin
      Memory.Write (Addr, Value);
   end Poke;
   function Peek_Word (Addr : Word) return Word is
     (Make_Word (Peek (Addr), Peek (Addr + 1)));
   function Bank_Peek (Bank : Natural; Offset : Natural) return Byte is
     (Memory.Store (Memory.RAM_Base (Bank mod 8) + Offset mod 16#4000#));
   procedure Bank_Poke (Bank : Natural; Offset : Natural; Value : Byte) is
   begin
      Memory.Store (Memory.RAM_Base (Bank mod 8) + Offset mod 16#4000#) :=
        Value;
   end Bank_Poke;
   function Screen_Bank return Natural is (Memory.Screen_Bank);
   function Border_Colour return Natural is (ULA.Border_Colour);

   ---------------------------------------------------------------------
   --  Screen text
   ---------------------------------------------------------------------

   function ZX81_Char (C : Byte) return Character is
      Table : constant String :=
        " ##########""`$:?()><=+-*/;,.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
   begin
      return Table (Natural (C and 16#3F#) + 1);
   end ZX81_Char;

   function Screen_Text return String is
      R : Unbounded_String;
   begin
      if Config.Is_ZX81 then
         declare
            A : Word := Peek_Word (16#400C#) + 1;    --  D_FILE
            Line : Unbounded_String;
         begin
            for Row in 0 .. 23 loop
               Line := Null_Unbounded_String;
               for Col in 0 .. 32 loop
                  declare
                     C : constant Byte := Peek (A);
                  begin
                     A := A + 1;
                     exit when C = 16#76#;
                     Append (Line, (if Config.Is_ZX80
                                    then Basic_ZX80.From_Code (C)
                                    else ZX81_Char (C)));
                  end;
               end loop;
               Append (R, To_String (Line) & ASCII.LF);
            end loop;
         end;
         return To_String (R);
      end if;
      declare
         Font : constant Natural :=
           Memory.ROM_Base (Memory.Basic48_ROM) + 16#3D00#;
      begin
         for Row in 0 .. 23 loop
            declare
               Line : String (1 .. 32) := (others => ' ');
               Last : Natural := 0;
            begin
               for Col in 0 .. 31 loop
                  declare
                     Cell : array (0 .. 7) of Byte;
                     Found : Character := '?';
                     Blank : Boolean := True;
                  begin
                     for K in 0 .. 7 loop
                        Cell (K) := Memory.Screen_Byte
                          ((Row / 8) * 2048 + K * 256 + (Row mod 8) * 32
                           + Col);
                        Blank := Blank and then
                          (Cell (K) = 0 or else Cell (K) = 16#FF#)
                          and then Cell (K) = Cell (0);
                     end loop;
                     if Blank then
                        Found := ' ';
                     else
                        for Ch in 33 .. 127 loop
                           declare
                              Match, Inverse : Boolean := True;
                           begin
                              for K in 0 .. 7 loop
                                 declare
                                    F : constant Byte := Memory.Store
                                      (Font + (Ch - 32) * 8 + K);
                                 begin
                                    Match := Match and then Cell (K) = F;
                                    Inverse := Inverse
                                      and then Cell (K) = not F;
                                 end;
                              end loop;
                              if Match or else Inverse then
                                 Found := Character'Val (Ch);
                                 exit;
                              end if;
                           end;
                        end loop;
                     end if;
                     Line (Col + 1) := Found;
                     if Found /= ' ' then
                        Last := Col + 1;
                     end if;
                  end;
               end loop;
               Append (R, Line (1 .. Last) & ASCII.LF);
            end;
         end loop;
      end;
      return To_String (R);
   end Screen_Text;

   function Screen_Contains (Text : String) return Boolean is
      S : constant String := Screen_Text;
   begin
      for I in S'First .. S'Last - Text'Length + 1 loop
         if S (I .. I + Text'Length - 1) = Text then
            return True;
         end if;
      end loop;
      return False;
   end Screen_Contains;

   ---------------------------------------------------------------------
   --  Prompt detection: the ROM's editor waits for a key
   ---------------------------------------------------------------------

   Prompt_Frames : Natural := 0;   --  frames in a row spent waiting

   Plus3_Wait_From : constant Word := 16#1872#;   --  +3 editor key wait
   Plus3_Wait_To   : constant Word := 16#1878#;

   ZX80_Wait_From : constant Word := 16#013C#;   --  ZX80 key wait loop
   ZX80_Wait_To   : constant Word := 16#01B5#;

   function In_Key_Wait return Boolean is
      PC : constant Word := CPU.PC;
      ROM : constant Natural := Memory.Current_ROM;
   begin
      case Model is
         when Config.ZX81 =>
            --  waiting in the editor (keyboard loop in the display
            --  routine, SLOW mode)
            return PC in 16#04CA# .. 16#04D2#;     --  waiting for a key
         when Config.ZX80 =>
            return PC in ZX80_Wait_From .. ZX80_Wait_To;
         when others =>
            --  48 BASIC editor key wait (WAIT-KEY / KEY-INPUT loop)
            if ROM = Memory.Basic48_ROM then
               return PC in 16#10A8# .. 16#111C# | 16#15D4# .. 16#15F6#
                 | 16#0F38# .. 16#0F80#;
            elsif ROM = 0 and then Model = Config.ZX128 then
               return PC in 16#3680# .. 16#3686#;    --  128 editor key wait
            elsif ROM = 0 and then Model = Config.Plus2 then
               return PC in 16#36A6# .. 16#36AC#;
            elsif ROM = 0 then
               return PC in Plus3_Wait_From .. Plus3_Wait_To;
            end if;
            return False;
      end case;
   end In_Key_Wait;

   Wait_Seen : Boolean := False;

   function At_Prompt return Boolean is
     (Prompt_Frames >= 3);

   ---------------------------------------------------------------------
   --  Typing and autostart
   ---------------------------------------------------------------------

   procedure Type_Text (S : String) is
   begin
      Typist.Type_Text (S);
   end Type_Text;

   function Typing_Busy return Boolean is (Keyboard.Typing_Busy);

   type Auto_Stage is (Idle, Wait_Prompt, Typing_Load, Wait_Loaded,
                       Wait_Inject);
   Stage : Auto_Stage := Idle;
   Menu_Frame : Integer := -1;      --  when the 128K menu choice was made
   Stage_Frames : Natural := 0;
   Auto_Run_After_Load : Boolean := False;

   Inject_Data : Byte_Array_Access := null;
   Inject_Load : Word := 0;
   Inject_Cmd : Unbounded_String;
   Inject_Basic : Boolean := False;
   Inject_Start : Integer := -1;

   function Autostart_Busy return Boolean is (Stage /= Idle);

   procedure Do_Inject is
   begin
      if Inject_Data = null then
         return;
      end if;
      if Inject_Basic then
         Typist.Install_Program (Inject_Data.all);
         if Config.Is_ZX81 then
            Keyboard.Type_Pause (60);
         end if;
      else
         for K in Inject_Data'Range loop
            Memory.Poke_Any (Inject_Load + Word (K - Inject_Data'First),
                             Inject_Data (K));
         end loop;
      end if;
      if Length (Inject_Cmd) > 0 then
         Type_Text (To_String (Inject_Cmd));
      elsif Inject_Start >= 0 then
         CPU.PC := Word (Inject_Start);
      end if;
   end Do_Inject;

   procedure Autostart_Step is
   begin
      if Stage = Idle then
         return;
      end if;
      Stage_Frames := Stage_Frames + 1;
      case Stage is
         when Idle => null;
         when Wait_Prompt =>
            if Is_128 then
               --  the 128K menu: its first entry loads from tape (on the
               --  +3 from the disc in drive A, else from tape)
               if (Stage_Frames mod 10 = 0 and then Screen_Contains ("BASIC"))
                 or else Stage_Frames > 300
               then
                  Keyboard.Type_Combo ((Key => Keyboard.K_Enter,
                                        others => False));
                  Stage := Wait_Loaded;
                  Stage_Frames := 0;
               end if;
            elsif At_Prompt or else Stage_Frames > 400 then
               Typist.Type_Load;
               Stage := Wait_Loaded;
               Stage_Frames := 0;
            end if;
         when Typing_Load => null;
         when Wait_Loaded =>
            if Config.Is_ZX81 and then Auto_Run_After_Load
              and then not Keyboard.Typing_Busy
              and then Stage_Frames > 50 and then At_Prompt
            then
               --  loaded without starting itself
               Type_Text ("RUN" & ASCII.LF);
               Stage := Idle;
            elsif Stage_Frames > 50 * 60 or else
              (not Config.Is_ZX81 and then not Tape.Playing
               and then Stage_Frames > 100)
              or else (Config.Is_ZX81 and then Stage_Frames > 300)
            then
               Stage := Idle;
            end if;
         when Wait_Inject =>
            if Is_128 and then not Memory.Special_Paging then
               --  choose "128 BASIC" (+3 BASIC) from the menu
               if Menu_Frame < 0 and then Stage_Frames mod 10 = 0
                 and then Screen_Contains ("BASIC")
               then
                  Keyboard.Type_Combo ((Key => Keyboard.Digit ('6'),
                                        Caps => True, Sym => False));
                  Keyboard.Type_Combo ((Key => Keyboard.K_Enter,
                                        others => False));
                  Menu_Frame := Stage_Frames;
               elsif Menu_Frame >= 0 and then Stage_Frames > Menu_Frame + 40
                 and then At_Prompt
               then
                  Do_Inject;
                  Stage := Idle;
               end if;
            elsif At_Prompt then
               Do_Inject;
               Stage := Idle;
            end if;
            if Stage_Frames > 600 then
               Do_Inject;
               Stage := Idle;
            end if;
      end case;
   end Autostart_Step;

   procedure Inject_And_Run (Data : Byte_Array; Load : Word;
                             Command : String; With_Reset : Boolean := True;
                             Is_Basic : Boolean := False;
                             Start : Integer := -1) is
   begin
      Inject_Data := new Byte_Array'(Data);
      Inject_Load := Load;
      Inject_Cmd := To_Unbounded_String (Command);
      Inject_Basic := Is_Basic;
      Inject_Start := Start;
      if With_Reset then
         Reset;
         Prompt_Frames := 0;
         Menu_Frame := -1;
         Stage := Wait_Inject;
         Stage_Frames := 0;
      else
         Do_Inject;
      end if;
   end Inject_And_Run;

   --  A BASIC or assembler source: tokenise / assemble, reset and run
   procedure Start_Source (Path : String; Ok : out Boolean) is
   begin
      if Basic.Is_Source (Path) then
         Basic.Tokenize_File
           (Path, (if Config.Is_ZX80 then Basic.ZX80
                   elsif Config.Is_ZX81 then Basic.ZX81 else Basic.Spectrum));
         Ok := Basic.Error_Count = 0;
         if not Ok then
            Err := To_Unbounded_String
              ("line" & Basic.Error_Line (1)'Image & ": " &
               Basic.Error_Text (1));
            return;
         end if;
         Inject_And_Run (Basic.Program, 0, "RUN" & ASCII.LF,
                         Is_Basic => True);
      else
         Asm.Target := (if Config.Is_ZX80 then Asm.ZX80
                        elsif Config.Is_ZX81 then Asm.ZX81 else Asm.Spectrum);
         Asm.Assemble (Path);
         Ok := not Asm.Has_Errors and then Asm.Has_Output;
         if not Ok then
            Err := To_Unbounded_String
              (if Asm.Has_Errors
               then "line" & Asm.Error_Line (1)'Image & ": " & Asm.Error_Text (1)
               else "no code");
            return;
         end if;
         if Config.Is_ZX80 then
            if Asm.Low_Address /= 16#402B# then
               Ok := False;
               Err := To_Unbounded_String
                 ("ZX80 programs must start at 16427 ($402B)");
               return;
            end if;
            Inject_And_Run (Asm.ZX80_Program, 0, "RUN" & ASCII.LF,
                            Is_Basic => True);
         elsif Config.Is_ZX81 then
            if Asm.Low_Address /= 16#4082# then
               Ok := False;
               Err := To_Unbounded_String
                 ("ZX81 programs must start at 16514 ($4082)");
               return;
            end if;
            Inject_And_Run (Asm.ZX81_Program, 0, "RUN" & ASCII.LF,
                            Is_Basic => True);
         else
            Inject_And_Run
              (Asm.Code_Bytes, Asm.Low_Address,
               "RANDOMIZE USR" & Natural'Image (Natural (Asm.Start_Address))
               & ASCII.LF);
         end if;
      end if;
   end Start_Source;

   procedure Autostart (Path : String; Ok : out Boolean) is
      Ext : constant String := Ada.Characters.Handling.To_Lower
        (File_Ext.Of_Path (Path));
      Is_ZX80_File : constant Boolean := Ext = "o" or else Ext = "80";
      Is_ZX81_File : constant Boolean := Ext = "p" or else Ext = "81"
        or else Ext = "p81" or else Is_ZX80_File;
   begin
      Ok := True;
      if Ext in "z80" | "sna" | "azx" | "szx" | "rzx" then
         Load_Snapshot (Path, Ok);
         return;
      end if;
      if Basic.Is_Source (Path) or else Asm.Is_Source (Path) then
         Start_Source (Path, Ok);
         return;
      end if;
      if Ext = "mdr" then
         --  Interface 1: load "run" from Microdrive 1 (it starts itself
         --  when it was saved with LINE)
         if Model not in Config.ZX48 .. Config.Plus2
           or else not Interface_1.Enabled
         then
            Interface_1.Enabled := True;
            Power_On ((if Model in Config.ZX48 .. Config.Plus2 then Model
                       else Config.ZX48), To_String (ROM_Dir_Used), Ok);
            if not Ok then
               return;
            end if;
         end if;
         Insert_Microdrive (1, Path, Ok);
         if not Ok then
            return;
         end if;
         Reset;
         Inject_And_Run ((1 .. 0 => 0), 0,
                         "LOAD *""m"";1;""run""" & ASCII.LF);
         return;
      end if;
      if Ext = "dsk" then
         if Model /= Config.Plus3 then
            Power_On (Config.Plus3, To_String (ROM_Dir_Used), Ok);
            if not Ok then
               return;
            end if;
         end if;
         Insert_Disc (Path, Ok);
         if not Ok then
            return;
         end if;
         Reset;
         Prompt_Frames := 0;
         Stage := Wait_Prompt;
         Stage_Frames := 0;
         return;
      end if;
      if Is_ZX81_File /= Config.Is_ZX81
        or else (Is_ZX80_File and then not Config.Is_ZX80)
        or else (Is_ZX81_File and then not Is_ZX80_File and then Config.Is_ZX80)
      then
         Power_On ((if Is_ZX80_File then Config.ZX80
                    elsif Is_ZX81_File then Config.ZX81 else Config.ZX48),
                   To_String (ROM_Dir_Used), Ok);
         if not Ok then
            return;
         end if;
      end if;
      if Is_ZX81_File then
         P_Files.Insert (Path, Ok);
         if not Ok then
            Err := To_Unbounded_String ("cannot read " & Path);
            return;
         end if;
         Auto_Run_After_Load := True;
      elsif Ext = "scr" then
         declare
            F : SIO.File_Type;
            D : Byte_Array (0 .. 6911);
         begin
            SIO.Open (F, SIO.In_File, Path);
            Byte_Array'Read (SIO.Stream (F), D);
            SIO.Close (F);
            for K in D'Range loop
               Bank_Poke (Memory.Screen_Bank, K, D (K));
            end loop;
            return;
         exception
            when others =>
               Ok := False;
               Err := To_Unbounded_String ("not a 6912 byte screen file");
               return;
         end;
      else
         Tape.Insert (Path, Ok);
         if not Ok then
            Err := To_Unbounded_String (Tape.Error_Message);
            return;
         end if;
      end if;
      Reset;
      Prompt_Frames := 0;
      Stage := Wait_Prompt;
      Stage_Frames := 0;
   end Autostart;

   ---------------------------------------------------------------------
   --  Tape
   ---------------------------------------------------------------------

   procedure Attach_Tape (Path : String; Ok : out Boolean) is
      Ext : constant String := Ada.Characters.Handling.To_Lower
        (File_Ext.Of_Path (Path));
   begin
      if Ext in "p" | "81" | "p81" then
         P_Files.Insert (Path, Ok);
      else
         Tape.Insert (Path, Ok);
         if not Ok then
            Err := To_Unbounded_String (Tape.Error_Message);
         end if;
      end if;
   end Attach_Tape;

   procedure Eject_Tape is
   begin
      Tape.Eject;
      P_Files.Eject;
   end Eject_Tape;

   function Tape_Name return String is
     (if Config.Is_ZX81 then P_Files.Name else Tape.Name);
   procedure Tape_Rewind is
   begin
      Tape.Rewind;
   end Tape_Rewind;
   procedure Tape_Play is
   begin
      Tape.Play;
   end Tape_Play;
   procedure Tape_Stop is
   begin
      Tape.Stop;
   end Tape_Stop;
   function Tape_Motor return Boolean is (Tape.Playing);
   function Tape_Recorded return Natural is
     (if Config.Is_ZX81 then P_Files.Recorded
      else Tape.Recorded_Bytes);
   procedure Save_Tape_Recording (Path : String; Ok : out Boolean) is
   begin
      if Config.Is_ZX81 then
         P_Files.Save_Recording (Path, Ok);
      else
         Tape.Save_Recording (Path, Ok);
      end if;
   end Save_Tape_Recording;

   --  ROM traps for the tape routines (in the 48 BASIC ROM)
   procedure Spectrum_Traps is
      PC : constant Word := CPU.PC;
   begin
      if Memory.Current_ROM /= Memory.Basic48_ROM
        or else Memory.Special_Paging
        or else Interface_1.Paged       --  the shadow ROM is not BASIC's
      then
         return;
      end if;
      if PC = 16#0556# then                --  LD-BYTES
         if Tape.Loaded and then not Tape.Playing and then Auto_Play then
            Tape.Play;
         end if;
         if Flash_Load and then Tape.Loaded and then Tape.At_Standard_Block
         then
            declare
               Data : constant Byte_Array := Tape.Take_Block;
               Want_Flag : constant Byte := CPU.A;
               Load : constant Boolean := (CPU.F and 1) /= 0;
               Addr : Word := CPU.IX;
               Len : Natural := Natural (CPU.DE);
               Ok : Boolean := Data'Length >= 1
                 and then Data (Data'First) = Want_Flag;
               Parity : Byte := 0;
               I : Natural := Data'First + 1;
            begin
               for B of Data loop
                  Parity := Parity xor B;
               end loop;
               if Ok then
                  while Len > 0 and then I <= Data'Last - 1 loop
                     if Load then
                        Memory.Write (Addr, Data (I));
                     elsif Memory.Read (Addr) /= Data (I) then
                        Ok := False;
                     end if;
                     Addr := Addr + 1;
                     Len := Len - 1;
                     I := I + 1;
                  end loop;
                  Ok := Ok and then Len = 0 and then Parity = 0;
               end if;
               CPU.IX := Addr;
               CPU.D := Byte (Len / 256);
               CPU.E := Byte (Len mod 256);
               CPU.F := (if Ok then CPU.F or 1 else CPU.F and 16#FE#);
               --  return from LD-BYTES
               CPU.PC := Make_Word (Memory.Read (CPU.SP),
                                    Memory.Read (CPU.SP + 1));
               CPU.SP := CPU.SP + 2;
               if not Tape.At_Standard_Block and then Tape.Playing
                 and then Tape.Current_Block = 0
               then
                  Tape.Stop;
               end if;
            end;
         end if;
      elsif PC = 16#04C2# then             --  SA-BYTES
         declare
            Len : constant Natural := Natural (CPU.DE);
            Data : Byte_Array (0 .. Len + 1);
            Parity : Byte := CPU.A;
         begin
            Data (0) := CPU.A;
            for K in 1 .. Len loop
               Data (K) := Memory.Read (CPU.IX + Word (K - 1));
               Parity := Parity xor Data (K);
            end loop;
            Data (Len + 1) := Parity;
            Tape.Record_Block (Data);
            CPU.IX := CPU.IX + Word (Len mod 65536);
            CPU.D := 0;
            CPU.E := 0;
            CPU.F := CPU.F or 1;
            CPU.PC := Make_Word (Memory.Read (CPU.SP),
                                 Memory.Read (CPU.SP + 1));
            CPU.SP := CPU.SP + 2;
         end;
      end if;
   end Spectrum_Traps;

   procedure ZX81_Traps is
      PC : constant Word := CPU.PC;
   begin
      if Config.Is_ZX80 then
         --  ZX80: LOAD at &0206, SAVE at &01B6 (memory &4000 .. E_LINE)
         if PC = 16#0206# and then P_Files.Loaded then
            CPU.SP := CPU.SP + 2;              --  its POP DE
            P_Files.Load_Into_Memory;
            declare
               Last : constant Word := P_Files.Last_Address;
            begin
               CPU.H := Hi (Last);
               CPU.L := Lo (Last);
            end;
            CPU.PC := 16#0248#;                --  CALL 01F8: loading done
         elsif PC = 16#01B6# then
            CPU.SP := CPU.SP + 2;
            P_Files.Record_Memory;
            declare
               Last : constant Word := Peek_Word (16#400A#) - 1;
            begin
               CPU.H := Hi (Last);
               CPU.L := Lo (Last);
            end;
            CPU.PC := 16#01F3#;
         end if;
         return;
      end if;
      if PC = 16#0347# and then P_Files.Loaded then
         P_Files.Load_Into_Memory;     --  sets HL to the last byte
         declare
            Last : constant Word := P_Files.Last_Address;
         begin
            CPU.H := Hi (Last);
            CPU.L := Lo (Last);
         end;
         CPU.PC := 16#0380#;               --  CALL 01FC: loading done
      elsif PC = 16#02FB# then
         P_Files.Record_Memory;
         declare
            Last : constant Word := Peek_Word (16#4014#) - 1;
         begin
            CPU.H := Hi (Last);
            CPU.L := Lo (Last);
         end;
         CPU.PC := 16#0319#;
      end if;
   end ZX81_Traps;

   ---------------------------------------------------------------------
   --  BASIC debugging
   ---------------------------------------------------------------------

   function Basic_Current_Line return Integer is
   begin
      if Config.Is_ZX80 then
         declare
            P : constant Word := Peek_Word (16#4002#);    --  PPC
         begin
            return (if P >= 16#FFFE# then -1 else Integer (P));
         end;
      elsif Config.Is_ZX81 then
         declare
            P : constant Word := Peek_Word (16#4007#);    --  PPC
         begin
            return (if P >= 16#FFFE# then -1 else Integer (P));
         end;
      end if;
      declare
         P : constant Word := Peek_Word (23621);            --  PPC
      begin
         --  bit 7 of FLAGS: syntax checking (editing), not running
         if P >= 16#FFFE# or else (Peek (23611) and 16#80#) = 0 then
            return -1;
         end if;
         return Integer (P);
      end;
   end Basic_Current_Line;

   --  The interpreter is about to execute a statement
   function At_Statement return Boolean is
     (if Config.Is_ZX80 then False
      elsif Config.Is_ZX81 then CPU.PC = 16#0CC1#
      else CPU.PC = 16#1B29#
        and then Memory.Current_ROM = Memory.Basic48_ROM);

   function Basic_Check return Boolean is
   begin
      if not At_Statement then
         return False;
      end if;
      declare
         L : constant Integer := Basic_Current_Line;
      begin
         if L < 0 then
            return False;
         end if;
         if L /= Basic_Last_Line then
            Basic_Last_Line := L;
            if Basic_Stepping then
               Basic_Stopped := L;
               return True;
            end if;
            for I in 1 .. Basic_BP_Count loop
               if Basic_BPs (I) = L then
                  Basic_Stopped := L;
                  return True;
               end if;
            end loop;
         end if;
      end;
      return False;
   end Basic_Check;

   procedure Clear_Basic_Breakpoints is
   begin
      Basic_BP_Count := 0;
   end Clear_Basic_Breakpoints;

   procedure Add_Basic_Breakpoint (Line_Number : Natural) is
   begin
      if Basic_BP_Count < Basic_BPs'Last then
         Basic_BP_Count := Basic_BP_Count + 1;
         Basic_BPs (Basic_BP_Count) := Line_Number;
      end if;
   end Add_Basic_Breakpoint;

   procedure Step_Basic_Line is
   begin
      Basic_Last_Line := Basic_Current_Line;
      Basic_Stepping := True;
      Resume;
   end Step_Basic_Line;

   function Basic_Stop_Line return Integer is (Basic_Stopped);

   ---------------------------------------------------------------------
   --  Main loop
   ---------------------------------------------------------------------

   procedure End_Of_Frame is
   begin
      Keyboard.Tick_Typing;
      Autostart_Step;
      if Wait_Seen then
         Prompt_Frames := Prompt_Frames + 1;
      else
         Prompt_Frames := 0;
      end if;
      Wait_Seen := False;
      Frames := Frames + 1;
   end End_Of_Frame;

   procedure Finish_Frame (Length : Natural) is
   begin
      if RZX_On and then Replay.Recording then
         Replay.Record_Frame (RZX_Fetches);
         RZX_Fetches := 0;
      end if;
      if not Config.Is_ZX81 then
         ULA.End_Frame;
      end if;
      Sound.End_Frame (Length);
      Tape.End_Frame (Length);
      T := T - Length;
      Next_HSync := Next_HSync - Length;
      VSync_Start_T := VSync_Start_T - Length;
      Line_Start_T := Line_Start_T - Length;
      Total_Cycles := Total_Cycles + Long_Long_Integer (Length);
      End_Of_Frame;
   end Finish_Frame;

   --  Before an instruction: breakpoints. True = stop here.
   function Debug_Before return Boolean is
   begin
      if Pause_Req then
         Stop (Paused);
         return True;
      end if;
      if not Skip_Break then
         if BP_Map (CPU.PC) then
            Stop (Breakpoint);
            return True;
         end if;
         if Temp_Addr >= 0 and then Integer (CPU.PC) = Temp_Addr
           and then CPU.SP >= Temp_SP
         then
            Stop (Step_Done);
            return True;
         end if;
      end if;
      Skip_Break := False;
      return False;
   end Debug_Before;

   --  After an instruction: watches, step out, BASIC lines
   function Debug_After (Op : Byte; Old_SP : Word) return Boolean is
   begin
      if Watch_Hit then
         Watch_Hit := False;
         Stop (if Watch_Write_Hit then Watch_Write else Watch_Read);
         return True;
      end if;
      if Out_Active and then CPU.SP > Old_SP
        and then (Op = 16#C9# or else (Op and 16#C7#) = 16#C0#
                  or else Op = 16#ED#)
        and then CPU.SP > Out_SP
      then
         Stop (Step_Done);
         return True;
      end if;
      if (Basic_BP_Count > 0 or else Basic_Stepping) and then Basic_Check
      then
         Stop (Basic_Line);
         return True;
      end if;
      return False;
   end Debug_After;

   procedure Execute_One is
   begin
      if Config.Is_ZX81 then
         --  /INT is A6, low only during the refresh of an M1 cycle: the
         --  Z80 sees it when an instruction ends with that M1 (NOP, HALT)
         CPU.INT_Line := T = Last_M1_End
           and then ((CPU.R - 1) and 16#40#) = 0;
         if CPU.Halted and then NMI_Gen and then T <= Next_HSync then
            T := Next_HSync;          --  WAIT until the NMI
            HSync (Next_HSync);
            Next_HSync := Next_HSync + ZX81_Line_T;
         end if;
         --  an HSYNC due exactly now waits: an interrupt acknowledge in
         --  this instruction replaces it
         while Next_HSync < T loop
            HSync (Next_HSync);
            Next_HSync := Next_HSync + ZX81_Line_T;
         end loop;
         declare
            T0 : constant Integer := T;
         begin
            CPU.Step;
            if CPU.Interrupt_Accepted then
               --  the interrupt acknowledge restarts the line
               HSync (T0 + HSync_Phase_T);
               Next_HSync := T0 + HSync_Phase_T + ZX81_Line_T;
            end if;
         end;
         ZX81_Traps;
      else
         CPU.INT_Line := T < ULA.Int_Length;
         Spectrum_Traps;
         CPU.Step;
      end if;
      if not Wait_Seen and then In_Key_Wait then
         Wait_Seen := True;
      end if;
   end Execute_One;

   function Frame_Length return Natural is
     (if Config.Is_ZX81 then ZX81_Frame_T else ULA.Frame_T);

   procedure Start_Replay_Part (Ok : out Boolean);

   --  RZX playback: the frame ends after the recorded number of fetches
   procedure Run_Replay_Frame is
      Limit : constant Natural := 4 * Frame_Length;
   begin
      while RZX_Fetches < Replay.Frame_Fetches loop
         if Debugging then
            if Debug_Before then
               return;
            end if;
            declare
               Op : constant Byte := Memory.Read (CPU.PC);
               Old_SP : constant Word := CPU.SP;
            begin
               Execute_One;
               if Debug_After (Op, Old_SP) then
                  return;
               end if;
            end;
         else
            Execute_One;
         end if;
         if T > Limit then
            Err := To_Unbounded_String ("RZX playback out of step");
            Replay.Stop_Playing;
            RZX_On := False;
            return;
         end if;
      end loop;
      Finish_Frame (Natural'Max (T, 0));
      RZX_Fetches := 0;
      declare
         New_Part : Boolean;
         Ok : Boolean;
      begin
         Replay.Next_Frame (New_Part);
         if New_Part then
            Start_Replay_Part (Ok);
         elsif not Replay.Playing then
            RZX_On := False;
         end if;
      end;
   end Run_Replay_Frame;

   procedure Run_Frame is
      Len : constant Natural := Frame_Length;
   begin
      if Break_Flag or else not Powered then
         return;
      end if;
      if RZX_On and then Replay.Playing then
         Run_Replay_Frame;
         return;
      end if;
      while T < Len loop
         if Debugging then
            if Debug_Before then
               return;
            end if;
            declare
               Op : constant Byte := Memory.Read (CPU.PC);
               Old_SP : constant Word := CPU.SP;
            begin
               Execute_One;
               if Debug_After (Op, Old_SP) then
                  return;
               end if;
            end;
         else
            Execute_One;
         end if;
      end loop;
      Finish_Frame (Len);
   end Run_Frame;

   ---------------------------------------------------------------------
   --  Debugger operations
   ---------------------------------------------------------------------

   procedure Step_Instruction is
   begin
      Execute_One;
      Watch_Hit := False;
      Skip_Break := True;
      Reason := Step_Done;
      if T >= Frame_Length then
         Finish_Frame (Frame_Length);
      end if;
   end Step_Instruction;

   procedure Step_Over is
      Len : Natural;
      Text : constant String :=
        Disasm.Instruction (Monitor_Peek'Access, CPU.PC, Len);
      pragma Unreferenced (Text);
   begin
      if Disasm.Is_Call (Monitor_Peek'Access, CPU.PC) then
         Temp_Addr := Integer (CPU.PC + Word (Len));
         Temp_SP := CPU.SP;
         Resume;
      else
         Step_Instruction;
      end if;
   end Step_Over;

   procedure Step_Out is
   begin
      Out_Active := True;
      Out_SP := CPU.SP;
      Resume;
   end Step_Out;

   procedure Run_To (Addr : Word) is
   begin
      Temp_Addr := Integer (Addr);
      Temp_SP := 0;
      Resume;
   end Run_To;

   procedure Request_Break is
   begin
      if not Break_Flag then
         Pause_Req := True;
      end if;
   end Request_Break;

   procedure Resume is
   begin
      Break_Flag := False;
      Skip_Break := True;
      Watch_Hit := False;
   end Resume;

   function Last_Stop return Stop_Reason is (Reason);

   function Stop_Text return String is
   begin
      case Reason is
         when None => return "";
         when Breakpoint => return "breakpoint at $" & Disasm.Hex4 (CPU.PC);
         when Watch_Read =>
            return "read of $" & Disasm.Hex4 (Watch_Addr) & " (PC $" &
              Disasm.Hex4 (CPU.PC) & ")";
         when Watch_Write =>
            return "write to $" & Disasm.Hex4 (Watch_Addr) & " (PC $" &
              Disasm.Hex4 (CPU.PC) & ")";
         when Step_Done => return "stopped at $" & Disasm.Hex4 (CPU.PC);
         when Paused => return "paused at $" & Disasm.Hex4 (CPU.PC);
         when Basic_Line => return "BASIC line" & Basic_Stopped'Image;
      end case;
   end Stop_Text;

   procedure Add_Watch (From, To : Word; On_Read, On_Write : Boolean) is
   begin
      for I in 1 .. Watch_Count loop
         if Watches (I).From = From then
            Watches (I) := (From, To, On_Read, On_Write);
            return;
         end if;
      end loop;
      if Watch_Count < Watches'Last then
         Watch_Count := Watch_Count + 1;
         Watches (Watch_Count) := (From, To, On_Read, On_Write);
      end if;
   end Add_Watch;

   procedure Remove_Watch (From : Word) is
   begin
      for I in 1 .. Watch_Count loop
         if Watches (I).From = From then
            Watches (I .. Watch_Count - 1) := Watches (I + 1 .. Watch_Count);
            Watch_Count := Watch_Count - 1;
            return;
         end if;
      end loop;
   end Remove_Watch;

   procedure Clear_Watches is
   begin
      Watch_Count := 0;
   end Clear_Watches;

   function Watch_List return String is
      R : Unbounded_String;
   begin
      for I in 1 .. Watch_Count loop
         Append (R, " $" & Disasm.Hex4 (Watches (I).From));
         if Watches (I).To /= Watches (I).From then
            Append (R, "-$" & Disasm.Hex4 (Watches (I).To));
         end if;
      end loop;
      return To_String (R);
   end Watch_List;

   procedure Set_Breakpoint (Addr : Word) is
   begin
      if not BP_Map (Addr) and then BP_Count < Max_BP then
         BP_Count := BP_Count + 1;
         Breakpoints (BP_Count) := Addr;
         BP_Map (Addr) := True;
      end if;
   end Set_Breakpoint;

   procedure Clear_Breakpoint (Addr : Word) is
   begin
      for I in 1 .. BP_Count loop
         if Breakpoints (I) = Addr then
            Breakpoints (I .. BP_Count - 1) := Breakpoints (I + 1 .. BP_Count);
            BP_Count := BP_Count - 1;
            BP_Map (Addr) := False;
            return;
         end if;
      end loop;
   end Clear_Breakpoint;

   procedure Clear_Breakpoints is
   begin
      for I in 1 .. BP_Count loop
         BP_Map (Breakpoints (I)) := False;
      end loop;
      BP_Count := 0;
   end Clear_Breakpoints;

   function Breakpoint_List return String is
      R : Unbounded_String;
   begin
      for I in 1 .. BP_Count loop
         Append (R, " $" & Disasm.Hex4 (Breakpoints (I)));
      end loop;
      return To_String (R);
   end Breakpoint_List;

   function Is_Breakpoint (Addr : Word) return Boolean is (BP_Map (Addr));
   function Break_Hit return Boolean is (Break_Flag);

   function Monitor_Peek (Addr : Word) return Byte is (Memory.Read (Addr));
   procedure Monitor_Poke (Addr : Word; Value : Byte) is
   begin
      Memory.Poke_Any (Addr, Value);
   end Monitor_Poke;
   function CPU_PC return Word is (CPU.PC);
   procedure Monitor_Set_PC (Addr : Word) is
   begin
      CPU.PC := Addr;
      CPU.Halted := False;
   end Monitor_Set_PC;

   function Flags_Text return String is
      Names : constant String := "SZ5H3PNC";
      R : String (1 .. 8);
   begin
      for K in 0 .. 7 loop
         R (K + 1) := (if (CPU.F and Shift_Right (Byte'(16#80#), K)) /= 0
                       then Names (K + 1) else '-');
      end loop;
      return R;
   end Flags_Text;

   function Register_Text return String is
      use Disasm;
   begin
      return "AF=" & Hex4 (CPU.AF) & " BC=" & Hex4 (CPU.BC) &
        " DE=" & Hex4 (CPU.DE) & " HL=" & Hex4 (CPU.HL) &
        " IX=" & Hex4 (CPU.IX) & " IY=" & Hex4 (CPU.IY) &
        " SP=" & Hex4 (CPU.SP) & " PC=" & Hex4 (CPU.PC) & ASCII.LF &
        "AF'=" & Hex4 (Make_Word (CPU.F2, CPU.A2)) &
        " BC'=" & Hex4 (Make_Word (CPU.C2, CPU.B2)) &
        " DE'=" & Hex4 (Make_Word (CPU.E2, CPU.D2)) &
        " HL'=" & Hex4 (Make_Word (CPU.L2, CPU.H2)) &
        " I=" & Hex2 (CPU.I) & " R=" & Hex2 (CPU.R) &
        " IM" & Integer'Image (CPU.IM) &
        (if CPU.IFF1 then " EI" else " DI") &
        (if CPU.Halted then " HALT" else "") &
        (if Interface_1.Paged then " IF1" else "") &
        "  " & Flags_Text & "  T=" & Integer'Image (T);
   end Register_Text;

   function Debug_Info return String is
   begin
      return Register_Text & ASCII.LF &
        Model_Name (Model) & " frames=" & Frames'Image &
        (if Is_128 then " 7FFD=" & Disasm.Hex2 (Memory.Port_7FFD) &
           " 1FFD=" & Disasm.Hex2 (Memory.Port_1FFD) &
           " ROM" & Memory.Current_ROM'Image
         else "") &
        (if Config.Is_ZX81
         then " NMI=" & (if NMI_Gen then "on" else "off") &
           " LINECNTR=" & Line_Counter'Image
         else " border=" & ULA.Border_Colour'Image) &
        (if Tape.Loaded then " tape block" & Tape.Current_Block'Image &
           "/" & Tape.Block_Count'Image &
           (if Tape.Playing then " playing" else "")
         else "");
   end Debug_Info;

   ---------------------------------------------------------------------
   --  Snapshots
   ---------------------------------------------------------------------

   procedure Save_Snapshot (Path : String; Ok : out Boolean) is
   begin
      Machine.Snapshots.Save (Path, Ok);
      if not Ok then
         Err := To_Unbounded_String (Machine.Snapshots.Error_Message);
      end if;
   end Save_Snapshot;

   procedure Start_Replay_Part (Ok : out Boolean) is
      Wanted : Model_Type;
   begin
      Ok := True;
      if Replay.Has_Snapshot then
         declare
            Kind : constant String := Replay.Snapshot_Kind;
            Data : constant Byte_Array := Replay.Snapshot_Data;
         begin
            Machine.Snapshots.Peek_Model_Data (Kind, Data, Wanted, Ok);
            if Ok and then Wanted /= Model then
               Power_On (Wanted, To_String (ROM_Dir_Used), Ok);
            end if;
            if Ok then
               Machine.Snapshots.Load_Data (Kind, Data, Ok);
            end if;
            if not Ok then
               Err := To_Unbounded_String (Machine.Snapshots.Error_Message);
               Replay.Stop_Playing;
               RZX_On := False;
               return;
            end if;
         end;
      end if;
      T := Replay.Start_T;
      Restart_Frame_State;
      RZX_Fetches := 0;
      RZX_On := True;
   end Start_Replay_Part;

   procedure Start_RZX_Recording is
   begin
      if Config.Is_ZX81 then
         return;
      end if;
      if Replay.Playing then
         Replay.Stop_Playing;
      end if;
      Replay.Start_Recording (Machine.Snapshots.SZX_Data, Natural'Max (T, 0));
      RZX_Fetches := 0;
      RZX_On := True;
   end Start_RZX_Recording;

   procedure Stop_RZX_Recording (Path : String; Ok : out Boolean) is
   begin
      Replay.Stop_Recording (Path, Ok);
      if not Ok then
         Err := To_Unbounded_String (Replay.Error_Message);
      end if;
      RZX_On := Replay.Playing;
   end Stop_RZX_Recording;

   function RZX_Recording return Boolean is (Replay.Recording);
   function RZX_Status return String is
     (if Replay.Recording then "RZX recording"
      elsif RZX_On then Replay.Progress else "");

   procedure Load_Snapshot (Path : String; Ok : out Boolean) is
      Wanted : Model_Type;
   begin
      if File_Ext.Of_Path (Path) = "rzx" then
         Replay.Open (Path, Ok);
         if not Ok then
            Err := To_Unbounded_String (Replay.Error_Message);
            return;
         end if;
         Start_Replay_Part (Ok);
         Stage := Idle;
         Break_Flag := False;
         return;
      end if;
      Machine.Snapshots.Peek_Model (Path, Wanted, Ok);
      if not Ok then
         Err := To_Unbounded_String (Machine.Snapshots.Error_Message);
         return;
      end if;
      if Wanted /= Model then
         Power_On (Wanted, To_String (ROM_Dir_Used), Ok);
         if not Ok then
            return;
         end if;
      end if;
      Machine.Snapshots.Load (Path, Ok);
      if not Ok then
         Err := To_Unbounded_String (Machine.Snapshots.Error_Message);
      end if;
      Stage := Idle;
      Break_Flag := False;
   end Load_Snapshot;

   function ROM_File (Name : String) return String is (Find_ROM (Name));

   function Ready_For_Keys return Boolean is (At_Prompt);

   procedure Shutdown is
   begin
      DSK.Flush_All;
      Interface_1.Flush_All;
   end Shutdown;

   procedure Set_Interface_1 (On : Boolean) is
      Ok : Boolean;
   begin
      Interface_1.Enabled := On;
      if Powered then
         Power_On (Model, To_String (ROM_Dir_Used), Ok);
      end if;
   end Set_Interface_1;

   function Interface_1_Fitted return Boolean is
     (Interface_1.Enabled and then Model in Config.ZX48 .. Config.Plus2);

   procedure Insert_Microdrive (Drive : Positive; Path : String;
                                Ok : out Boolean) is
   begin
      Interface_1.Insert (Interface_1.Drive_Number ((Drive - 1) mod 8 + 1),
                          Path, Ok);
      if not Ok then
         Err := To_Unbounded_String (Interface_1.Error_Message);
      end if;
   end Insert_Microdrive;

   procedure Eject_Microdrive (Drive : Positive) is
   begin
      Interface_1.Eject (Interface_1.Drive_Number ((Drive - 1) mod 8 + 1));
   end Eject_Microdrive;

   function Microdrive_Name (Drive : Positive) return String is
     (Interface_1.Name (Interface_1.Drive_Number ((Drive - 1) mod 8 + 1)));

   procedure Create_Microdrive (Path : String; Ok : out Boolean) is
   begin
      Interface_1.Create (Path, Ok);
      if not Ok then
         Err := To_Unbounded_String (Interface_1.Error_Message);
      end if;
   end Create_Microdrive;

   function Microdrive_Active return Boolean is (Interface_1.Motor_On);

   procedure Insert_Disc (Path : String; Ok : out Boolean;
                          Drive : Natural := 0) is
   begin
      DSK.Insert (DSK.Drive (Drive mod 2), Path, Ok);
      if not Ok then
         Err := To_Unbounded_String (DSK.Error_Message);
      end if;
   end Insert_Disc;

   procedure Eject_Disc (Drive : Natural := 0) is
   begin
      DSK.Eject (DSK.Drive (Drive mod 2));
   end Eject_Disc;

   function Disc_Name (Drive : Natural := 0) return String is
     (DSK.Name (DSK.Drive (Drive mod 2)));

   procedure Create_Disc (Path : String; Ok : out Boolean) is
   begin
      DSK.Create (Path, Ok);
      if not Ok then
         Err := To_Unbounded_String (DSK.Error_Message);
      end if;
   end Create_Disc;

   function Disc_Active return Boolean is
     (FDC765.Motor and then Model = Config.Plus3);

begin
   Keyboard.Ready := Ready_For_Keys'Access;
end Machine;
