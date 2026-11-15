-- ***************************************************************************
--                             AdaZX - Fat_Image
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

with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Containers.Vectors;
with Ada.Direct_IO;
with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces; use Interfaces;

package body Fat_Image is

   subtype Byte is Unsigned_8;
   type Sector is array (0 .. 511) of Byte;
   package DIO is new Ada.Direct_IO (Sector);
   use type DIO.Count;
   use type Ada.Directories.File_Kind;

   Err : Unbounded_String;

   function Error_Message return String is (To_String (Err));

   type Node is record
      Name : String (1 .. 11);           --  8.3, space padded
      Host : Unbounded_String;
      Is_Dir : Boolean;
      Size : Natural;
      Parent : Natural;                  --  0 = the root
      First, Count : Natural := 0;       --  clusters
      Date, Time : Unsigned_16 := 0;
   end record;

   package Node_Vectors is new Ada.Containers.Vectors (Positive, Node);
   Nodes : Node_Vectors.Vector;

   package Name_Vectors is new Ada.Containers.Vectors
     (Positive, Unbounded_String);
   package Name_Sort is new Name_Vectors.Generic_Sorting;

   Too_Big : exception;

   ---------------------------------------------------------------------
   --  Names
   ---------------------------------------------------------------------

   function Valid (C : Character) return Boolean is
     (Is_Upper (C) or else Is_Digit (C)
      or else Ada.Strings.Fixed.Index ("!#$%&'()-@^_`{}~", (1 => C)) > 0);

   function Taken (Name : String; Parent : Natural) return Boolean is
   begin
      for N of Nodes loop
         if N.Parent = Parent and then N.Name = Name then
            return True;
         end if;
      end loop;
      return False;
   end Taken;

   function Find (Name : String; Parent : Natural) return Natural is
   begin
      for I in 1 .. Natural (Nodes.Length) loop
         if Nodes (I).Parent = Parent and then Nodes (I).Name = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   function Short_Name (Long : String; Parent : Natural;
                        Exact : out Boolean) return String is
      U : constant String := To_Upper (Long);
      Dot : constant Natural := Ada.Strings.Fixed.Index
        (U, ".", Ada.Strings.Backward);
      Base_In : constant String :=
        (if Dot > U'First then U (U'First .. Dot - 1) else U);
      Ext_In : constant String :=
        (if Dot > U'First then U (Dot + 1 .. U'Last) else "");
      Base, Ext : Unbounded_String;
      Lossy : Boolean := False;
   begin
      for C of Base_In loop
         if C = ' ' or else C = '.' then
            Lossy := True;
         elsif Valid (C) then
            Append (Base, C);
         else
            Append (Base, '_');
            Lossy := True;
         end if;
      end loop;
      for C of Ext_In loop
         if Valid (C) then
            Append (Ext, C);
         elsif C /= ' ' then
            Append (Ext, '_');
            Lossy := True;
         end if;
      end loop;
      if Length (Base) = 0 then
         Base := To_Unbounded_String ("_");
         Lossy := True;
      end if;
      if Length (Base) > 8 or else Length (Ext) > 3 then
         Lossy := True;
      end if;
      if Length (Ext) > 3 then
         Ext := Head (Ext, 3);
      end if;
      declare
         E : constant String := Ada.Strings.Fixed.Head (To_String (Ext), 3);
      begin
         if not Lossy then
            Exact := True;
            return Ada.Strings.Fixed.Head (To_String (Base), 8) & E;
         end if;
         Exact := False;
         for N in 1 .. 999_999 loop
            declare
               Tail : constant String :=
                 "~" & Ada.Strings.Fixed.Trim (N'Image, Ada.Strings.Left);
               B : constant String :=
                 Ada.Strings.Fixed.Head
                   (To_String (Head (Base, Natural'Min
                      (Length (Base), 8 - Tail'Length))) & Tail, 8);
            begin
               if not Taken (B & E, Parent) then
                  return B & E;
               end if;
            end;
         end loop;
         return "_       ___";
      end;
   end Short_Name;

   ---------------------------------------------------------------------
   --  Scanning the host folders
   ---------------------------------------------------------------------

   procedure Stamp (N : in out Node) is
      use Ada.Calendar;
      T : Time;
      Y : Year_Number; Mo : Month_Number; D : Day_Number;
      H : Ada.Calendar.Formatting.Hour_Number;
      Mi : Ada.Calendar.Formatting.Minute_Number;
      S : Ada.Calendar.Formatting.Second_Number;
      Sub : Ada.Calendar.Formatting.Second_Duration;
   begin
      T := Ada.Directories.Modification_Time (To_String (N.Host));
      Ada.Calendar.Formatting.Split (T, Y, Mo, D, H, Mi, S, Sub);
      N.Date := Unsigned_16 (Integer'Max (Y - 1980, 0)) * 512
        + Unsigned_16 (Mo) * 32 + Unsigned_16 (D);
      N.Time := Unsigned_16 (H) * 2048 + Unsigned_16 (Mi) * 32
        + Unsigned_16 (S / 2);
   exception
      when others => null;
   end Stamp;

   procedure Scan (Folder : String; Parent : Natural) is
      use Ada.Directories;
      Names : Name_Vectors.Vector;
      S : Search_Type;
      E : Directory_Entry_Type;
   begin
      Start_Search (S, Folder, "");
      while More_Entries (S) loop
         Get_Next_Entry (S, E);
         declare
            N : constant String := Simple_Name (E);
         begin
            if N'Length > 0 and then N (N'First) /= '.'
              and then Kind (E) /= Special_File
            then
               Names.Append (To_Unbounded_String (N));
            end if;
         end;
      end loop;
      End_Search (S);
      Name_Sort.Sort (Names);
      for Long of Names loop
         declare
            Path : constant String := Compose (Folder, To_String (Long));
            Dir : constant Boolean := Kind (Path) = Directory;
            Exact : Boolean;
            Short : constant String :=
              Short_Name (To_String (Long), Parent, Exact);
            Existing : constant Natural :=
              (if Exact then Find (Short, Parent) else 0);
         begin
            if Existing > 0 then
               if Dir and then Nodes (Existing).Is_Dir then
                  Scan (Path, Existing);       --  merge the folders
               end if;
            else
               declare
                  N : Node :=
                    (Name => Short, Host => To_Unbounded_String (Path),
                     Is_Dir => Dir,
                     Size => (if Dir then 0
                              else Natural (Ada.Directories.Size (Path))),
                     Parent => Parent, others => <>);
               begin
                  Stamp (N);
                  Nodes.Append (N);
                  if Dir then
                     Scan (Path, Natural (Nodes.Length));
                  end if;
               end;
            end if;
         end;
      end loop;
   end Scan;

   function Children (Parent : Natural) return Natural is
      C : Natural := 0;
   begin
      for N of Nodes loop
         if N.Parent = Parent then
            C := C + 1;
         end if;
      end loop;
      return C;
   end Children;

   ---------------------------------------------------------------------
   --  Writing the image
   ---------------------------------------------------------------------

   Root_Entries : constant := 512;
   type Size_List is array (Positive range <>) of Positive;

   procedure Write_Image (Image : String; Size_MB : Positive) is
      Total : constant Natural := Size_MB * 2048;         --  sectors
      SPC : constant Natural := Size_MB / 16;              --  per cluster
      Cluster_Bytes : constant Natural := SPC * 512;
      FAT_Sectors : constant Natural :=
        ((Total / SPC + 2) * 2 + 511) / 512;
      Root_Start : constant Natural := 1 + 2 * FAT_Sectors;
      Data_Start : constant Natural := Root_Start + Root_Entries * 32 / 512;
      Clusters : constant Natural := (Total - Data_Start) / SPC;
      FAT : array (0 .. Clusters + 1) of Unsigned_16 := (others => 0);
      Next_Free : Natural := 2;
      F : DIO.File_Type;
      Index : DIO.Positive_Count := 1;

      procedure Put (S : Sector) is
      begin
         DIO.Write (F, S, Index);
         Index := Index + 1;
      end Put;

      procedure W16 (S : in out Sector; At_I : Natural; V : Natural) is
      begin
         S (At_I) := Byte (V mod 256);
         S (At_I + 1) := Byte (V / 256 mod 256);
      end W16;

      procedure W32 (S : in out Sector; At_I : Natural; V : Natural) is
      begin
         W16 (S, At_I, V mod 65536);
         W16 (S, At_I + 2, V / 65536);
      end W32;

      --  Directory entries of Parent (with "." and ".." for a subfolder)
      procedure Entries (Parent : Natural; Sectors : Natural) is
         Buf : array (0 .. Sectors - 1) of Sector :=
           (others => (others => 0));
         Pos : Natural := 0;

         procedure Add (Name : String; Attr : Byte; Cluster, Size : Natural;
                        Date, Time : Unsigned_16) is
            S : constant Natural := Pos / 16;
            O : constant Natural := (Pos mod 16) * 32;
         begin
            for I in 0 .. 10 loop
               Buf (S) (O + I) := Character'Pos (Name (Name'First + I));
            end loop;
            Buf (S) (O + 11) := Attr;
            W16 (Buf (S), O + 14, Natural (Time));
            W16 (Buf (S), O + 16, Natural (Date));
            W16 (Buf (S), O + 18, Natural (Date));
            W16 (Buf (S), O + 22, Natural (Time));
            W16 (Buf (S), O + 24, Natural (Date));
            W16 (Buf (S), O + 26, Cluster);
            W32 (Buf (S), O + 28, Size);
            Pos := Pos + 1;
         end Add;
      begin
         if Parent = 0 then
            Add ("ADAZX      ", 16#08#, 0, 0, 0, 0);    --  volume label
         else
            declare
               P : constant Node := Nodes (Parent);
            begin
               Add (".          ", 16#10#, P.First, 0, P.Date, P.Time);
               Add ("..         ", 16#10#,
                    (if P.Parent = 0 then 0 else Nodes (P.Parent).First), 0,
                    P.Date, P.Time);
            end;
         end if;
         for N of Nodes loop
            if N.Parent = Parent then
               Add (N.Name, (if N.Is_Dir then 16#10# else 16#20#),
                    N.First, N.Size, N.Date, N.Time);
            end if;
         end loop;
         for S of Buf loop
            Put (S);
         end loop;
      end Entries;

      procedure Copy_File (N : Node) is
         use Ada.Streams.Stream_IO;
         In_F : File_Type;
         Buf : Stream_Element_Array (1 .. 512);
         Last : Stream_Element_Offset;
         S : Sector;
         Written : Natural := 0;
      begin
         if N.Count = 0 then
            return;
         end if;
         Open (In_F, In_File, To_String (N.Host));
         while not End_Of_File (In_F) loop
            Read (In_F, Buf, Last);
            S := (others => 0);
            for I in 1 .. Last loop
               S (Natural (I) - 1) := Byte (Buf (I));
            end loop;
            Put (S);
            Written := Written + 1;
         end loop;
         Close (In_F);
         while Written < N.Count * SPC loop      --  the cluster's rest
            Put ((others => 0));
            Written := Written + 1;
         end loop;
      end Copy_File;

      Boot : Sector := (others => 0);
      OEM : constant String := "ADAZX1.0";
      Label : constant String := "ADAZX      ";
      FS_Type : constant String := "FAT16   ";
   begin
      --  Allocate the clusters in the order the data is written
      for I in 1 .. Natural (Nodes.Length) loop
         declare
            N : Node := Nodes (I);
         begin
            N.Count :=
              (if N.Is_Dir
               then ((Children (I) + 2) * 32 + Cluster_Bytes - 1)
                      / Cluster_Bytes
               else (N.Size + Cluster_Bytes - 1) / Cluster_Bytes);
            if N.Count > 0 then
               if Next_Free + N.Count > Clusters + 2 then
                  raise Too_Big;
               end if;
               N.First := Next_Free;
               for C in Next_Free .. Next_Free + N.Count - 2 loop
                  FAT (C) := Unsigned_16 (C + 1);
               end loop;
               FAT (Next_Free + N.Count - 1) := 16#FFFF#;
               Next_Free := Next_Free + N.Count;
            end if;
            Nodes.Replace_Element (I, N);
         end;
      end loop;
      FAT (0) := 16#FFF8#;
      FAT (1) := 16#FFFF#;

      --  Boot sector (BIOS parameter block)
      Boot (0 .. 2) := (16#EB#, 16#3C#, 16#90#);
      for I in 0 .. 7 loop
         Boot (3 + I) := Character'Pos (OEM (I + 1));
      end loop;
      W16 (Boot, 11, 512);
      Boot (13) := Byte (SPC);
      W16 (Boot, 14, 1);                        --  reserved sectors
      Boot (16) := 2;                           --  FATs
      W16 (Boot, 17, Root_Entries);
      W16 (Boot, 19, 0);
      Boot (21) := 16#F8#;
      W16 (Boot, 22, FAT_Sectors);
      W16 (Boot, 24, 32);
      W16 (Boot, 26, 64);
      W32 (Boot, 28, 0);
      W32 (Boot, 32, Total);
      Boot (36) := 16#80#;
      Boot (38) := 16#29#;
      W32 (Boot, 39, 16#2026_0ADA#);       --  volume serial
      for I in 0 .. 10 loop
         Boot (43 + I) := Character'Pos (Label (I + 1));
      end loop;
      for I in 0 .. 7 loop
         Boot (54 + I) := Character'Pos (FS_Type (I + 1));
      end loop;
      Boot (510) := 16#55#;
      Boot (511) := 16#AA#;

      DIO.Create (F, DIO.Out_File, Image);
      Put (Boot);
      for Copy in 1 .. 2 loop
         for S in 0 .. FAT_Sectors - 1 loop
            declare
               Sec : Sector := (others => 0);
            begin
               for K in 0 .. 255 loop
                  if S * 256 + K <= FAT'Last then
                     W16 (Sec, K * 2, Natural (FAT (S * 256 + K)));
                  end if;
               end loop;
               Put (Sec);
            end;
         end loop;
      end loop;
      Entries (0, Root_Entries * 32 / 512);
      for I in 1 .. Natural (Nodes.Length) loop
         if Nodes (I).Is_Dir then
            Entries (I, Nodes (I).Count * SPC);
         else
            Copy_File (Nodes (I));
         end if;
      end loop;
      DIO.Write (F, (others => 0), DIO.Positive_Count (Total));  --  size
      DIO.Close (F);
   end Write_Image;

   procedure Build (Image : String; Folders : Folder_List; Ok : out Boolean)
   is
      Need : Natural := 0;
   begin
      Ok := False;
      Nodes.Clear;
      for D of Folders loop
         if not Ada.Directories.Exists (D.all)
           or else Ada.Directories.Kind (D.all) /= Ada.Directories.Directory
         then
            Err := To_Unbounded_String ("not a folder: " & D.all);
            return;
         end if;
         Scan (D.all, 0);
      end loop;
      if Children (0) > Root_Entries - 1 then
         Err := To_Unbounded_String
           ("more than" & Natural'Image (Root_Entries - 1) &
              " entries in the top folder");
         return;
      end if;
      for N of Nodes loop
         Need := Need + N.Size / 1024 + 64;   --  KB, with slack
      end loop;
      for MB of Size_List'(64, 128, 256, 512, 1024) loop
         if Need / 1024 < MB * 7 / 8 then
            begin
               Write_Image (Image, MB);
               Ok := True;
               return;
            exception
               when Too_Big => null;
            end;
         end if;
      end loop;
      Err := To_Unbounded_String ("the files do not fit on a 1 GB card");
   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error |
           Ada.IO_Exceptions.Device_Error =>
         Err := To_Unbounded_String ("cannot write " & Image);
         Ok := False;
   end Build;

   procedure Blank (Image : String; Ok : out Boolean) is
   begin
      Nodes.Clear;
      Write_Image (Image, 64);
      Ok := True;
   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error |
           Ada.IO_Exceptions.Device_Error =>
         Err := To_Unbounded_String ("cannot write " & Image);
         Ok := False;
   end Blank;

end Fat_Image;
