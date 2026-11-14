-- ***************************************************************************
--                             AdaZX - Wav_Sink
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
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Interfaces; use Interfaces;

package body Wav_Sink is

   Max : constant := Sound.Sample_Rate * 120;
   type Buffer is array (0 .. Max - 1) of Sound.Sample;
   type Buffer_Access is access Buffer;
   Buf : constant Buffer_Access := new Buffer;
   Count : Natural := 0;

   procedure Push (S : Sound.Sample) is
   begin
      if Count < Max then
         Buf (Count) := S;
         Count := Count + 1;
      end if;
   end Push;

   procedure Save (Path : String) is
      F : File_Type;
      S : Stream_Access;
      Data_Bytes : constant Unsigned_32 := Unsigned_32 (Count * 2);
   begin
      Create (F, Out_File, Path);
      S := Stream (F);
      String'Write (S, "RIFF");
      Unsigned_32'Write (S, 36 + Data_Bytes);
      String'Write (S, "WAVEfmt ");
      Unsigned_32'Write (S, 16);
      Unsigned_16'Write (S, 1);                       --  PCM
      Unsigned_16'Write (S, 1);                       --  mono
      Unsigned_32'Write (S, Sound.Sample_Rate);
      Unsigned_32'Write (S, Sound.Sample_Rate * 2);
      Unsigned_16'Write (S, 2);
      Unsigned_16'Write (S, 16);
      String'Write (S, "data");
      Unsigned_32'Write (S, Data_Bytes);
      for I in 0 .. Count - 1 loop
         Sound.Sample'Write (S, Buf (I));
      end loop;
      Close (F);
   end Save;

end Wav_Sink;
