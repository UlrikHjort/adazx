--  Floppy disc images in the CPC / +3 .dsk formats ("MV - CPC" standard
--  and "EXTENDED CPC DSK"), two drives.  The disc is held in memory as
--  tracks of sectors with their ID fields (C, H, R, N), the FDC status
--  flags recorded with them (copy protection) and their data; a disc that
--  was written to is saved back (as an extended DSK) by Flush.

with Types; use Types;

package DSK is

   type Drive is range 0 .. 1;

   procedure Insert (D : Drive; Path : String; Ok : out Boolean);
   procedure Eject (D : Drive);           --  flushes first
   function Present (D : Drive) return Boolean;
   function Name (D : Drive) return String;
   function Write_Protected (D : Drive) return Boolean;
   function Sides (D : Drive) return Natural;
   function Error_Message return String;

   procedure Create (Path : String; Ok : out Boolean);
   --  A blank +3 disc: 40 tracks, one side, 9 sectors of 512 bytes
   --  (IDs 1 - 9), the +3DOS disc specification in the first sector and
   --  an empty directory.

   --  Tracks and sectors
   Max_Sectors : constant := 32;
   function Sector_Count (D : Drive; Cyl, Head : Natural) return Natural;
   procedure Sector_ID (D : Drive; Cyl, Head, Index : Natural;
                        C, H, R, N : out Byte);
   procedure Sector_Status (D : Drive; Cyl, Head, Index : Natural;
                            ST1, ST2 : out Byte);
   function Sector_Length (D : Drive; Cyl, Head, Index : Natural)
                           return Natural;
   function Find (D : Drive; Cyl, Head : Natural; C, H, R, N : Byte)
                  return Integer;
   --  Index of the sector with that ID on the track, -1 if there is none.
   function Get (D : Drive; Cyl, Head, Index, Offset : Natural) return Byte;
   procedure Put (D : Drive; Cyl, Head, Index, Offset : Natural; V : Byte);

   type ID_Field is record
      C, H, R, N : Byte;
   end record;
   type ID_List is array (Positive range <>) of ID_Field;
   procedure Format_Track (D : Drive; Cyl, Head : Natural; IDs : ID_List;
                           Filler : Byte);

   procedure Flush (D : Drive);
   procedure Flush_All;

end DSK;
