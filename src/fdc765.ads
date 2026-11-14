--  NEC uPD765A floppy disc controller of the Spectrum +3, with the discs
--  of package DSK in drives A (0) and B (1).
--
--  The +3 polls the controller (its interrupt is not connected): the CPU
--  writes command bytes to the data register (&3FFD), transfers the data
--  of read / write commands byte by byte through it (non-DMA execution
--  phase) and reads the result bytes; the main status register (&2FFD)
--  tells which phase it is in.  Transfers are immediate (the drive is
--  never late).  Commands: read / write (deleted) data, read track,
--  read ID, format track, seek, recalibrate, sense interrupt status,
--  sense drive status, specify; others are invalid.  As on the +3 there
--  is no terminal count, so read / write commands end after the last
--  sector of the track (EOT) with "end of cylinder", which +3DOS takes
--  as success.

with Types; use Types;

package FDC765 is

   procedure Reset;
   function Read_Status return Byte;
   function Read_Data return Byte;
   procedure Write_Data (V : Byte);

   Motor : Boolean := False;       --  bit 3 of port &1FFD

   function Active return Boolean;  --  a command is in progress (LED)

end FDC765;
