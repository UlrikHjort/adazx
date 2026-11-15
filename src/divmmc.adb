-- ***************************************************************************
--                              AdaZX - DivMMC
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

with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.IO_Exceptions;
with Ada.Direct_IO;
with Interfaces; use Interfaces;

package body DivMMC is

   package SIO renames Ada.Streams.Stream_IO;

   ROM : Byte_Array (0 .. 16#1FFF#) := (others => 16#FF#);
   Have_ROM : Boolean := False;
   RAM : Byte_Array (0 .. 64 * 16#2000# - 1) := (others => 0);

   Control : Byte := 0;           --  port &E3
   MapRAM : Boolean := False;
   Automap : Boolean := False;

   function ConMem return Boolean is ((Control and 16#80#) /= 0);
   function Bank return Natural is (Natural (Control and 16#3F#));

   procedure Load_ROM (Path : String; Ok : out Boolean) is
      F : SIO.File_Type;
      Last : Stream_Element_Offset;
      Buf : Stream_Element_Array (1 .. 16#2000#);
   begin
      Ok := False;
      SIO.Open (F, SIO.In_File, Path);
      SIO.Read (F, Buf, Last);
      SIO.Close (F);
      if Last < 16#2000# then
         return;
      end if;
      for I in ROM'Range loop
         ROM (I) := Byte (Buf (Stream_Element_Offset (I) + 1));
      end loop;
      Have_ROM := True;
      Ok := True;
   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Ok := False;
   end Load_ROM;

   function ROM_Loaded return Boolean is (Have_ROM);

   function Active return Boolean is
     (Enabled and then (Automap or else ConMem));

   function Read (Addr : Word) return Byte is
   begin
      if Addr < 16#2000# then
         if MapRAM and then not ConMem then
            return RAM (3 * 16#2000# + Natural (Addr));
         end if;
         return ROM (Natural (Addr));
      end if;
      return RAM (Bank * 16#2000# + Natural (Addr - 16#2000#));
   end Read;

   procedure Write (Addr : Word; V : Byte) is
   begin
      if Addr >= 16#2000#
        and then (ConMem or else not MapRAM or else Bank /= 3)
      then
         RAM (Bank * 16#2000# + Natural (Addr - 16#2000#)) := V;
      end if;
   end Write;

   procedure Before_Fetch (Addr : Word) is
   begin
      if Enabled and then (Addr and 16#FF00#) = 16#3D00# then
         Automap := True;            --  instant: this fetch is mapped
      end if;
   end Before_Fetch;

   procedure After_Fetch (Addr : Word) is
   begin
      if not Enabled then
         return;
      end if;
      case Addr is
         when 16#0000# | 16#0008# | 16#0038# | 16#0066# | 16#04C6#
            | 16#0562# =>
            Automap := True;
         when 16#1FF8# .. 16#1FFF# =>
            Automap := False;
         when others => null;
      end case;
   end After_Fetch;

   ---------------------------------------------------------------------
   --  SD card (SPI mode)
   ---------------------------------------------------------------------

   type Sector is array (0 .. 511) of Byte;
   package DIO is new Ada.Direct_IO (Sector);
   Card : DIO.File_Type;
   Card_Path : Unbounded_String;
   Card_Writable : Boolean := False;
   Blocks : Natural := 0;
   Err : Unbounded_String;
   Activity : Boolean := False;

   Selected : Boolean := False;
   Idle_State : Boolean := True;
   App_Cmd : Boolean := False;

   Out_Buf : Byte_Array (0 .. 1023);
   Out_Pos, Out_Len : Natural := 0;

   type In_State is (Command, Write_Token, Write_Data);
   State : In_State := Command;
   Cmd_Buf : Byte_Array (0 .. 5);
   Cmd_Len : Natural := 0;
   Data_Buf : Byte_Array (0 .. 513);      --  512 bytes + CRC
   Data_Len : Natural := 0;
   Write_Block : Natural := 0;
   Multi_Write : Boolean := False;
   Multi_Read : Boolean := False;
   Read_Block : Natural := 0;

   procedure Put (B : Byte) is
   begin
      if Out_Len <= Out_Buf'Last then
         Out_Buf (Out_Len) := B;
         Out_Len := Out_Len + 1;
      end if;
   end Put;

   procedure Clear_Output is
   begin
      Out_Pos := 0;
      Out_Len := 0;
   end Clear_Output;

   procedure Queue_Block (N : Natural) is
      Buf : Sector := (others => 0);
   begin
      Put (16#FE#);                           --  data token
      if N < Blocks then
         DIO.Read (Card, Buf, DIO.Positive_Count (N + 1));
      end if;
      for B of Buf loop
         Put (B);
      end loop;
      Put (16#FF#);                           --  CRC (not checked)
      Put (16#FF#);
      Activity := True;
   end Queue_Block;

   procedure Store_Block (N : Natural; Ok : out Boolean) is
      Buf : Sector;
   begin
      Ok := Card_Writable and then N < Blocks;
      if not Ok then
         return;
      end if;
      for I in Buf'Range loop
         Buf (I) := Data_Buf (I);
      end loop;
      DIO.Write (Card, Buf, DIO.Positive_Count (N + 1));
      Activity := True;
   end Store_Block;

   function R1 return Byte is (if Idle_State then 1 else 0);

   procedure Do_Command is
      Cmd : constant Natural := Natural (Cmd_Buf (0) and 16#3F#);
      Arg : constant Natural :=
        Natural (Cmd_Buf (1)) * 16#100_0000# + Natural (Cmd_Buf (2)) * 16#1_0000#
        + Natural (Cmd_Buf (3)) * 16#100# + Natural (Cmd_Buf (4));
      Was_App : constant Boolean := App_Cmd;
   begin
      Clear_Output;
      App_Cmd := False;
      Put (16#FF#);                           --  NCR
      if Was_App and then Cmd = 41 then       --  ACMD41: initialise
         Idle_State := False;
         Put (0);
         return;
      end if;
      case Cmd is
         when 0 =>                            --  GO_IDLE_STATE
            Idle_State := True;
            Multi_Read := False;
            Put (1);
         when 1 =>                            --  SEND_OP_COND
            Idle_State := False;
            Put (0);
         when 8 =>                            --  SEND_IF_COND
            Put (R1);
            Put (0); Put (0);
            Put (Byte (Arg / 256 mod 16));
            Put (Byte (Arg mod 256));
         when 9 =>                            --  SEND_CSD (version 2)
            declare
               C_Size : constant Natural :=
                 Natural'Max (Blocks / 1024, 1) - 1;
            begin
               Put (0);
               Put (16#FE#);
               Put (16#40#); Put (16#0E#); Put (16#00#); Put (16#32#);
               Put (16#5B#); Put (16#59#); Put (16#00#);
               Put (Byte (C_Size / 16#1_0000# mod 64));
               Put (Byte (C_Size / 256 mod 256));
               Put (Byte (C_Size mod 256));
               Put (16#7F#); Put (16#80#); Put (16#0A#); Put (16#40#);
               Put (16#00#); Put (16#01#);
               Put (16#FF#); Put (16#FF#);
            end;
         when 10 =>                           --  SEND_CID
            Put (0);
            Put (16#FE#);
            for B of Byte_Array'(16#41#, 16#44#, 16#41#, 16#5A#, 16#58#,
                                 16#53#, 16#44#, 16#20#, 16#10#, 16#00#,
                                 16#00#, 16#00#, 16#01#, 16#01#, 16#A1#,
                                 16#01#)
            loop
               Put (B);
            end loop;
            Put (16#FF#); Put (16#FF#);
         when 12 =>                           --  STOP_TRANSMISSION
            Multi_Read := False;
            Put (16#FF#);                     --  stuff byte
            Put (0);
         when 13 =>                           --  SEND_STATUS
            Put (R1);
            Put (0);
         when 16 | 59 =>                      --  SET_BLOCKLEN, CRC_ON_OFF
            Put (R1);
         when 17 | 18 =>                      --  READ_(MULTIPLE_)BLOCK
            if Arg >= Blocks then
               Put (16#40#);                  --  parameter error
            else
               Put (0);
               Queue_Block (Arg);
               Multi_Read := Cmd = 18;
               Read_Block := Arg + 1;
            end if;
         when 24 | 25 =>                      --  WRITE_(MULTIPLE_)BLOCK
            if Arg >= Blocks then
               Put (16#40#);
            else
               Put (0);
               Write_Block := Arg;
               Multi_Write := Cmd = 25;
               State := Write_Token;
            end if;
         when 55 =>                           --  APP_CMD
            App_Cmd := True;
            Put (R1);
         when 58 =>                           --  READ_OCR: SDHC, ready
            Put (R1);
            Put (16#C0#); Put (16#FF#); Put (16#80#); Put (16#00#);
         when others =>
            Put (R1 or 4);                    --  illegal command
      end case;
   end Do_Command;

   procedure Card_Write (B : Byte) is
   begin
      case State is
         when Command =>
            if Cmd_Len = 0 and then (B and 16#C0#) /= 16#40# then
               return;                        --  not a command start
            end if;
            Cmd_Buf (Cmd_Len) := B;
            Cmd_Len := Cmd_Len + 1;
            if Cmd_Len = 6 then
               Cmd_Len := 0;
               Do_Command;
            end if;
         when Write_Token =>
            if B = 16#FE# or else (Multi_Write and then B = 16#FC#) then
               State := Write_Data;
               Data_Len := 0;
            elsif Multi_Write and then B = 16#FD# then   --  stop token
               Multi_Write := False;
               State := Command;
               Clear_Output;
               Put (16#FF#);
               Put (0);                       --  busy, then ready
            end if;
         when Write_Data =>
            Data_Buf (Data_Len) := B;
            Data_Len := Data_Len + 1;
            if Data_Len = 514 then
               declare
                  Ok : Boolean;
               begin
                  Store_Block (Write_Block, Ok);
                  Clear_Output;
                  Put (if Ok then 16#05# else 16#0D#);  --  data response
                  Put (0);                    --  busy
                  Write_Block := Write_Block + 1;
                  State := (if Multi_Write and then Ok then Write_Token
                            else Command);
                  if not Ok then
                     Multi_Write := False;
                  end if;
               end;
            end if;
      end case;
   end Card_Write;

   function Card_Read return Byte is
   begin
      if Out_Pos >= Out_Len then
         Clear_Output;
         if Multi_Read and then Read_Block < Blocks then
            Queue_Block (Read_Block);
            Read_Block := Read_Block + 1;
         else
            return 16#FF#;
         end if;
      end if;
      Out_Pos := Out_Pos + 1;
      return Out_Buf (Out_Pos - 1);
   end Card_Read;

   procedure Insert (Path : String; Ok : out Boolean) is
   begin
      Eject;
      Ok := False;
      begin
         DIO.Open (Card, DIO.Inout_File, Path);
         Card_Writable := True;
      exception
         when Ada.IO_Exceptions.Use_Error =>
            DIO.Open (Card, DIO.In_File, Path);
            Card_Writable := False;
      end;
      Blocks := Natural (DIO.Size (Card));
      if Blocks < 64 then
         DIO.Close (Card);
         Err := To_Unbounded_String ("not an SD card image: " & Path);
         return;
      end if;
      Card_Path := To_Unbounded_String (Path);
      Idle_State := True;
      Ok := True;
   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Err := To_Unbounded_String ("cannot open " & Path);
         Ok := False;
   end Insert;

   procedure Eject is
   begin
      if DIO.Is_Open (Card) then
         DIO.Close (Card);
      end if;
      Card_Path := Null_Unbounded_String;
      Blocks := 0;
      State := Command;
      Cmd_Len := 0;
      Clear_Output;
   end Eject;

   function Card_Name return String is (To_String (Card_Path));
   function Error_Message return String is (To_String (Err));

   function Card_Active return Boolean is
      A : constant Boolean := Activity;
   begin
      Activity := False;
      return A;
   end Card_Active;

   ---------------------------------------------------------------------
   --  Ports
   ---------------------------------------------------------------------

   function Port_Selected (Port : Word) return Boolean is
     (Enabled and then (Lo (Port) = 16#E3# or else Lo (Port) = 16#E7#
                        or else Lo (Port) = 16#EB#));

   function Port_In (Port : Word) return Byte is
   begin
      if Lo (Port) = 16#EB# then
         return (if Selected and then Blocks > 0 then Card_Read else 16#FF#);
      end if;
      return 16#FF#;
   end Port_In;

   procedure Port_Out (Port : Word; Value : Byte) is
   begin
      case Lo (Port) is
         when 16#E3# =>
            Control := Value;
            if (Value and 16#40#) /= 0 then
               MapRAM := True;                --  stays until power off
            end if;
         when 16#E7# =>
            declare
               Now : constant Boolean := (Value and 1) = 0;   --  card 0
            begin
               if not Now then
                  State := Command;
                  Cmd_Len := 0;
               end if;
               Selected := Now;
            end;
         when 16#EB# =>
            if Selected and then Blocks > 0 then
               Card_Write (Value);
            end if;
         when others => null;
      end case;
   end Port_Out;

   procedure Reset is
   begin
      Control := 0;
      Automap := False;
      Selected := False;
      State := Command;
      Cmd_Len := 0;
      Multi_Read := False;
      Multi_Write := False;
      Clear_Output;
   end Reset;

   procedure Power_On is
   begin
      Reset;
      MapRAM := False;
      RAM := (others => 0);
      Idle_State := True;
   end Power_On;

end DivMMC;
