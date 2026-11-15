with Ada.Streams.Stream_IO;
with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces; use Interfaces;

package body Interface_1 is

   package SIO renames Ada.Streams.Stream_IO;

   Block_Len : constant := 543;
   Head_Len  : constant := 15;
   Data_Len  : constant := 512;
   Max_Blocks : constant := 254;

   ROM : Byte_Array (0 .. 16#1FFF#) := (others => 16#FF#);
   Have_ROM : Boolean := False;
   Err : Unbounded_String;

   type Cartridge is record
      Inserted : Boolean := False;
      Path : Unbounded_String;
      Data : Byte_Array_Access := null;
      Blocks : Natural := 0;
      Write_Protect : Boolean := False;
      Modified : Boolean := False;
      --  preamble written / found, per header (0 ..) and data (256 ..)
      Formatted : Byte_Array (0 .. 511) := (others => 0);
      Motor : Boolean := False;
      Head : Natural := 0;
      Gap, Sync : Natural := 15;
      Transferred : Natural := 0;
      Max_Bytes : Natural := Head_Len;
      Last : Byte := 16#FF#;
   end record;

   Drives : array (Drive_Number) of Cartridge;
   Comms_Clk : Boolean := False;

   function Error_Message return String is (To_String (Err));
   function ROM_Loaded return Boolean is (Have_ROM);
   function ROM_Byte (Addr : Word) return Byte is
     (ROM (Natural (Addr and 16#1FFF#)));

   procedure Load_ROM (Path : String; Ok : out Boolean) is
      F : SIO.File_Type;
   begin
      SIO.Open (F, SIO.In_File, Path);
      Byte_Array'Read (SIO.Stream (F), ROM);
      SIO.Close (F);
      Have_ROM := True;
      Ok := True;
   exception
      when others =>
         Ok := False;
         Err := To_Unbounded_String ("cannot read " & Path);
   end Load_ROM;

   procedure Reset is
   begin
      Paged := False;
      Comms_Clk := False;
      for D of Drives loop
         D.Motor := False;
         D.Head := 0;
         D.Gap := 15;
         D.Sync := 15;
         D.Transferred := 0;
      end loop;
   end Reset;

   function Port_Selected (Port : Word) return Boolean is
     (Enabled and then (Port and 1) = 1 and then (Port and 16#18#) /= 16#18#);

   function Motor_On return Boolean is
     (for some D of Drives => D.Motor and then D.Inserted);

   procedure Advance (D : in out Cartridge) is
   begin
      D.Head := D.Head + 1;
      if D.Head >= D.Blocks * Block_Len then
         D.Head := 0;
      end if;
   end Advance;

   --  Every control port access: the head moves to the start of the
   --  record it is in, and the transfer count starts again
   procedure Restart is
   begin
      for D of Drives loop
         if D.Inserted and then D.Blocks > 0 then
            while D.Head mod Block_Len /= 0
              and then D.Head mod Block_Len /= Head_Len
            loop
               Advance (D);
            end loop;
         end if;
         D.Transferred := 0;
         D.Max_Bytes := (if D.Head mod Block_Len = 0 then Head_Len
                         else Head_Len + Data_Len + 1);
      end loop;
   end Restart;

   function Record_Index (D : Cartridge) return Natural is
     (D.Head / Block_Len + (if D.Max_Bytes = Head_Len then 0 else 256));

   Sync_OK : constant Byte := 16#FF#;

   function Port_In (Port : Word) return Byte is
      Ret : Byte := 16#FF#;
   begin
      case Port and 16#18# is
         when 16#00# =>                       --  &E7: data
            for D of Drives loop
               if D.Motor and then D.Inserted then
                  if D.Transferred < D.Max_Bytes then
                     D.Last := D.Data (D.Head);
                     Advance (D);
                  end if;
                  D.Transferred := D.Transferred + 1;
                  Ret := Ret and D.Last;
               end if;
            end loop;
         when 16#08# =>                       --  &EF: status
            for D of Drives loop
               if D.Motor and then D.Inserted then
                  if D.Formatted (Record_Index (D)) = Sync_OK then
                     if D.Gap > 0 then
                        D.Gap := D.Gap - 1;
                     else
                        Ret := Ret and 16#F9#;  --  GAP and SYNC low
                        if D.Sync > 0 then
                           D.Sync := D.Sync - 1;
                        else
                           D.Gap := 15;
                           D.Sync := 15;
                        end if;
                     end if;
                  end if;
                  if D.Write_Protect then
                     Ret := Ret and 16#FE#;
                  end if;
               end if;
            end loop;
            Ret := Ret and 16#E7#;            --  DTR and BUSY low
            Restart;
         when others =>                       --  &F7: network / RS232
            null;
      end case;
      return Ret;
   end Port_In;

   procedure Port_Out (Port : Word; Value : Byte) is
   begin
      case Port and 16#18# is
         when 16#00# =>                       --  &E7: write a byte
            for D of Drives loop
               if D.Motor and then D.Inserted then
                  declare
                     R : constant Natural := Record_Index (D);
                  begin
                     --  10 zeros and 2 &FF bytes: the preamble
                     if D.Transferred = 0 and then Value = 0 then
                        D.Formatted (R) := 1;
                     elsif D.Transferred in 1 .. 9 and then Value = 0 then
                        D.Formatted (R) := D.Formatted (R) + 1;
                     elsif D.Transferred in 10 .. 11 and then Value = 16#FF#
                     then
                        D.Formatted (R) := D.Formatted (R) + 1;
                     elsif D.Transferred = 12 and then D.Formatted (R) = 12
                     then
                        D.Formatted (R) := Sync_OK;
                     end if;
                     if D.Transferred > 11
                       and then D.Transferred < D.Max_Bytes + 12
                     then
                        D.Data (D.Head) := Value;
                        Advance (D);
                        D.Modified := True;
                     end if;
                     D.Transferred := D.Transferred + 1;
                  end;
               end if;
            end loop;
         when 16#08# =>                       --  &EF: control
            --  falling edge of COMMS CLK shifts the motor selection
            if (Value and 2) = 0 and then Comms_Clk then
               for K in reverse 2 .. 8 loop
                  Drives (K).Motor := Drives (K - 1).Motor;
               end loop;
               Drives (1).Motor := (Value and 1) = 0;
            end if;
            Comms_Clk := (Value and 2) /= 0;
            Restart;
         when others =>
            null;
      end case;
   end Port_Out;

   ---------------------------------------------------------------------
   --  Cartridges
   ---------------------------------------------------------------------

   procedure Write_Cartridge (D : Cartridge; Path : String;
                              Ok : out Boolean) is
      F : SIO.File_Type;
   begin
      SIO.Create (F, SIO.Out_File, Path);
      Byte_Array'Write (SIO.Stream (F), D.Data (0 .. D.Blocks * Block_Len - 1));
      Byte'Write (SIO.Stream (F), (if D.Write_Protect then 1 else 0));
      SIO.Close (F);
      Ok := True;
   exception
      when others =>
         Ok := False;
         Err := To_Unbounded_String ("cannot write " & Path);
   end Write_Cartridge;

   procedure Flush (N : Drive_Number) is
      Ok : Boolean;
   begin
      if Drives (N).Inserted and then Drives (N).Modified then
         Write_Cartridge (Drives (N), To_String (Drives (N).Path), Ok);
         if Ok then
            Drives (N).Modified := False;
         end if;
      end if;
   end Flush;

   procedure Flush_All is
   begin
      for N in Drive_Number loop
         Flush (N);
      end loop;
   end Flush_All;

   procedure Eject (Drive : Drive_Number) is
   begin
      Flush (Drive);
      Drives (Drive) := (others => <>);
   end Eject;

   procedure Insert (Drive : Drive_Number; Path : String; Ok : out Boolean)
   is
      F : SIO.File_Type;
   begin
      Eject (Drive);
      SIO.Open (F, SIO.In_File, Path);
      declare
         Size : constant Natural := Natural (SIO.Size (F));
         Blocks : constant Natural := Natural'Min (Size / Block_Len, Max_Blocks);
         D : Cartridge;
      begin
         if Blocks = 0 then
            SIO.Close (F);
            Ok := False;
            Err := To_Unbounded_String ("not a Microdrive cartridge (.mdr)");
            return;
         end if;
         D.Data := new Byte_Array (0 .. Max_Blocks * Block_Len - 1);
         D.Data.all := (others => 16#FF#);
         Byte_Array'Read (SIO.Stream (F), D.Data (0 .. Blocks * Block_Len - 1));
         if Size > Blocks * Block_Len then
            declare
               WP : Byte;
            begin
               Byte'Read (SIO.Stream (F), WP);
               D.Write_Protect := WP /= 0;
            end;
         end if;
         SIO.Close (F);
         D.Blocks := Blocks;
         D.Inserted := True;
         D.Path := To_Unbounded_String (Path);
         for B in 0 .. Blocks - 1 loop
            D.Formatted (B) := Sync_OK;
            D.Formatted (256 + B) := Sync_OK;
         end loop;
         Drives (Drive) := D;
         Ok := True;
      end;
   exception
      when others =>
         Ok := False;
         Err := To_Unbounded_String ("cannot read " & Path);
   end Insert;

   function Name (Drive : Drive_Number) return String is
     (if Drives (Drive).Inserted
      then Ada.Directories.Simple_Name (To_String (Drives (Drive).Path))
      else "");

   procedure Create (Path : String; Ok : out Boolean) is
      D : Cartridge;
   begin
      D.Blocks := 180;
      D.Data := new Byte_Array'(0 .. Max_Blocks * Block_Len - 1 => 16#FF#);
      Write_Cartridge (D, Path, Ok);
   end Create;

end Interface_1;
