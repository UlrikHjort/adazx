-- ***************************************************************************
--                               AdaZX - Tape
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
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Directories;
with Ada.Characters.Handling;
with Interfaces; use Interfaces;
with Config;
use type Config.Model_Type;
with Tstates;

package body Tape is

   package SIO renames Ada.Streams.Stream_IO;

   type Kind_Type is (Standard, Turbo, Tone, Pulses, Pure_Data, Direct,
                      Pause, Loop_Start, Loop_End, Jump, Stop48, Set_Level,
                      Info);

   type Block is record
      Kind : Kind_Type := Info;
      Pilot, Sync1, Sync2, Zero, One : Natural := 0;
      Pilot_Count : Natural := 0;
      Used_Bits : Natural := 8;
      Pause_Ms : Natural := 0;
      Data_Ofs, Data_Len : Natural := 0;
      Count : Natural := 0;           --  tone pulses / loop count / pulses
      Offset : Integer := 0;          --  jump
      Level : Boolean := False;
      Text : Unbounded_String;
   end record;

   Max_Blocks : constant := 4096;
   Blocks : array (1 .. Max_Blocks) of Block;
   N_Blocks : Natural := 0;

   Image : Byte_Array_Access := null;
   Image_Name : Unbounded_String;
   Err : Unbounded_String;

   --  Generator state
   type Stage_Type is (Start, Pilot_St, Sync1_St, Sync2_St, Data_St,
                       Pause_St, Pause_Rest, Tone_St, Pulse_St, Direct_St);
   type Action_Type is (None, Toggle, Set_Low, Set_High);

   Blk : Natural := 1;
   Stage : Stage_Type := Start;
   Counter : Natural := 0;
   Bit_Pos : Natural := 0;        --  bit index into the block's data
   Second_Half : Boolean := False;
   Loop_Blk : Natural := 0;
   Loop_Left : Natural := 0;
   Level : Boolean := False;
   Is_Playing : Boolean := False;
   Edge_At : Integer := 0;
   Pending : Action_Type := None;

   Scale : Float := 1.0;          --  CPU clock / 3.5 MHz

   function D (I : Natural) return Natural is (Natural (Image (I)));
   function W (I : Natural) return Natural is (D (I) + 256 * D (I + 1));
   function W3 (I : Natural) return Natural is (W (I) + 65536 * D (I + 2));
   function W4 (I : Natural) return Natural is
     (W (I) + 65536 * W (I + 2));

   function Error_Message return String is (To_String (Err));
   function Name return String is (To_String (Image_Name));
   function Loaded return Boolean is (Image /= null and then N_Blocks > 0);
   function Playing return Boolean is (Is_Playing);
   function Block_Count return Natural is (N_Blocks);
   function Current_Block return Natural is
     (if Blk in 1 .. N_Blocks then Blk else 0);

   procedure Add (B : Block) is
   begin
      if N_Blocks < Max_Blocks then
         N_Blocks := N_Blocks + 1;
         Blocks (N_Blocks) := B;
      end if;
   end Add;

   function Header_Text (Ofs, Len : Natural) return String is
   begin
      if Len = 19 and then D (Ofs) = 0 then
         declare
            Kind : constant String :=
              (case D (Ofs + 1) is
                  when 0 => "Program: ",
                  when 1 => "Number array: ",
                  when 2 => "Character array: ",
                  when others => "Bytes: ");
            N : String (1 .. 10);
         begin
            for K in 1 .. 10 loop
               N (K) := (if D (Ofs + 1 + K) in 32 .. 126
                         then Character'Val (D (Ofs + 1 + K)) else '?');
            end loop;
            return Kind & N;
         end;
      elsif Len > 0 then
         return "data, " & Natural'Image (Len - 2) & " bytes";
      end if;
      return "empty";
   end Header_Text;

   function Std (Data_Ofs, Len, Pause_Ms : Natural) return Block is
      B : Block;
   begin
      B.Kind := Standard;
      B.Pilot := 2168;
      B.Sync1 := 667;
      B.Sync2 := 735;
      B.Zero := 855;
      B.One := 1710;
      B.Pilot_Count :=
        (if Len > 0 and then D (Data_Ofs) < 128 then 8063 else 3223);
      B.Used_Bits := 8;
      B.Pause_Ms := Pause_Ms;
      B.Data_Ofs := Data_Ofs;
      B.Data_Len := Len;
      B.Text := To_Unbounded_String (Header_Text (Data_Ofs, Len));
      return B;
   end Std;

   procedure Parse_TAP is
      P : Natural := 0;
   begin
      while P + 1 < Image'Length loop
         declare
            Len : constant Natural := W (P);
         begin
            exit when P + 2 + Len > Image'Length;
            Add (Std (P + 2, Len, 1000));
            P := P + 2 + Len;
         end;
      end loop;
   end Parse_TAP;

   procedure Parse_TZX (Ok : out Boolean) is
      P : Natural := 10;
      Last : constant Natural := Image'Length;
      Magic : constant String := "ZXTape!";
   begin
      Ok := Last >= 10
        and then (for all K in 0 .. 6 =>
                    Character'Val (D (K)) = Magic (K + 1));
      if not Ok then
         Err := To_Unbounded_String ("not a TZX file");
         return;
      end if;
      while P < Last loop
         declare
            Id : constant Natural := D (P);
            B : Block;
            Len : Natural := 0;
         begin
            P := P + 1;
            case Id is
               when 16#10# =>
                  Len := W (P + 2);
                  Add (Std (P + 4, Len, W (P)));
                  P := P + 4 + Len;
               when 16#11# =>
                  B.Kind := Turbo;
                  B.Pilot := W (P);
                  B.Sync1 := W (P + 2);
                  B.Sync2 := W (P + 4);
                  B.Zero := W (P + 6);
                  B.One := W (P + 8);
                  B.Pilot_Count := W (P + 10);
                  B.Used_Bits := D (P + 12);
                  B.Pause_Ms := W (P + 13);
                  Len := W3 (P + 15);
                  B.Data_Ofs := P + 18;
                  B.Data_Len := Len;
                  B.Text := To_Unbounded_String
                    ("turbo " & Header_Text (P + 18, Len));
                  Add (B);
                  P := P + 18 + Len;
               when 16#12# =>
                  B.Kind := Tone;
                  B.Pilot := W (P);
                  B.Count := W (P + 2);
                  B.Text := To_Unbounded_String ("pure tone");
                  Add (B);
                  P := P + 4;
               when 16#13# =>
                  B.Kind := Pulses;
                  B.Count := D (P);
                  B.Data_Ofs := P + 1;
                  B.Text := To_Unbounded_String ("pulse sequence");
                  Add (B);
                  P := P + 1 + 2 * B.Count;
               when 16#14# =>
                  B.Kind := Pure_Data;
                  B.Zero := W (P);
                  B.One := W (P + 2);
                  B.Used_Bits := D (P + 4);
                  B.Pause_Ms := W (P + 5);
                  Len := W3 (P + 7);
                  B.Data_Ofs := P + 10;
                  B.Data_Len := Len;
                  B.Text := To_Unbounded_String ("pure data");
                  Add (B);
                  P := P + 10 + Len;
               when 16#15# =>
                  B.Kind := Direct;
                  B.Pilot := W (P);           --  T-states per sample
                  B.Pause_Ms := W (P + 2);
                  B.Used_Bits := D (P + 4);
                  Len := W3 (P + 5);
                  B.Data_Ofs := P + 8;
                  B.Data_Len := Len;
                  B.Text := To_Unbounded_String ("direct recording");
                  Add (B);
                  P := P + 8 + Len;
               when 16#18# | 16#19# =>
                  B.Text := To_Unbounded_String
                    ("unsupported block (CSW / generalized data)");
                  Add (B);
                  P := P + 4 + W4 (P);
               when 16#20# =>
                  B.Kind := Pause;
                  B.Pause_Ms := W (P);
                  B.Text := To_Unbounded_String
                    (if B.Pause_Ms = 0 then "stop the tape" else "pause");
                  Add (B);
                  P := P + 2;
               when 16#21# =>
                  B.Text := To_Unbounded_String ("group");
                  Add (B);
                  P := P + 1 + D (P);
               when 16#22# | 16#25# | 16#27# =>
                  if Id = 16#25# then
                     B.Kind := Loop_End;
                  end if;
                  Add (B);
               when 16#23# =>
                  B.Kind := Jump;
                  B.Offset := W (P);
                  if B.Offset >= 32768 then
                     B.Offset := B.Offset - 65536;
                  end if;
                  Add (B);
                  P := P + 2;
               when 16#24# =>
                  B.Kind := Loop_Start;
                  B.Count := W (P);
                  Add (B);
                  P := P + 2;
               when 16#26# =>
                  P := P + 2 + 2 * W (P);
               when 16#28# =>
                  P := P + 2 + W (P);
               when 16#2A# =>
                  B.Kind := Stop48;
                  Add (B);
                  P := P + 4;
               when 16#2B# =>
                  B.Kind := Set_Level;
                  B.Level := D (P + 4) /= 0;
                  Add (B);
                  P := P + 5;
               when 16#30# =>
                  P := P + 1 + D (P);
               when 16#31# =>
                  P := P + 2 + D (P + 1);
               when 16#32# =>
                  P := P + 2 + W (P);
               when 16#33# =>
                  P := P + 1 + 3 * D (P);
               when 16#35# =>
                  P := P + 20 + W4 (P + 16);
               when 16#5A# =>
                  P := P + 9;
               when others =>
                  --  Extension rule: a DWORD length follows the ID
                  P := P + 4 + W4 (P);
            end case;
         end;
      end loop;
   exception
      when others =>
         --  a truncated last block: keep what was read
         Ok := N_Blocks > 0;
   end Parse_TZX;

   procedure Insert (Path : String; Ok : out Boolean) is
      F : SIO.File_Type;
      Ext : constant String := Ada.Characters.Handling.To_Lower
        (File_Ext.Of_Path (Path));
   begin
      Eject;
      SIO.Open (F, SIO.In_File, Path);
      Image := new Byte_Array (0 .. Natural (SIO.Size (F)) - 1);
      Byte_Array'Read (SIO.Stream (F), Image.all);
      SIO.Close (F);
      if Ext = "tzx" then
         Parse_TZX (Ok);
      else
         Parse_TAP;
         Ok := N_Blocks > 0;
         if not Ok then
            Err := To_Unbounded_String ("no blocks in the tape image");
         end if;
      end if;
      if Ok then
         Image_Name := To_Unbounded_String (Ada.Directories.Simple_Name (Path));
      end if;
      Rewind;
   exception
      when others =>
         Err := To_Unbounded_String ("cannot read " & Path);
         Ok := False;
   end Insert;

   procedure Eject is
   begin
      Image := null;
      N_Blocks := 0;
      Image_Name := Null_Unbounded_String;
      Is_Playing := False;
      Rewind;
   end Eject;

   procedure Rewind is
   begin
      Blk := 1;
      Stage := Start;
      Loop_Left := 0;
      Pending := None;
   end Rewind;

   procedure Play is
   begin
      if Loaded then
         if Blk > N_Blocks then
            Rewind;
         end if;
         Scale := Float (Config.CPU_Clock) / 3_500_000.0;
         Is_Playing := True;
         Edge_At := Tstates.T;
         Pending := None;
      end if;
   end Play;

   procedure Stop is
   begin
      Is_Playing := False;
      if On_Edge /= null then
         On_Edge (False, Tstates.T);
      end if;
   end Stop;

   function Data_Bit (B : Block; Index : Natural) return Boolean is
      Byte_I : constant Natural := Index / 8;
   begin
      return (Image (B.Data_Ofs + Byte_I)
              and Shift_Right (Byte'(16#80#), Index mod 8)) /= 0;
   end Data_Bit;

   function Total_Bits (B : Block) return Natural is
     (if B.Data_Len = 0 then 0
      else (B.Data_Len - 1) * 8 + Natural'Max (1, Natural'Min (B.Used_Bits, 8)));

   procedure Next_Block is
   begin
      Blk := Blk + 1;
      Stage := Start;
   end Next_Block;

   --  The next event: after Dur T-states (3.5 MHz) perform Act.
   --  Dur = 0 with Act = None: the tape stopped.
   procedure Next_Event (Dur : out Natural; Act : out Action_Type) is
   begin
      loop
         if Blk > N_Blocks then
            Is_Playing := False;
            Dur := 0;
            Act := None;
            return;
         end if;
         declare
            B : Block renames Blocks (Blk);
         begin
            case Stage is
               when Start =>
                  Counter := 0;
                  Bit_Pos := 0;
                  Second_Half := False;
                  case B.Kind is
                     when Standard | Turbo =>
                        Counter := B.Pilot_Count;
                        Stage := Pilot_St;
                     when Tone =>
                        Counter := B.Count;
                        Stage := Tone_St;
                     when Pulses =>
                        Stage := Pulse_St;
                     when Pure_Data =>
                        Stage := Data_St;
                     when Direct =>
                        Stage := Direct_St;
                     when Pause =>
                        if B.Pause_Ms = 0 then
                           Next_Block;
                           Is_Playing := False;
                           Dur := 0;
                           Act := None;
                           return;
                        end if;
                        Stage := Pause_St;
                     when Loop_Start =>
                        Loop_Blk := Blk;
                        Loop_Left := B.Count;
                        Next_Block;
                     when Loop_End =>
                        if Loop_Left > 1 then
                           Loop_Left := Loop_Left - 1;
                           Blk := Loop_Blk + 1;
                           Stage := Start;
                        else
                           Next_Block;
                        end if;
                     when Jump =>
                        Blk := Natural (Integer'Max (1, Blk + B.Offset));
                        Stage := Start;
                     when Stop48 =>
                        Next_Block;
                        if Config.Model = Config.ZX48 then
                           Is_Playing := False;
                           Dur := 0;
                           Act := None;
                           return;
                        end if;
                     when Set_Level =>
                        Level := B.Level;
                        Next_Block;
                     when Info =>
                        Next_Block;
                  end case;
               when Pilot_St =>
                  if Counter > 0 then
                     Counter := Counter - 1;
                     Dur := B.Pilot;
                     Act := Toggle;
                     return;
                  end if;
                  Stage := Sync1_St;
               when Sync1_St =>
                  Stage := Sync2_St;
                  if B.Sync1 > 0 then
                     Dur := B.Sync1;
                     Act := Toggle;
                     return;
                  end if;
               when Sync2_St =>
                  Stage := Data_St;
                  if B.Sync2 > 0 then
                     Dur := B.Sync2;
                     Act := Toggle;
                     return;
                  end if;
               when Data_St =>
                  if Bit_Pos >= Total_Bits (B) then
                     Stage := Pause_St;
                  else
                     Dur := (if Data_Bit (B, Bit_Pos) then B.One else B.Zero);
                     Act := Toggle;
                     if Second_Half then
                        Bit_Pos := Bit_Pos + 1;
                     end if;
                     Second_Half := not Second_Half;
                     return;
                  end if;
               when Tone_St =>
                  if Counter > 0 then
                     Counter := Counter - 1;
                     Dur := B.Pilot;
                     Act := Toggle;
                     return;
                  end if;
                  Next_Block;
               when Pulse_St =>
                  if Counter < B.Count then
                     Dur := W (B.Data_Ofs + 2 * Counter);
                     Counter := Counter + 1;
                     Act := Toggle;
                     return;
                  end if;
                  Next_Block;
               when Direct_St =>
                  if Bit_Pos < Total_Bits (B) then
                     Dur := B.Pilot;
                     Act := (if Data_Bit (B, Bit_Pos) then Set_High
                             else Set_Low);
                     Bit_Pos := Bit_Pos + 1;
                     return;
                  end if;
                  Stage := Pause_St;
               when Pause_St =>
                  if B.Pause_Ms > 0 then
                     Stage := Pause_Rest;
                     Dur := 3500;           --  finish the last pulse
                     Act := Set_Low;
                     return;
                  end if;
                  Next_Block;
               when Pause_Rest =>
                  Next_Block;
                  if B.Pause_Ms > 1 then
                     Dur := (B.Pause_Ms - 1) * 3500;
                     Act := None;
                     return;
                  end if;
            end case;
         end;
      end loop;
   end Next_Event;

   procedure Apply (Act : Action_Type; T : Integer) is
      Old : constant Boolean := Level;
   begin
      case Act is
         when None => null;
         when Toggle => Level := not Level;
         when Set_Low => Level := False;
         when Set_High => Level := True;
      end case;
      if Level /= Old and then On_Edge /= null then
         On_Edge (Level, T);
      end if;
   end Apply;

   function Ear (T : Integer) return Boolean is
      Dur : Natural;
      Act : Action_Type;
   begin
      while Is_Playing and then Edge_At <= T loop
         Apply (Pending, Edge_At);
         Next_Event (Dur, Act);
         exit when not Is_Playing;
         Edge_At := Edge_At + Natural (Float (Dur) * Scale);
         Pending := Act;
      end loop;
      return Level;
   end Ear;

   procedure End_Frame (Frame_T : Natural) is
      L : constant Boolean := Ear (Frame_T);
      pragma Unreferenced (L);
   begin
      if Is_Playing then
         Edge_At := Edge_At - Frame_T;
      end if;
   end End_Frame;

   function At_Standard_Block return Boolean is
   begin
      while Blk <= N_Blocks and then Stage = Start
        and then Blocks (Blk).Kind in Info | Set_Level
      loop
         Next_Block;
      end loop;
      return Blk <= N_Blocks
        and then Blocks (Blk).Kind = Standard
        and then Stage in Start | Pilot_St;
   end At_Standard_Block;

   function Take_Block return Byte_Array is
      B : constant Block := Blocks (Blk);
   begin
      Next_Block;
      Pending := None;
      Edge_At := Tstates.T;
      return Image (B.Data_Ofs .. B.Data_Ofs + B.Data_Len - 1);
   end Take_Block;

   function Block_Text (I : Positive) return String is
     (if I <= N_Blocks then To_String (Blocks (I).Text) else "");

   ---------------------------------------------------------------------
   --  Recording
   ---------------------------------------------------------------------

   Rec : Byte_Array (0 .. 1024 * 1024 - 1);
   Rec_Len : Natural := 0;

   procedure Record_Block (Data : Byte_Array) is
   begin
      if Rec_Len + Data'Length + 2 <= Rec'Length then
         Rec (Rec_Len) := Byte (Data'Length mod 256);
         Rec (Rec_Len + 1) := Byte (Data'Length / 256);
         Rec (Rec_Len + 2 .. Rec_Len + 1 + Data'Length) := Data;
         Rec_Len := Rec_Len + 2 + Data'Length;
      end if;
   end Record_Block;

   function Recorded_Bytes return Natural is (Rec_Len);

   procedure Clear_Recording is
   begin
      Rec_Len := 0;
   end Clear_Recording;

   procedure Save_Recording (Path : String; Ok : out Boolean) is
      F : SIO.File_Type;
   begin
      SIO.Create (F, SIO.Out_File, Path);
      Byte_Array'Write (SIO.Stream (F), Rec (0 .. Rec_Len - 1));
      SIO.Close (F);
      Ok := True;
   exception
      when others =>
         Ok := False;
   end Save_Recording;

end Tape;
