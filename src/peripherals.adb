-- ***************************************************************************
--                            AdaZX - Peripherals
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

with Ada.Containers.Vectors;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.IO_Exceptions;
with Interfaces; use Interfaces;
with Glib; use Glib;
with Cairo; use Cairo;
with Cairo.Image_Surface;
with Cairo.Png;
with Cairo.Surface;
with System;

package body Peripherals is

   ---------------------------------------------------------------------
   --  Kempston mouse
   ---------------------------------------------------------------------

   function Mouse_Port (Port : Word) return Boolean is
     (Mouse_On and then ((Port and 16#0121#) = 16#0001#
                         or else (Port and 16#0521#) = 16#0101#
                         or else (Port and 16#0521#) = 16#0501#));

   function Mouse_In (Port : Word) return Byte is
   begin
      if (Port and 16#0121#) = 16#0001# then
         return Mouse_Buttons;
      elsif (Port and 16#0521#) = 16#0101# then
         return Mouse_X;
      else
         return Mouse_Y;
      end if;
   end Mouse_In;

   ---------------------------------------------------------------------
   --  ZX Printer (the model of Fuse, from xz80)
   ---------------------------------------------------------------------

   type Line is array (0 .. 255) of Boolean;
   package Line_Vectors is new Ada.Containers.Vectors (Positive, Line);
   Paper : Line_Vectors.Vector;

   --  The printer follows the ROM's handshake: between lines a read shows
   --  the start of a line (bit 7) and arms it; then every write is the
   --  next pixel (bit 7: the stylus) and after 256 the line is printed.
   --  The encoder (bit 0) is always ready, so printing takes no time.
   Motor : Boolean := False;
   In_Line : Boolean := False;
   Count : Natural := 0;
   Current : Line := (others => False);

   function Printer_Port (Port : Word) return Boolean is
     (Printer_On and then (Port and 16#FF#) = 16#FB#);

   procedure Output_Line is
   begin
      Paper.Append (Current);
      Current := (others => False);
      Count := 0;
      In_Line := False;
   end Output_Line;

   function Printer_In (Cycle : Long_Long_Integer) return Byte is
      pragma Unreferenced (Cycle);
   begin
      if not Motor then
         return 16#3E#;                 --  present, stopped
      elsif not In_Line then
         In_Line := True;               --  the start of a line
         Count := 0;
         return 16#BF#;
      end if;
      return 16#3F#;                    --  the encoder: the next pixel
   end Printer_In;

   procedure Printer_Out (V : Byte; Cycle : Long_Long_Integer) is
      pragma Unreferenced (Cycle);
   begin
      if (V and 4) /= 0 then            --  motor off
         if In_Line and then Count > 0 then
            Output_Line;
         end if;
         Motor := False;
         In_Line := False;
         return;
      end if;
      Motor := True;
      if In_Line then
         Current (Count) := (V and 128) /= 0;
         Count := Count + 1;
         if Count = 256 then
            Output_Line;
         end if;
      end if;
   end Printer_Out;

   function Printed_Lines return Natural is (Natural (Paper.Length));

   function Printed_Pixel (X, Y : Natural) return Boolean is
     (Paper (Y + 1) (X));

   procedure Clear_Printout is
   begin
      Paper.Clear;
   end Clear_Printout;

   procedure Save_Printout (Path : String; Ok : out Boolean) is
      H : constant Natural := Natural'Max (1, Printed_Lines);
      package CI renames Cairo.Image_Surface;
      Surf : constant Cairo_Surface :=
        CI.Create (CI.Cairo_Format_RGB24, 256, Gint (H));
      Stride : constant Natural := Natural (CI.Get_Stride (Surf)) / 4;
      Addr : constant System.Address := CI.Get_Data_Generic (Surf);
      type Pixels is array (0 .. H - 1, 0 .. Stride - 1) of Unsigned_32;
      Dst : Pixels;
      for Dst'Address use Addr;
      pragma Import (Ada, Dst);
      Status : Cairo_Status;
   begin
      Cairo.Surface.Flush (Surf);
      for Y in 0 .. H - 1 loop
         for X in 0 .. 255 loop
            Dst (Y, X) :=
              (if Y < Printed_Lines and then Printed_Pixel (X, Y)
               then 16#202020# else 16#D8D8D0#);   --  silver paper
         end loop;
      end loop;
      Cairo.Surface.Mark_Dirty (Surf);
      Status := Cairo.Png.Write_To_Png (Surf, Path);
      Cairo.Surface.Destroy (Surf);
      Ok := Status = Cairo_Status_Success;
   end Save_Printout;

   ---------------------------------------------------------------------
   --  Multiface 128
   ---------------------------------------------------------------------

   MF_ROM : Byte_Array (0 .. 16#1FFF#) := (others => 16#FF#);
   MF_RAM : Byte_Array (0 .. 16#1FFF#) := (others => 0);
   MF_Have_ROM : Boolean := False;
   Armed : Boolean := True;         --  IC8b: the button may be pressed
   Pending : Boolean := False;      --  pressed: page in at &0066
   Visible : Boolean := False;      --  J2: software may page it in

   procedure MF_Load_ROM (Path : String; Ok : out Boolean) is
      package SIO renames Ada.Streams.Stream_IO;
      F : SIO.File_Type;
      Buf : Stream_Element_Array (1 .. 16#2000#);
      Last : Stream_Element_Offset;
   begin
      Ok := False;
      SIO.Open (F, SIO.In_File, Path);
      SIO.Read (F, Buf, Last);
      SIO.Close (F);
      if Last < 16#2000# then
         return;
      end if;
      for I in MF_ROM'Range loop
         MF_ROM (I) := Byte (Buf (Stream_Element_Offset (I) + 1));
      end loop;
      MF_Have_ROM := True;
      Ok := True;
   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Ok := False;
   end MF_Load_ROM;

   function MF_ROM_Loaded return Boolean is (MF_Have_ROM);

   function MF_Read (Addr : Word) return Byte is
     (if Addr < 16#2000# then MF_ROM (Natural (Addr))
      else MF_RAM (Natural (Addr) - 16#2000#));

   procedure MF_Write (Addr : Word; V : Byte) is
   begin
      if Addr in 16#2000# .. 16#3FFF# then
         MF_RAM (Natural (Addr) - 16#2000#) := V;
      end if;
   end MF_Write;

   function MF_Red_Button return Boolean is
   begin
      if not MF_Enabled or else not Armed then
         return False;
      end if;
      Armed := False;
      Pending := True;
      return True;
   end MF_Red_Button;

   procedure MF_Before_Fetch (Addr : Word) is
   begin
      if Pending and then Addr = 16#0066# then
         Pending := False;
         MF_Active := True;
         Visible := True;
      end if;
   end MF_Before_Fetch;

   function MF_Port (Port : Word) return Boolean is
     (MF_Enabled and then (Port and 16#72#) = 16#32#);

   function MF_In (Port : Word; Last_7FFD : Byte) return Byte is
   begin
      if (Port and 16#80#) /= 0 then
         if Visible then
            MF_Active := True;
            return (if (Last_7FFD and 8) /= 0 then 16#FF# else 16#7F#);
         end if;
      else
         MF_Active := False;
      end if;
      return 16#FF#;
   end MF_In;

   procedure MF_Out (Port : Word) is
   begin
      if MF_Active then
         Visible := (Port and 16#80#) /= 0;
      end if;
      Armed := True;
   end MF_Out;

   procedure MF_Reset (Hard : Boolean) is
   begin
      MF_Active := False;
      Pending := False;
      Armed := True;
      Visible := False;
      if Hard then
         MF_RAM := (others => 0);
      end if;
   end MF_Reset;

end Peripherals;
