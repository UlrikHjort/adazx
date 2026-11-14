with Interfaces; use Interfaces;
with DSK; use DSK;

package body FDC765 is

   type Phase_Type is (Command_Phase, Exec_Read, Exec_Write, Result_Phase);
   Phase : Phase_Type := Command_Phase;

   Cmd : Byte_Array (0 .. 8) := (others => 0);
   Cmd_Len, Cmd_Got : Natural := 0;
   Res : Byte_Array (0 .. 6) := (others => 0);
   Res_Len, Res_Pos : Natural := 0;

   Cyl : array (Drive) of Natural := (others => 0);   --  head position
   Rotation : array (Drive) of Natural := (others => 0);
   Seek_Done : array (Drive) of Boolean := (others => False);

   --  The transfer in progress
   Unit : Drive := 0;
   Head : Natural := 0;
   C, H, R, N, EOT : Byte := 0;
   Sec : Integer := -1;            --  sector index on the track
   Pos, Len : Natural := 0;        --  within the sector
   ST0, ST1, ST2 : Byte := 0;
   Code : Natural := 0;            --  command (low 5 bits)
   Multi_Track : Boolean := False;
   Format_IDs : ID_List (1 .. Max_Sectors);
   Format_Count, Format_Got : Natural := 0;
   Filler : Byte := 16#E5#;

   function Active return Boolean is (Phase /= Command_Phase);

   procedure Reset is
   begin
      Phase := Command_Phase;
      Cmd_Got := 0;
      Cmd_Len := 0;
      Seek_Done := (others => False);
   end Reset;

   function Params (Code : Natural) return Natural is
     (case Code is
         when 16#02# | 16#05# | 16#06# | 16#09# | 16#0C# | 16#11# | 16#19#
            | 16#1D# => 9,
         when 16#03# | 16#0F# => 3,
         when 16#04# | 16#07# | 16#0A# => 2,
         when 16#0D# => 6,
         when others => 1);

   function Drive_Ready (D : Drive) return Boolean is (Present (D));

   procedure Results (B : Byte_Array) is
   begin
      Res (0 .. B'Length - 1) := B;
      Res_Len := B'Length;
      Res_Pos := 0;
      Phase := Result_Phase;
   end Results;

   function Base_ST0 return Byte is
     (Byte (Unit) or (if Head = 1 then 4 else 0));

   procedure Finish (Abnormal : Boolean) is
   begin
      ST0 := Base_ST0 or (if Abnormal then 16#40# else 0);
      Results ((ST0, ST1, ST2, C, H, R, N));
   end Finish;

   --  Find sector R on the current track (two revolutions), set Sec / Len
   function Locate return Boolean is
   begin
      Sec := Find (Unit, Cyl (Unit), Head, C, H, R, N);
      if Sec < 0 then
         ST1 := ST1 or 16#04#;          --  no data
         if Sector_Count (Unit, Cyl (Unit), Head) = 0 then
            ST1 := ST1 or 16#01#;       --  missing address mark
         end if;
         return False;
      end if;
      Pos := 0;
      Len := 128 * 2 ** Natural (N and 7);
      return True;
   end Locate;

   procedure Start_Sector is
      S1, S2 : Byte;
   begin
      if not Locate then
         Finish (True);
         return;
      end if;
      Sector_Status (Unit, Cyl (Unit), Head, Sec, S1, S2);
      --  error flags recorded on the disc (copy protection)
      ST1 := ST1 or (S1 and 16#25#);
      ST2 := ST2 or (S2 and 16#61#);
      if Code = 16#06# and then (S2 and 16#40#) /= 0 then
         null;          --  deleted data read by "read data": CM reported
      end if;
      Rotation (Unit) := Sec + 1;
   end Start_Sector;

   --  After a sector: the next one, or the end of the command
   procedure Next_Sector is
   begin
      if (ST1 and 16#25#) /= 0 or else (ST2 and 16#61#) /= 0 then
         Finish (True);            --  stop at a sector with errors
         return;
      end if;
      if R = EOT then
         if Multi_Track and then Head = 0 then
            Head := 1;
            H := 1;
            R := 1;
         else
            --  no terminal count on the +3: "end of cylinder"
            ST1 := ST1 or 16#80#;
            R := R + 1;
            Finish (True);
            return;
         end if;
      else
         R := R + 1;
      end if;
      Start_Sector;
   end Next_Sector;

   procedure Execute is
   begin
      Code := Natural (Cmd (0) and 16#1F#);
      Multi_Track := (Cmd (0) and 16#80#) /= 0;
      if Cmd_Len > 1 then
         Unit := Drive (Cmd (1) and 1);
         Head := Natural (Shift_Right (Cmd (1), 2) and 1);
      end if;
      ST1 := 0;
      ST2 := 0;
      case Code is
         when 16#03# =>                       --  specify
            Phase := Command_Phase;
         when 16#04# =>                       --  sense drive status
            Results ((1 => Byte (Unit) or (if Head = 1 then 4 else 0)
                     or (if Drive_Ready (Unit) then 16#20# else 0)
                     or (if Cyl (Unit) = 0 then 16#10# else 0)
                     or (if Present (Unit) and then Write_Protected (Unit)
                         then 16#40# else 0)
                     or (if Present (Unit) and then Sides (Unit) > 1
                         then 16#08# else 0)));
         when 16#07# | 16#0F# =>              --  recalibrate / seek
            Cyl (Unit) := (if Code = 16#07# then 0 else Natural (Cmd (2)));
            Seek_Done (Unit) := True;
            Phase := Command_Phase;
         when 16#08# =>                       --  sense interrupt status
            declare
               Found : Boolean := False;
            begin
               for D in Drive loop
                  if Seek_Done (D) then
                     Seek_Done (D) := False;
                     Results ((16#20# or Byte (D)
                               or (if Drive_Ready (D) then 0 else 16#48#),
                               Byte (Cyl (D))));
                     Found := True;
                     exit;
                  end if;
               end loop;
               if not Found then
                  Results ((1 => 16#80#));
               end if;
            end;
         when 16#0A# =>                       --  read ID
            if not Drive_Ready (Unit) then
               ST0 := Base_ST0 or 16#48#;
               Results ((ST0, 0, 0, 0, 0, 0, 0));
            elsif Sector_Count (Unit, Cyl (Unit), Head) = 0 then
               ST0 := Base_ST0 or 16#40#;
               Results ((ST0, 16#01#, 0, 0, 0, 0, 0));
            else
               declare
                  Count : constant Natural :=
                    Sector_Count (Unit, Cyl (Unit), Head);
                  I : constant Natural := Rotation (Unit) mod Count;
               begin
                  Sector_ID (Unit, Cyl (Unit), Head, I, C, H, R, N);
                  Rotation (Unit) := I + 1;
                  Results ((Base_ST0, 0, 0, C, H, R, N));
               end;
            end if;
         when 16#06# | 16#0C# | 16#02# | 16#05# | 16#09# =>
            C := Cmd (2);
            H := Cmd (3);
            R := Cmd (4);
            N := Cmd (5);
            EOT := Cmd (6);
            if not Drive_Ready (Unit) then
               ST0 := Base_ST0 or 16#48#;
               Results ((ST0, ST1, ST2, C, H, R, N));
               return;
            end if;
            if Code = 16#02# then
               --  read track: the sectors in their order on the track
               if Sector_Count (Unit, Cyl (Unit), Head) = 0 then
                  ST1 := 16#01#;
                  Finish (True);
                  return;
               end if;
               declare
                  CC, HH, RR, NN : Byte;
               begin
                  Sector_ID (Unit, Cyl (Unit), Head, 0, CC, HH, RR, NN);
                  R := RR;
                  C := CC;
                  H := HH;
                  N := NN;
               end;
            end if;
            if (Code = 16#05# or else Code = 16#09#)
              and then Write_Protected (Unit)
            then
               ST1 := 16#02#;
               Finish (True);
               return;
            end if;
            Start_Sector;
            if Phase /= Result_Phase then
               Phase := (if Code in 16#05# | 16#09# then Exec_Write
                         else Exec_Read);
            end if;
         when 16#0D# =>                       --  format track
            N := Cmd (2);
            Format_Count := Natural'Min (Natural (Cmd (3)), Max_Sectors);
            Filler := Cmd (5);
            Format_Got := 0;
            if not Drive_Ready (Unit) or else Write_Protected (Unit) then
               ST1 := (if Drive_Ready (Unit) then 16#02# else 0);
               ST0 := Base_ST0 or 16#40#
                 or (if Drive_Ready (Unit) then 0 else 16#08#);
               Results ((ST0, ST1, 0, 0, 0, 0, N));
            else
               Pos := 0;
               Phase := Exec_Write;
            end if;
         when others =>
            Results ((1 => 16#80#));          --  invalid command
      end case;
   end Execute;

   function Read_Status return Byte is
   begin
      case Phase is
         when Command_Phase =>
            return 16#80#                      --  RQM, CPU to FDC
              or (if Cmd_Got > 0 then 16#10# else 0);
         when Exec_Read => return 16#F0#;      --  RQM DIO EXM CB
         when Exec_Write => return 16#B0#;     --  RQM EXM CB
         when Result_Phase => return 16#D0#;   --  RQM DIO CB
      end case;
   end Read_Status;

   function Read_Data return Byte is
   begin
      case Phase is
         when Result_Phase =>
            declare
               V : constant Byte := Res (Res_Pos);
            begin
               Res_Pos := Res_Pos + 1;
               if Res_Pos >= Res_Len then
                  Phase := Command_Phase;
               end if;
               return V;
            end;
         when Exec_Read =>
            declare
               V : constant Byte := Get (Unit, Cyl (Unit), Head, Sec, Pos);
            begin
               Pos := Pos + 1;
               if Pos >= Len then
                  Next_Sector;
               end if;
               return V;
            end;
         when others =>
            return 16#FF#;
      end case;
   end Read_Data;

   procedure Write_Data (V : Byte) is
   begin
      case Phase is
         when Command_Phase =>
            if Cmd_Got = 0 then
               Cmd_Len := Params (Natural (V and 16#1F#));
            end if;
            Cmd (Cmd_Got) := V;
            Cmd_Got := Cmd_Got + 1;
            if Cmd_Got >= Cmd_Len then
               Cmd_Got := 0;
               Execute;
            end if;
         when Exec_Write =>
            if Code = 16#0D# then
               --  format: C, H, R, N per sector
               declare
                  K : constant Natural := Format_Got / 4 + 1;
               begin
                  case Format_Got mod 4 is
                     when 0 => Format_IDs (K).C := V;
                     when 1 => Format_IDs (K).H := V;
                     when 2 => Format_IDs (K).R := V;
                     when others => Format_IDs (K).N := V;
                  end case;
                  Format_Got := Format_Got + 1;
                  if Format_Got >= 4 * Format_Count then
                     Format_Track (Unit, Cyl (Unit), Head,
                                   Format_IDs (1 .. Format_Count), Filler);
                     Results ((Base_ST0, 0, 0, C, H, R, N));
                  end if;
               end;
            else
               Put (Unit, Cyl (Unit), Head, Sec, Pos, V);
               Pos := Pos + 1;
               if Pos >= Len then
                  Next_Sector;
               end if;
            end if;
         when others =>
            null;
      end case;
   end Write_Data;

end FDC765;
