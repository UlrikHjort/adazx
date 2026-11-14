with Ada.Streams.Stream_IO;
with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces; use Interfaces;

package body DSK is

   package SIO renames Ada.Streams.Stream_IO;

   type Sector is record
      C, H, R, N : Byte := 0;
      ST1, ST2 : Byte := 0;
      Data : Byte_Array_Access := null;
   end record;
   type Sector_Array is array (0 .. Max_Sectors - 1) of Sector;

   type Track is record
      Count : Natural := 0;
      Sectors : Sector_Array;
   end record;

   Max_Cyl : constant := 84;
   type Track_Array is array (0 .. Max_Cyl - 1, 0 .. 1) of Track;
   type Track_Access is access Track_Array;

   type Disc is record
      Present : Boolean := False;
      Path : Unbounded_String;
      Cyls : Natural := 0;
      Sides : Natural := 1;
      Tracks : Track_Access := null;
      Dirty : Boolean := False;
      Read_Only : Boolean := False;
   end record;

   Discs : array (Drive) of Disc;
   Err : Unbounded_String;

   function Error_Message return String is (To_String (Err));
   function Present (D : Drive) return Boolean is (Discs (D).Present);
   function Name (D : Drive) return String is
     (if Discs (D).Present
      then Ada.Directories.Simple_Name (To_String (Discs (D).Path)) else "");
   function Write_Protected (D : Drive) return Boolean is
     (Discs (D).Read_Only);
   function Sides (D : Drive) return Natural is (Discs (D).Sides);

   function Valid (D : Drive; Cyl, Head : Natural) return Boolean is
     (Discs (D).Present and then Cyl < Max_Cyl and then Head <= 1);

   function Sector_Count (D : Drive; Cyl, Head : Natural) return Natural is
     (if Valid (D, Cyl, Head) then Discs (D).Tracks (Cyl, Head).Count else 0);

   procedure Sector_ID (D : Drive; Cyl, Head, Index : Natural;
                        C, H, R, N : out Byte) is
      S : Sector renames Discs (D).Tracks (Cyl, Head).Sectors (Index);
   begin
      C := S.C;
      H := S.H;
      R := S.R;
      N := S.N;
   end Sector_ID;

   procedure Sector_Status (D : Drive; Cyl, Head, Index : Natural;
                            ST1, ST2 : out Byte) is
      S : Sector renames Discs (D).Tracks (Cyl, Head).Sectors (Index);
   begin
      ST1 := S.ST1;
      ST2 := S.ST2;
   end Sector_Status;

   function Sector_Length (D : Drive; Cyl, Head, Index : Natural)
                           return Natural is
      S : Sector renames Discs (D).Tracks (Cyl, Head).Sectors (Index);
   begin
      return (if S.Data = null then 0 else S.Data'Length);
   end Sector_Length;

   function Find (D : Drive; Cyl, Head : Natural; C, H, R, N : Byte)
                  return Integer is
   begin
      if not Valid (D, Cyl, Head) then
         return -1;
      end if;
      declare
         T : Track renames Discs (D).Tracks (Cyl, Head);
      begin
         for I in 0 .. T.Count - 1 loop
            if T.Sectors (I).C = C and then T.Sectors (I).H = H
              and then T.Sectors (I).R = R and then T.Sectors (I).N = N
            then
               return I;
            end if;
         end loop;
      end;
      return -1;
   end Find;

   function Get (D : Drive; Cyl, Head, Index, Offset : Natural) return Byte
   is
      S : Sector renames Discs (D).Tracks (Cyl, Head).Sectors (Index);
   begin
      if S.Data = null or else S.Data'Length = 0 then
         return 16#E5#;
      end if;
      --  a sector shorter than its size code repeats (weak / short sectors)
      return S.Data (S.Data'First + Offset mod S.Data'Length);
   end Get;

   procedure Put (D : Drive; Cyl, Head, Index, Offset : Natural; V : Byte) is
      S : Sector renames Discs (D).Tracks (Cyl, Head).Sectors (Index);
   begin
      if S.Data /= null and then Offset < S.Data'Length then
         S.Data (S.Data'First + Offset) := V;
         Discs (D).Dirty := True;
      end if;
   end Put;

   procedure Format_Track (D : Drive; Cyl, Head : Natural; IDs : ID_List;
                           Filler : Byte) is
   begin
      if not Valid (D, Cyl, Head) then
         return;
      end if;
      declare
         T : Track renames Discs (D).Tracks (Cyl, Head);
      begin
         T.Count := Natural'Min (IDs'Length, Max_Sectors);
         for I in 0 .. T.Count - 1 loop
            declare
               F : constant ID_Field := IDs (IDs'First + I);
               Size : constant Natural := 128 * 2 ** Natural (F.N and 7);
            begin
               T.Sectors (I) := (F.C, F.H, F.R, F.N, 0, 0,
                                 new Byte_Array'(0 .. Size - 1 => Filler));
            end;
         end loop;
      end;
      if Cyl + 1 > Discs (D).Cyls then
         Discs (D).Cyls := Cyl + 1;
      end if;
      if Head + 1 > Discs (D).Sides then
         Discs (D).Sides := Head + 1;
      end if;
      Discs (D).Dirty := True;
   end Format_Track;

   ---------------------------------------------------------------------
   --  Reading and writing images
   ---------------------------------------------------------------------

   function Starts (D : Byte_Array; S : String) return Boolean is
     (D'Length >= S'Length
      and then (for all K in S'Range =>
                  Character'Val (D (D'First + K - S'First)) = S (K)));

   procedure Parse (Img : Byte_Array; Disc_Rec : in out Disc;
                    Ok : out Boolean) is
      Extended : constant Boolean := Starts (Img, "EXTENDED");
      Cyls : constant Natural := Natural (Img (16#30#));
      Sides : constant Natural := Natural'Max (1, Natural (Img (16#31#)));
      Std_Size : constant Natural :=
        Natural (Img (16#32#)) + 256 * Natural (Img (16#33#));
      P : Natural := 256;
   begin
      Ok := Extended or else Starts (Img, "MV - CPC");
      if not Ok then
         Err := To_Unbounded_String ("not a CPC / +3 .dsk image");
         return;
      end if;
      Disc_Rec.Tracks := new Track_Array;
      Disc_Rec.Cyls := Natural'Min (Cyls, Max_Cyl);
      Disc_Rec.Sides := Natural'Min (Sides, 2);
      for Cyl in 0 .. Cyls - 1 loop
         for Side in 0 .. Sides - 1 loop
            declare
               Size : constant Natural :=
                 (if Extended
                  then 256 * Natural (Img (16#34# + Cyl * Sides + Side))
                  else Std_Size);
            begin
               if Size > 0 and then P + 256 <= Img'Length
                 and then Starts (Img (P .. Img'Last), "Track-Info")
                 and then Cyl < Max_Cyl and then Side <= 1
               then
                  declare
                     T : Track renames Disc_Rec.Tracks (Cyl, Side);
                     N_Sectors : constant Natural :=
                       Natural'Min (Natural (Img (P + 16#15#)), Max_Sectors);
                     Track_N : constant Natural := Natural (Img (P + 16#14#));
                     Data : Natural := P + 256;
                  begin
                     T.Count := N_Sectors;
                     for I in 0 .. N_Sectors - 1 loop
                        declare
                           Info : constant Natural := P + 16#18# + 8 * I;
                           N : constant Byte := Img (Info + 3);
                           Len : Natural :=
                             (if Extended
                              then Natural (Img (Info + 6))
                                + 256 * Natural (Img (Info + 7))
                              else 128 * 2 ** Natural'Min (Track_N, 6));
                        begin
                           if Len = 0 and then not Extended then
                              Len := 128 * 2 ** Natural (N and 7);
                           end if;
                           Len := Natural'Min (Len, Img'Length - Data);
                           T.Sectors (I) :=
                             (Img (Info), Img (Info + 1), Img (Info + 2), N,
                              Img (Info + 4), Img (Info + 5),
                              new Byte_Array'(Img (Data .. Data + Len - 1)));
                           Data := Data + Len;
                        end;
                     end loop;
                  end;
               end if;
               P := P + Size;
            end;
         end loop;
      end loop;
   end Parse;

   procedure Insert (D : Drive; Path : String; Ok : out Boolean) is
      F : SIO.File_Type;
   begin
      Eject (D);
      SIO.Open (F, SIO.In_File, Path);
      declare
         Img : Byte_Array (0 .. Natural (SIO.Size (F)) - 1);
         New_Disc : Disc;
      begin
         Byte_Array'Read (SIO.Stream (F), Img);
         SIO.Close (F);
         if Img'Length < 256 then
            Ok := False;
            Err := To_Unbounded_String ("not a .dsk image");
            return;
         end if;
         Parse (Img, New_Disc, Ok);
         if Ok then
            New_Disc.Present := True;
            New_Disc.Path := To_Unbounded_String (Path);
            begin
               SIO.Open (F, SIO.Append_File, Path);
               SIO.Close (F);
            exception
               when others => New_Disc.Read_Only := True;
            end;
            Discs (D) := New_Disc;
         end if;
      end;
   exception
      when others =>
         Ok := False;
         Err := To_Unbounded_String ("cannot read " & Path);
   end Insert;

   procedure Write_Image (Disc_Rec : Disc; Path : String; Ok : out Boolean) is
      F : SIO.File_Type;
      Header : Byte_Array (0 .. 255) := (others => 0);
      Sig : constant String := "EXTENDED CPC DSK File" & ASCII.CR & ASCII.LF
        & "Disk-Info" & ASCII.CR & ASCII.LF;
      Creator : constant String := "AdaZX";
   begin
      for K in Sig'Range loop
         Header (K - 1) := Character'Pos (Sig (K));
      end loop;
      for K in Creator'Range loop
         Header (16#22# + K - 1) := Character'Pos (Creator (K));
      end loop;
      Header (16#30#) := Byte (Disc_Rec.Cyls);
      Header (16#31#) := Byte (Disc_Rec.Sides);
      for Cyl in 0 .. Disc_Rec.Cyls - 1 loop
         for Side in 0 .. Disc_Rec.Sides - 1 loop
            declare
               T : Track renames Disc_Rec.Tracks (Cyl, Side);
               Size : Natural := 0;
            begin
               if T.Count > 0 then
                  Size := 256;
                  for I in 0 .. T.Count - 1 loop
                     Size := Size + T.Sectors (I).Data'Length;
                  end loop;
                  Size := (Size + 255) / 256 * 256;
               end if;
               Header (16#34# + Cyl * Disc_Rec.Sides + Side) :=
                 Byte (Size / 256);
            end;
         end loop;
      end loop;
      SIO.Create (F, SIO.Out_File, Path);
      Byte_Array'Write (SIO.Stream (F), Header);
      for Cyl in 0 .. Disc_Rec.Cyls - 1 loop
         for Side in 0 .. Disc_Rec.Sides - 1 loop
            declare
               T : Track renames Disc_Rec.Tracks (Cyl, Side);
               TH : Byte_Array (0 .. 255) := (others => 0);
               Ti : constant String := "Track-Info" & ASCII.CR & ASCII.LF;
               Total : Natural := 256;
            begin
               if T.Count > 0 then
                  for K in Ti'Range loop
                     TH (K - 1) := Character'Pos (Ti (K));
                  end loop;
                  TH (16#10#) := Byte (Cyl);
                  TH (16#11#) := Byte (Side);
                  TH (16#14#) := T.Sectors (0).N;
                  TH (16#15#) := Byte (T.Count);
                  TH (16#16#) := 16#4E#;
                  TH (16#17#) := 16#E5#;
                  for I in 0 .. T.Count - 1 loop
                     declare
                        S : Sector renames T.Sectors (I);
                        Info : constant Natural := 16#18# + 8 * I;
                     begin
                        TH (Info .. Info + 7) :=
                          (S.C, S.H, S.R, S.N, S.ST1, S.ST2,
                           Byte (S.Data'Length mod 256),
                           Byte (S.Data'Length / 256));
                        Total := Total + S.Data'Length;
                     end;
                  end loop;
                  Byte_Array'Write (SIO.Stream (F), TH);
                  for I in 0 .. T.Count - 1 loop
                     Byte_Array'Write (SIO.Stream (F), T.Sectors (I).Data.all);
                  end loop;
                  if Total mod 256 /= 0 then
                     Byte_Array'Write (SIO.Stream (F),
                                       (1 .. 256 - Total mod 256 => 0));
                  end if;
               end if;
            end;
         end loop;
      end loop;
      SIO.Close (F);
      Ok := True;
   exception
      when others =>
         Ok := False;
         Err := To_Unbounded_String ("cannot write " & Path);
   end Write_Image;

   procedure Flush (D : Drive) is
      Ok : Boolean;
   begin
      if Discs (D).Present and then Discs (D).Dirty
        and then not Discs (D).Read_Only
      then
         Write_Image (Discs (D), To_String (Discs (D).Path), Ok);
         if Ok then
            Discs (D).Dirty := False;
         end if;
      end if;
   end Flush;

   procedure Flush_All is
   begin
      Flush (0);
      Flush (1);
   end Flush_All;

   procedure Eject (D : Drive) is
   begin
      Flush (D);
      Discs (D) := (others => <>);
   end Eject;

   procedure Create (Path : String; Ok : out Boolean) is
      New_Disc : Disc;
      --  +3DOS disc specification (single sided, 40 tracks, 9 x 512)
      Spec : constant Byte_Array :=
        (16#00#, 16#00#, 16#28#, 16#09#, 16#02#, 16#01#, 16#03#, 16#02#,
         16#2A#, 16#52#);
   begin
      New_Disc.Tracks := new Track_Array;
      New_Disc.Cyls := 40;
      New_Disc.Sides := 1;
      New_Disc.Present := True;
      for Cyl in 0 .. 39 loop
         declare
            IDs : ID_List (1 .. 9);
            T : Track renames New_Disc.Tracks (Cyl, 0);
         begin
            for I in IDs'Range loop
               IDs (I) := (Byte (Cyl), 0, Byte (I), 2);
            end loop;
            T.Count := 9;
            for I in 0 .. 8 loop
               T.Sectors (I) := (Byte (Cyl), 0, Byte (I + 1), 2, 0, 0,
                                 new Byte_Array'(0 .. 511 => 16#E5#));
            end loop;
         end;
      end loop;
      New_Disc.Tracks (0, 0).Sectors (0).Data (0 .. Spec'Length - 1) := Spec;
      New_Disc.Tracks (0, 0).Sectors (0).Data (Spec'Length .. 511) :=
        (others => 0);
      Write_Image (New_Disc, Path, Ok);
   end Create;

end DSK;
