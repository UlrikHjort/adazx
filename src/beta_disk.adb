with Ada.Exceptions;
-- ***************************************************************************
--                             AdaZX - Beta_Disk
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
with Ada.Characters.Handling;
with Ada.IO_Exceptions;
with Interfaces; use Interfaces;
with File_Ext;

package body Beta_Disk is

   package SIO renames Ada.Streams.Stream_IO;

   Sector_Size : constant := 256;
   Sectors : constant := 16;
   Track_Size : constant := Sectors * Sector_Size;

   ROM : Byte_Array (0 .. 16#3FFF#) := (others => 16#FF#);
   Have_ROM : Boolean := False;

   type Disc is record
      Present : Boolean := False;
      Data : Byte_Array_Access := null;
      Cyls : Natural := 80;
      Sides : Natural := 2;
      Path : Unbounded_String;
      Is_SCL : Boolean := False;
      Modified : Boolean := False;
      Protect : Boolean := False;
      Head : Natural := 0;            --  the head's cylinder
   end record;

   Drives : array (Drive_Number) of Disc;

   --  The sector IDs (C H R N) a Write Track put on a track, returned by
   --  Read Address (TR-DOS's FORMAT tells one side from two this way);
   --  tracks never formatted here give (cylinder, side, sector, 1)
   type ID_List is array (0 .. 15) of Byte_Array (0 .. 3);
   type Track_IDs is record
      Count : Natural := 0;
      IDs : ID_List;
   end record;
   Written_IDs : array (Drive_Number, 0 .. 83, 0 .. 1) of Track_IDs;
   Err : Unbounded_String;
   Used : Boolean := False;

   --  WD1793 state
   Track_R, Sector_R, Data_R : Byte := 0;
   Cmd : Byte := 0;
   Busy, DRQ, INTRQ : Boolean := False;
   Type_I : Boolean := True;          --  status shows the type I bits
   RNF, Lost, Seek_Err, Head_Loaded : Boolean := False;
   Cur : Drive_Number := 0;
   Side : Natural := 0;
   Step_Dir : Integer := 1;
   Next_ID : Natural := 1;            --  sector of the next Read Address

   type Transfer is (None, Reading, Writing_Sector, Writing_Track);
   Mode : Transfer := None;
   Buffer : Byte_Array (0 .. 6_399);
   Pos, Len : Natural := 0;
   Multi : Boolean := False;
   Cmd_Cycle : Long_Long_Integer := 0;   --  when the command started
   Now : Long_Long_Integer := 0;

   Index_Period : constant := 700_000;   --  300 rpm at 3.5 MHz
   Index_Width : constant := 14_000;

   ---------------------------------------------------------------------
   --  ROM and paging
   ---------------------------------------------------------------------

   procedure Load_ROM (Path : String; Ok : out Boolean) is
      F : SIO.File_Type;
      Buf : Stream_Element_Array (1 .. 16#4000#);
      Last : Stream_Element_Offset;
   begin
      Ok := False;
      SIO.Open (F, SIO.In_File, Path);
      SIO.Read (F, Buf, Last);
      SIO.Close (F);
      if Last < 16#4000# then
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
   function ROM_Byte (Addr : Word) return Byte is (ROM (Natural (Addr)));

   procedure Before_Fetch (Addr : Word; Basic48 : Boolean) is
   begin
      if not Enabled then
         return;
      end if;
      if Active then
         if Addr >= 16#4000# then
            Active := False;
         end if;
      elsif (Addr and 16#FF00#) = 16#3D00# and then Basic48 then
         Active := True;
      end if;
   end Before_Fetch;

   ---------------------------------------------------------------------
   --  Disc geometry
   ---------------------------------------------------------------------

   function Has_Disc return Boolean is (Drives (Cur).Present);

   --  Offset of a sector (1 .. 16) of the current drive, -1 if none
   function Offset (Cyl, Sd : Natural; Sec : Natural) return Integer is
      D : Disc renames Drives (Cur);
   begin
      if not D.Present or else Cyl >= D.Cyls or else Sd >= D.Sides
        or else Sec not in 1 .. Sectors
      then
         return -1;
      end if;
      return ((Cyl * D.Sides + Sd) * Sectors + Sec - 1) * Sector_Size;
   end Offset;

   procedure Set_Geometry (D : in out Disc; Kind : Byte; Size : Natural) is
   begin
      case Kind is
         when 16#16# => D.Cyls := 80; D.Sides := 2;
         when 16#17# => D.Cyls := 40; D.Sides := 2;
         when 16#18# => D.Cyls := 80; D.Sides := 1;
         when 16#19# => D.Cyls := 40; D.Sides := 1;
         when others =>
            D.Sides := 2;
            D.Cyls := Natural'Max (40, (Size + 2 * Track_Size - 1)
                                   / (2 * Track_Size));
      end case;
   end Set_Geometry;

   --  The disc information sector (track 0, sector 9) of an empty disc
   procedure Format_Info (Data : in out Byte_Array; Files, First_Free_Sec,
                          First_Free_Trk, Free : Natural; Label : String)
   is
      Base : constant Natural := Data'First + 8 * Sector_Size;
   begin
      Data (Base + 16#E1#) := Byte (First_Free_Sec);
      Data (Base + 16#E2#) := Byte (First_Free_Trk);
      Data (Base + 16#E3#) := 16#16#;            --  80 tracks, 2 sides
      Data (Base + 16#E4#) := Byte (Files);
      Data (Base + 16#E5#) := Byte (Free mod 256);
      Data (Base + 16#E6#) := Byte (Free / 256);
      Data (Base + 16#E7#) := 16#10#;            --  TR-DOS
      for I in 16#EA# .. 16#F2# loop
         Data (Base + I) := 16#20#;
      end loop;
      Data (Base + 16#F4#) := 0;                  --  deleted files
      for I in 0 .. 7 loop
         Data (Base + 16#F5# + I) :=
           (if I < Label'Length
            then Character'Pos (Label (Label'First + I)) else 16#20#);
      end loop;
   end Format_Info;

   ---------------------------------------------------------------------
   --  Images
   ---------------------------------------------------------------------

   function Read_File (Path : String; Ok : out Boolean) return Byte_Array is
      F : SIO.File_Type;
   begin
      SIO.Open (F, SIO.In_File, Path);
      declare
         N : constant Natural := Natural (SIO.Size (F));
         Buf : Stream_Element_Array (1 .. Stream_Element_Offset (N));
         Last : Stream_Element_Offset;
         R : Byte_Array (0 .. N - 1);
      begin
         SIO.Read (F, Buf, Last);
         SIO.Close (F);
         for I in R'Range loop
            R (I) := Byte (Buf (Stream_Element_Offset (I) + 1));
         end loop;
         Ok := True;
         return R;
      end;
   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Ok := False;
         return (1 .. 0 => 0);
   end Read_File;

   --  An .scl archive made into a TR-DOS disc
   procedure From_SCL (F : Byte_Array; D : in out Disc; Ok : out Boolean) is
      N : Natural;
      Hdr, Src : Natural;
      Trk : Natural := 1;            --  logical track (cylinder * 2 + side)
      Sec : Natural := 0;
      Used_Sectors : Natural := 0;
      Signature : constant String := "SINCLAIR";
   begin
      Ok := False;
      if F'Length < 9 then
         return;
      end if;
      for I in 0 .. 7 loop
         if F (F'First + I) /= Character'Pos (Signature (I + 1)) then
            return;
         end if;
      end loop;
      N := Natural (F (F'First + 8));
      if N > 128 or else F'Length < 9 + 14 * N then
         return;
      end if;
      D.Cyls := 80;
      D.Sides := 2;
      D.Data := new Byte_Array (0 .. 80 * 2 * Track_Size - 1);
      D.Data.all := (others => 0);
      Hdr := F'First + 9;
      Src := F'First + 9 + 14 * N;
      for K in 0 .. N - 1 loop
         declare
            H : constant Natural := Hdr + 14 * K;
            Count : constant Natural := Natural (F (H + 13));
            Cat : constant Natural := K * 16;
         begin
            D.Data (Cat .. Cat + 13) := F (H .. H + 13);
            D.Data (Cat + 14) := Byte (Sec);
            D.Data (Cat + 15) := Byte (Trk);
            for S in 0 .. Count - 1 loop
               declare
                  Dst : constant Natural :=
                    ((Trk * Sectors) + Sec) * Sector_Size;
               begin
                  if Src + Sector_Size - 1 <= F'Last
                    and then Dst + Sector_Size - 1 <= D.Data'Last
                  then
                     D.Data (Dst .. Dst + Sector_Size - 1) :=
                       F (Src .. Src + Sector_Size - 1);
                  end if;
                  Src := Src + Sector_Size;
                  Sec := Sec + 1;
                  if Sec = Sectors then
                     Sec := 0;
                     Trk := Trk + 1;
                  end if;
               end;
            end loop;
            Used_Sectors := Used_Sectors + Count;
         end;
      end loop;
      Format_Info (D.Data.all, N, Sec, Trk,
                   Natural'Max (0, 159 * Sectors - Used_Sectors), "SCL");
      Ok := True;
   end From_SCL;

   procedure Insert (Drive : Drive_Number; Path : String; Ok : out Boolean)
   is
      F : constant Byte_Array := Read_File (Path, Ok);
      D : Disc;
      E : constant String :=
        Ada.Characters.Handling.To_Lower (File_Ext.Of_Path (Path));
   begin
      if not Ok then
         Err := To_Unbounded_String ("cannot read " & Path);
         return;
      end if;
      if E = "scl" then
         From_SCL (F, D, Ok);
         D.Is_SCL := True;
         if not Ok then
            Err := To_Unbounded_String ("not an SCL archive: " & Path);
            return;
         end if;
      else
         if F'Length < 9 * Sector_Size or else F'Length mod Sector_Size /= 0
         then
            Ok := False;
            Err := To_Unbounded_String ("not a TRD disc image: " & Path);
            return;
         end if;
         Set_Geometry (D, F (F'First + 8 * Sector_Size + 16#E3#), F'Length);
         D.Data := new Byte_Array
           (0 .. Natural'Max (F'Length, D.Cyls * D.Sides * Track_Size) - 1);
         D.Data.all := (others => 0);
         D.Data (0 .. F'Length - 1) := F;
      end if;
      Eject (Drive);
      for C in 0 .. 83 loop
         for S in 0 .. 1 loop
            Written_IDs (Drive, C, S).Count := 0;
         end loop;
      end loop;
      D.Present := True;
      D.Path := To_Unbounded_String (Path);
      D.Head := Drives (Drive).Head;
      Drives (Drive) := D;
      Ok := True;
   end Insert;

   procedure Flush (Drive : Drive_Number) is
      D : Disc renames Drives (Drive);
      F : SIO.File_Type;
   begin
      if not D.Present or else not D.Modified or else D.Is_SCL then
         return;
      end if;
      declare
         Buf : Stream_Element_Array
           (1 .. Stream_Element_Offset (D.Data'Length));
      begin
         for I in D.Data'Range loop
            Buf (Stream_Element_Offset (I) + 1) := Stream_Element (D.Data (I));
         end loop;
         SIO.Create (F, SIO.Out_File, To_String (D.Path));
         SIO.Write (F, Buf);
         SIO.Close (F);
         D.Modified := False;
      end;
   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Err := To_Unbounded_String ("cannot write " & To_String (D.Path));
   end Flush;

   function Has_Boot (Drive : Drive_Number) return Boolean is
      D : Disc renames Drives (Drive);
      Boot : constant String := "boot    B";
   begin
      if not D.Present then
         return False;
      end if;
      for K in 0 .. 127 loop
         declare
            O : constant Natural := K * 16;
         begin
            exit when D.Data (O) = 0;           --  end of the catalogue
            if (for all I in 0 .. 8 =>
                  D.Data (O + I) = Character'Pos (Boot (I + 1)))
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Has_Boot;

   procedure Flush_All is
   begin
      for D in Drive_Number loop
         Flush (D);
      end loop;
   end Flush_All;

   procedure Eject (Drive : Drive_Number) is
   begin
      Flush (Drive);
      Drives (Drive).Present := False;
      Drives (Drive).Data := null;
      Drives (Drive).Path := Null_Unbounded_String;
   end Eject;

   function Name (Drive : Drive_Number) return String is
     (To_String (Drives (Drive).Path));

   procedure Create (Path : String; Ok : out Boolean) is
      Data : Byte_Array (0 .. 80 * 2 * Track_Size - 1) := (others => 0);
      F : SIO.File_Type;
   begin
      Format_Info (Data, 0, 0, 1, 159 * Sectors, "ADAZX");
      declare
         Buf : Stream_Element_Array (1 .. Stream_Element_Offset (Data'Length));
      begin
         for I in Data'Range loop
            Buf (Stream_Element_Offset (I) + 1) := Stream_Element (Data (I));
         end loop;
         SIO.Create (F, SIO.Out_File, Path);
         SIO.Write (F, Buf);
         SIO.Close (F);
      end;
      Ok := True;
   exception
      when E : Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Err := To_Unbounded_String
           ("cannot write " & Path & ": " &
            Ada.Exceptions.Exception_Message (E));
         Ok := False;
   end Create;

   function Error_Message return String is (To_String (Err));

   function Activity return Boolean is
      A : constant Boolean := Used;
   begin
      Used := False;
      return A;
   end Activity;

   ---------------------------------------------------------------------
   --  WD1793
   ---------------------------------------------------------------------

   procedure Finish is
   begin
      Busy := False;
      DRQ := False;
      Mode := None;
      INTRQ := True;
   end Finish;

   --  Load sector Sector_R of the current track into the buffer
   function Load_Sector return Boolean is
      D : Disc renames Drives (Cur);
      O : constant Integer := Offset (D.Head, Side, Natural (Sector_R));
   begin
      if O < 0 or else Natural (Track_R) /= D.Head then
         return False;
      end if;
      Buffer (0 .. Sector_Size - 1) := D.Data (O .. O + Sector_Size - 1);
      Pos := 0;
      Len := Sector_Size;
      Used := True;
      return True;
   end Load_Sector;

   procedure Store_Sector is
      D : Disc renames Drives (Cur);
      O : constant Integer := Offset (D.Head, Side, Natural (Sector_R));
   begin
      if O >= 0 then
         D.Data (O .. O + Sector_Size - 1) := Buffer (0 .. Sector_Size - 1);
         D.Modified := True;
         Used := True;
      end if;
   end Store_Sector;

   --  Write Track: the sectors in the stream (ID mark F5 .. FE C H R N,
   --  data mark F5 .. FB and the data)
   procedure Store_Track is
      D : Disc renames Drives (Cur);
      I : Natural := 1;
      Pending : Integer := -1;
      T : Track_IDs renames Written_IDs (Cur, Natural'Min (D.Head, 83), Side);
   begin
      if Len > 0 then
         T.Count := 0;
      end if;
      while I + 4 < Len loop
         if Buffer (I) = 16#FE# and then Buffer (I - 1) = 16#F5# then
            Pending := Integer (Buffer (I + 3));
            if T.Count < 16 then
               T.IDs (T.Count) := Buffer (I + 1 .. I + 4);
               T.Count := T.Count + 1;
            end if;
            I := I + 5;
         elsif Buffer (I) = 16#FB# and then Buffer (I - 1) = 16#F5#
           and then Pending >= 0
         then
            declare
               O : constant Integer := Offset (D.Head, Side, Pending);
            begin
               if O >= 0 and then I + Sector_Size <= Len then
                  D.Data (O .. O + Sector_Size - 1) :=
                    Buffer (I + 1 .. I + Sector_Size);
                  D.Modified := True;
               end if;
            end;
            Pending := -1;
            I := I + Sector_Size + 1;
         else
            I := I + 1;
         end if;
      end loop;
      Used := True;
   end Store_Track;

   procedure Command (V : Byte) is
      D : Disc renames Drives (Cur);
   begin
      Cmd := V;
      Cmd_Cycle := Now;
      INTRQ := False;
      if (V and 16#F0#) = 16#D0# then              --  Force Interrupt
         Busy := False;
         DRQ := False;
         Mode := None;
         Type_I := True;
         INTRQ := (V and 16#0F#) /= 0;
         return;
      end if;
      RNF := False;
      Lost := False;
      Seek_Err := False;
      if (V and 16#80#) = 0 then                   --  type I
         Type_I := True;
         Head_Loaded := (V and 8) /= 0;
         case Shift_Right (V, 5) is
            when 0 =>
               if (V and 16#10#) = 0 then           --  Restore
                  D.Head := 0;
                  Track_R := 0;
               else                                 --  Seek
                  if Data_R > Track_R then
                     Step_Dir := 1;
                  elsif Data_R < Track_R then
                     Step_Dir := -1;
                  end if;
                  D.Head := Natural'Min
                    (Natural'Max (Integer (D.Head) + Integer (Data_R)
                                  - Integer (Track_R), 0), 83);
                  Track_R := Data_R;
               end if;
            when others =>                          --  Step / In / Out
               if Shift_Right (V, 5) = 2 then
                  Step_Dir := 1;
               elsif Shift_Right (V, 5) = 3 then
                  Step_Dir := -1;
               end if;
               D.Head := Natural'Min
                 (Natural'Max (Integer (D.Head) + Step_Dir, 0), 83);
               if (V and 16#10#) /= 0 then
                  Track_R := Byte ((Integer (Track_R) + Step_Dir) mod 256);
               end if;
         end case;
         if D.Present and then (V and 4) /= 0
           and then Natural (Track_R) /= D.Head
         then
            Seek_Err := True;                       --  verify failed
         end if;
         Finish;
         return;
      end if;
      Type_I := False;
      if not Has_Disc then
         Finish;
         return;
      end if;
      case Shift_Right (V, 4) is
         when 8 | 9 =>                              --  Read Sector
            Multi := (V and 16#10#) /= 0;
            if Load_Sector then
               Mode := Reading;
               Busy := True;
               DRQ := True;
            else
               RNF := True;
               Finish;
            end if;
         when 16#A# | 16#B# =>                      --  Write Sector
            Multi := (V and 16#10#) /= 0;
            if D.Protect then
               Finish;
            elsif Offset (D.Head, Side, Natural (Sector_R)) < 0
              or else Natural (Track_R) /= D.Head
            then
               RNF := True;
               Finish;
            else
               Mode := Writing_Sector;
               Pos := 0;
               Len := Sector_Size;
               Busy := True;
               DRQ := True;
            end if;
         when 16#C# =>                              --  Read Address
            declare
               T : Track_IDs renames
                 Written_IDs (Cur, Natural'Min (D.Head, 83), Side);
            begin
               if T.Count > 0 then
                  Buffer (0 .. 3) := T.IDs ((Next_ID - 1) mod T.Count);
               else
                  Buffer (0 .. 3) := (Byte (D.Head), Byte (Side),
                                      Byte (Next_ID), 1);
               end if;
               Buffer (4 .. 5) := (0, 0);
               Sector_R := Buffer (0);
            end;
            Next_ID := Next_ID mod Sectors + 1;
            Pos := 0;
            Len := 6;
            Mode := Reading;
            Multi := False;
            Busy := True;
            DRQ := True;
         when 16#E# =>                              --  Read Track
            Len := 0;
            for S in 1 .. Sectors loop
               declare
                  O : constant Integer := Offset (D.Head, Side, S);
               begin
                  Buffer (Len .. Len + 6) := (16#FE#, Byte (D.Head),
                                              Byte (Side), Byte (S), 1, 0, 0);
                  Buffer (Len + 7) := 16#FB#;
                  if O >= 0 then
                     Buffer (Len + 8 .. Len + 7 + Sector_Size) :=
                       D.Data (O .. O + Sector_Size - 1);
                  end if;
                  Len := Len + 8 + Sector_Size;
               end;
            end loop;
            Pos := 0;
            Mode := Reading;
            Multi := False;
            Busy := True;
            DRQ := True;
         when 16#F# =>                              --  Write Track
            if D.Protect then
               Finish;
            else
               Mode := Writing_Track;
               Pos := 0;
               Len := 6_250;
               Busy := True;
               DRQ := True;
            end if;
         when others =>
            Finish;
      end case;
   end Command;

   function Read_Data return Byte is
      V : Byte;
   begin
      if Mode /= Reading then
         return Data_R;
      end if;
      V := Buffer (Pos);
      Pos := Pos + 1;
      Data_R := V;
      if Pos >= Len then
         if Multi then
            Sector_R := Sector_R + 1;
            if not Load_Sector then
               Finish;
            end if;
         else
            Finish;
         end if;
      end if;
      return V;
   end Read_Data;

   procedure Write_Data (V : Byte) is
   begin
      Data_R := V;
      case Mode is
         when Writing_Sector =>
            Buffer (Pos) := V;
            Pos := Pos + 1;
            if Pos >= Sector_Size then
               Store_Sector;
               if Multi and then Offset (Drives (Cur).Head, Side,
                                         Natural (Sector_R) + 1) >= 0
               then
                  Sector_R := Sector_R + 1;
                  Pos := 0;
               else
                  Finish;
               end if;
            end if;
         when Writing_Track =>
            Buffer (Pos) := V;
            Pos := Pos + 1;
            if Pos >= Len then
               Len := Pos;
               Store_Track;
               Finish;
            end if;
         when others => null;
      end case;
   end Write_Data;

   function Status (Cycle : Long_Long_Integer) return Byte is
      D : Disc renames Drives (Cur);
      S : Byte := 0;
      procedure Bit (N : Natural; On : Boolean) is
      begin
         if On then
            S := S or Shift_Left (1, N);
         end if;
      end Bit;
   begin
      Bit (0, Busy);
      Bit (7, not D.Present);
      if Type_I then
         Bit (1, D.Present and then Cycle mod Index_Period < Index_Width);
         Bit (2, D.Head = 0);
         Bit (4, Seek_Err);
         Bit (5, Head_Loaded);
         Bit (6, D.Present and then D.Protect);
      else
         Bit (1, DRQ);
         Bit (2, Lost);
         Bit (4, RNF);
         Bit (6, D.Present and then D.Protect
                 and then (Cmd and 16#E0#) = 16#A0#);
      end if;
      return S;
   end Status;

   function Port_Selected (Port : Word) return Boolean is
     (Enabled and then Active
      and then Lo (Port) in 16#1F# | 16#3F# | 16#5F# | 16#7F# | 16#FF#);

   --  Write Track ends at the next index pulse, with the data written so
   --  far (TR-DOS starts one at boot without writing anything)
   procedure Check_Track_End (Cycle : Long_Long_Integer) is
   begin
      if Mode = Writing_Track and then Cycle - Cmd_Cycle >= Index_Period then
         Lost := Pos < Len;
         Len := Pos;
         Store_Track;
         Finish;
      end if;
   end Check_Track_End;

   function Port_In (Port : Word; Cycle : Long_Long_Integer) return Byte is
   begin
      Now := Cycle;
      Check_Track_End (Cycle);
      case Lo (Port) is
         when 16#1F# =>
            INTRQ := False;
            return Status (Cycle);
         when 16#3F# => return Track_R;
         when 16#5F# => return Sector_R;
         when 16#7F# => return Read_Data;
         when others =>
            return (if INTRQ then 16#80# else 0)
              or (if DRQ then 16#40# else 0) or 16#3F#;
      end case;
   end Port_In;

   procedure Port_Out (Port : Word; Value : Byte; Cycle : Long_Long_Integer)
   is
   begin
      Now := Cycle;
      Check_Track_End (Cycle);
      case Lo (Port) is
         when 16#1F# => Command (Value);
         when 16#3F# => Track_R := Value;
         when 16#5F# => Sector_R := Value;
         when 16#7F# => Write_Data (Value);
         when others =>
            Cur := Drive_Number (Value and 3);
            Side := (if (Value and 16#10#) = 0 then 1 else 0);
            if (Value and 4) = 0 then           --  controller reset
               Busy := False;
               DRQ := False;
               Mode := None;
               Type_I := True;
               Cmd := 3;
            end if;
      end case;
   end Port_Out;

   procedure Reset is
   begin
      Active := False;
      Busy := False;
      DRQ := False;
      INTRQ := False;
      Mode := None;
      Type_I := True;
      Track_R := 0;
      Sector_R := 1;
      Data_R := 0;
      Cur := 0;
      Side := 0;
   end Reset;

end Beta_Disk;
