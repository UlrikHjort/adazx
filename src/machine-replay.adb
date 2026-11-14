with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;
with Ada.Characters.Handling;
with Interfaces; use Interfaces;
with Interfaces.C;
with System;

package body Machine.Replay is

   package SIO renames Ada.Streams.Stream_IO;
   use type Interfaces.C.int;

   Err : Unbounded_String;
   function Error_Message return String is (To_String (Err));

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

   package Byte_Vectors is new Ada.Containers.Vectors (Natural, Byte);

   type Frame is record
      Fetches : Natural;
      In_First : Natural;        --  index into Ins
      In_Count : Natural;
   end record;
   package Frame_Vectors is new Ada.Containers.Vectors (Natural, Frame);

   --  A part: an optional snapshot followed by input frames
   type Part is record
      Snap_Kind : Unbounded_String;
      Snap_First, Snap_Len : Natural := 0;     --  in Snaps
      T_Start : Natural := 0;
      First_Frame, Frame_Count : Natural := 0;
   end record;
   package Part_Vectors is new Ada.Containers.Vectors (Positive, Part);

   Parts : Part_Vectors.Vector;
   Frames : Frame_Vectors.Vector;
   Ins : Byte_Vectors.Vector;
   Snaps : Byte_Vectors.Vector;

   Cur_Part : Natural := 0;
   Cur_Frame : Natural := 0;       --  within the part
   In_Pos : Natural := 0;          --  within the frame
   Is_Playing : Boolean := False;

   function Playing return Boolean is (Is_Playing);

   procedure Stop_Playing is
   begin
      Is_Playing := False;
   end Stop_Playing;

   function L32 (D : Byte_Array; I : Natural) return Natural is
     (Natural (D (I)) + 256 * Natural (D (I + 1))
      + 65536 * Natural (D (I + 2)) + 16777216 * Natural (D (I + 3) and 127));
   function L16 (D : Byte_Array; I : Natural) return Natural is
     (Natural (D (I)) + 256 * Natural (D (I + 1)));

   function Inflate (Src : Byte_Array; Guess : Natural) return Byte_Array is
      Size : Natural := Natural'Max (Guess, 4096);
   begin
      for Attempt in 1 .. 8 loop
         declare
            Out_Buf : Byte_Array (0 .. Size - 1);
            Len : aliased Interfaces.C.unsigned_long :=
              Interfaces.C.unsigned_long (Size);
            R : constant Interfaces.C.int :=
              Z_Uncompress (Out_Buf'Address, Len'Access, Src'Address,
                            Interfaces.C.unsigned_long (Src'Length));
         begin
            if R = 0 then
               return Out_Buf (0 .. Natural (Len) - 1);
            elsif R /= -5 then       --  not "buffer too small"
               exit;
            end if;
         end;
         Size := Size * 4;
      end loop;
      raise Constraint_Error;
   end Inflate;

   procedure Open (Path : String; Ok : out Boolean) is
      F : SIO.File_Type;
   begin
      Parts.Clear;
      Frames.Clear;
      Ins.Clear;
      Snaps.Clear;
      Is_Playing := False;
      SIO.Open (F, SIO.In_File, Path);
      declare
         D : Byte_Array (0 .. Natural (SIO.Size (F)) - 1);
         P : Natural := 10;
         Pending : Part;
         Have_Snap : Boolean := False;
      begin
         Byte_Array'Read (SIO.Stream (F), D);
         SIO.Close (F);
         if D'Length < 10 or else D (0 .. 3) /= (82, 90, 88, 33) then  --  RZX!
            Err := To_Unbounded_String ("not an RZX file");
            Ok := False;
            return;
         end if;
         while P + 4 < D'Length loop
            declare
               Id : constant Byte := D (P);
               Len : constant Natural := L32 (D, P + 1);
            begin
               exit when Len < 5 or else P + Len > D'Length;
               if Id = 16#30# then
                  declare
                     Flags : constant Natural := L32 (D, P + 5);
                     Ext : String (1 .. 3);
                     U_Len : constant Natural := L32 (D, P + 13);
                     Raw : constant Byte_Array := D (P + 17 .. P + Len - 1);
                  begin
                     for K in 1 .. 3 loop
                        Ext (K) := Character'Val (D (P + 8 + K));
                     end loop;
                     if Flags mod 2 = 1 then
                        Err := To_Unbounded_String
                          ("RZX with an external snapshot file");
                        Ok := False;
                        return;
                     end if;
                     declare
                        Data : constant Byte_Array :=
                          (if (Flags / 2) mod 2 = 1 then Inflate (Raw, U_Len)
                           else Raw);
                     begin
                        Pending.Snap_Kind := To_Unbounded_String
                          (Ada.Characters.Handling.To_Lower (Ext));
                        Pending.Snap_First := Natural (Snaps.Length);
                        Pending.Snap_Len := Data'Length;
                        for B of Data loop
                           Snaps.Append (B);
                        end loop;
                        Have_Snap := True;
                     end;
                  end;
               elsif Id = 16#80# then
                  declare
                     N_Frames : constant Natural := L32 (D, P + 5);
                     Flags : constant Natural := L32 (D, P + 14);
                     Raw : constant Byte_Array := D (P + 18 .. P + Len - 1);
                     Data : constant Byte_Array :=
                       (if (Flags / 2) mod 2 = 1
                        then Inflate (Raw, N_Frames * 16 + 1024) else Raw);
                     Q : Natural := Data'First;
                     Last_First, Last_Count : Natural := 0;
                     Prt : Part := (if Have_Snap then Pending else (others => <>));
                  begin
                     Prt.T_Start := L32 (D, P + 10);
                     Prt.First_Frame := Natural (Frames.Length);
                     Prt.Frame_Count := N_Frames;
                     for K in 1 .. N_Frames loop
                        exit when Q + 3 > Data'Last;
                        declare
                           Fetch : constant Natural := L16 (Data, Q);
                           N_In : constant Natural := L16 (Data, Q + 2);
                        begin
                           Q := Q + 4;
                           if N_In = 16#FFFF# then       --  as the last frame
                              Frames.Append ((Fetch, Last_First, Last_Count));
                           else
                              Last_First := Natural (Ins.Length);
                              Last_Count := N_In;
                              for J in 0 .. N_In - 1 loop
                                 Ins.Append (Data (Q + J));
                              end loop;
                              Q := Q + N_In;
                              Frames.Append ((Fetch, Last_First, N_In));
                           end if;
                        end;
                     end loop;
                     Prt.Frame_Count := Natural (Frames.Length) - Prt.First_Frame;
                     Parts.Append (Prt);
                     Have_Snap := False;
                  end;
               end if;
               P := P + Len;
            end;
         end loop;
      end;
      Ok := not Parts.Is_Empty;
      if not Ok then
         Err := To_Unbounded_String ("no input recording in the RZX file");
         return;
      end if;
      Cur_Part := 1;
      Cur_Frame := 0;
      In_Pos := 0;
      Is_Playing := True;
   exception
      when others =>
         Ok := False;
         Err := To_Unbounded_String ("cannot read the RZX file " & Path);
   end Open;

   function Has_Snapshot return Boolean is
     (Is_Playing and then Parts (Cur_Part).Snap_Len > 0);
   function Snapshot_Kind return String is
     (To_String (Parts (Cur_Part).Snap_Kind));

   function Snapshot_Data return Byte_Array is
      P : constant Part := Parts (Cur_Part);
      R : Byte_Array (0 .. P.Snap_Len - 1);
   begin
      for K in R'Range loop
         R (K) := Snaps (P.Snap_First + K);
      end loop;
      return R;
   end Snapshot_Data;

   function Start_T return Natural is (Parts (Cur_Part).T_Start);

   function Current return Frame is
     (Frames (Parts (Cur_Part).First_Frame + Cur_Frame));

   function Frame_Fetches return Natural is
     (if Is_Playing then Current.Fetches else 0);

   function Next_In return Byte is
   begin
      if not Is_Playing then
         return 16#FF#;
      end if;
      declare
         Fr : constant Frame := Current;
      begin
         if In_Pos < Fr.In_Count then
            In_Pos := In_Pos + 1;
            return Ins (Fr.In_First + In_Pos - 1);
         end if;
         return 16#FF#;           --  more INs than recorded: out of step
      end;
   end Next_In;

   procedure Next_Frame (New_Part : out Boolean) is
   begin
      New_Part := False;
      In_Pos := 0;
      Cur_Frame := Cur_Frame + 1;
      if Cur_Frame >= Parts (Cur_Part).Frame_Count then
         Cur_Frame := 0;
         if Cur_Part < Natural (Parts.Length) then
            Cur_Part := Cur_Part + 1;
            New_Part := True;
         else
            Is_Playing := False;
         end if;
      end if;
   end Next_Frame;

   function Progress return String is
     (if not Is_Playing then ""
      else "RZX frame" & Natural'Image (Cur_Frame + 1) & " /" &
        Natural'Image (Parts (Cur_Part).Frame_Count));

   ---------------------------------------------------------------------
   --  Recording
   ---------------------------------------------------------------------

   Rec_On : Boolean := False;
   Rec_Snap : Byte_Vectors.Vector;
   Rec_Data : Byte_Vectors.Vector;     --  frames as written to the file
   Rec_Frame_Ins : Byte_Vectors.Vector;
   Rec_Frames : Natural := 0;
   Rec_T : Natural := 0;

   function Recording return Boolean is (Rec_On);

   procedure Start_Recording (Snapshot : Byte_Array; T_Start : Natural) is
   begin
      Rec_Snap.Clear;
      for B of Snapshot loop
         Rec_Snap.Append (B);
      end loop;
      Rec_Data.Clear;
      Rec_Frame_Ins.Clear;
      Rec_Frames := 0;
      Rec_T := T_Start;
      Rec_On := True;
   end Start_Recording;

   procedure Record_In (Value : Byte) is
   begin
      if Rec_On then
         Rec_Frame_Ins.Append (Value);
      end if;
   end Record_In;

   procedure Record_Frame (Fetches : Natural) is
      N : constant Natural := Natural (Rec_Frame_Ins.Length);
   begin
      if not Rec_On then
         return;
      end if;
      Rec_Data.Append (Byte (Fetches mod 256));
      Rec_Data.Append (Byte (Fetches / 256 mod 256));
      Rec_Data.Append (Byte (N mod 256));
      Rec_Data.Append (Byte (N / 256 mod 256));
      Rec_Data.Append (Rec_Frame_Ins);
      Rec_Frame_Ins.Clear;
      Rec_Frames := Rec_Frames + 1;
   end Record_Frame;

   function To_Array (V : Byte_Vectors.Vector) return Byte_Array is
      R : Byte_Array (0 .. Natural (V.Length) - 1);
   begin
      for K in R'Range loop
         R (K) := V (K);
      end loop;
      return R;
   end To_Array;

   function Deflate (D : Byte_Array) return Byte_Array is
      Out_Buf : Byte_Array (0 .. D'Length + D'Length / 100 + 1024);
      Len : aliased Interfaces.C.unsigned_long := Out_Buf'Length;
   begin
      if Z_Compress (Out_Buf'Address, Len'Access, D'Address,
                     Interfaces.C.unsigned_long (D'Length)) /= 0
      then
         raise Constraint_Error;
      end if;
      return Out_Buf (0 .. Natural (Len) - 1);
   end Deflate;

   function LE32 (N : Natural) return Byte_Array is
     (Byte (N mod 256), Byte (N / 256 mod 256), Byte (N / 65536 mod 256),
      Byte (N / 16777216 mod 256));

   procedure Stop_Recording (Path : String; Ok : out Boolean) is
      F : SIO.File_Type;
   begin
      Ok := True;
      if not Rec_On or else Path = "" then
         Rec_On := False;
         return;
      end if;
      Rec_On := False;
      declare
         Snap : constant Byte_Array := Deflate (To_Array (Rec_Snap));
         Input : constant Byte_Array := Deflate (To_Array (Rec_Data));
         Creator : Byte_Array (0 .. 28) := (others => 0);
         Name : constant String := "AdaZX";
      begin
         Creator (0) := 16#10#;
         Creator (1 .. 4) := LE32 (29);
         for K in Name'Range loop
            Creator (4 + K) := Character'Pos (Name (K));
         end loop;
         Creator (25) := 1;          --  version 1.0
         SIO.Create (F, SIO.Out_File, Path);
         Byte_Array'Write
           (SIO.Stream (F),
            Byte_Array'(82, 90, 88, 33, 0, 13) & LE32 (0) & Creator
            --  snapshot block: compressed .szx
            & Byte_Array'(1 => 16#30#) & LE32 (17 + Snap'Length) & LE32 (2)
            & Byte_Array'(115, 122, 120, 0)
            & LE32 (Natural (Rec_Snap.Length)) & Snap
            --  input recording block
            & Byte_Array'(1 => 16#80#) & LE32 (18 + Input'Length)
            & LE32 (Rec_Frames) & Byte_Array'(1 => 0) & LE32 (Rec_T)
            & LE32 (2) & Input);
         SIO.Close (F);
      end;
   exception
      when others =>
         Ok := False;
         Err := To_Unbounded_String ("cannot write " & Path);
   end Stop_Recording;

end Machine.Replay;
