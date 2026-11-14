-- ***************************************************************************
--                              AdaZX - Audio
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
with System;
with Interfaces.C; use Interfaces.C;
with Interfaces.C.Strings; use Interfaces.C.Strings;

package body Audio is

   ---------------------------------------------------------------------
   --  PulseAudio simple API binding
   ---------------------------------------------------------------------

   type Sample_Spec is record
      Format   : int;
      Rate     : unsigned;
      Channels : unsigned_char;
   end record;
   pragma Convention (C, Sample_Spec);

   type Buffer_Attr is record
      Max_Length : unsigned;
      T_Length   : unsigned;
      Pre_Buf    : unsigned;
      Min_Req    : unsigned;
      Frag_Size  : unsigned;
   end record;
   pragma Convention (C, Buffer_Attr);

   PA_SAMPLE_S16LE    : constant int := 3;
   PA_STREAM_PLAYBACK : constant int := 1;

   function pa_simple_new
     (Server : chars_ptr; Name : chars_ptr; Dir : int; Dev : chars_ptr;
      Stream_Name : chars_ptr; Spec : access constant Sample_Spec;
      Map : System.Address; Attr : access constant Buffer_Attr;
      Error : access int) return System.Address;
   pragma Import (C, pa_simple_new, "pa_simple_new");

   function pa_simple_write
     (S : System.Address; Data : System.Address; Bytes : size_t;
      Error : access int) return int;
   pragma Import (C, pa_simple_write, "pa_simple_write");

   procedure pa_simple_free (S : System.Address);
   pragma Import (C, pa_simple_free, "pa_simple_free");

   use type System.Address;
   Handle : System.Address := System.Null_Address;

   ---------------------------------------------------------------------
   --  Ring buffer
   ---------------------------------------------------------------------

   Ring_Size : constant := 16384;
   type Sample_Array is array (Natural range <>) of Sound.Sample;

   protected Ring is
      procedure Put (Data : Sample_Array);
      procedure Get (Data : out Sample_Array; Got : out Natural);
      function Count return Natural;
   private
      Buf  : Sample_Array (0 .. Ring_Size - 1) := (others => 0);
      Head : Natural := 0;
      Fill : Natural := 0;
   end Ring;

   protected body Ring is
      procedure Put (Data : Sample_Array) is
      begin
         for S of Data loop
            exit when Fill >= Ring_Size;
            Buf ((Head + Fill) mod Ring_Size) := S;
            Fill := Fill + 1;
         end loop;
      end Put;

      procedure Get (Data : out Sample_Array; Got : out Natural) is
      begin
         Got := Natural'Min (Fill, Data'Length);
         for I in 0 .. Got - 1 loop
            Data (Data'First + I) := Buf (Head);
            Head := (Head + 1) mod Ring_Size;
         end loop;
         Fill := Fill - Got;
         for I in Got .. Data'Length - 1 loop
            Data (Data'First + I) := 0;
         end loop;
      end Get;

      function Count return Natural is (Fill);
   end Ring;

   ---------------------------------------------------------------------
   --  Output task
   ---------------------------------------------------------------------

   Stop_Requested : Boolean := False;
   pragma Atomic (Stop_Requested);

   task type Writer is
      entry Go;
   end Writer;
   type Writer_Access is access Writer;
   The_Writer : Writer_Access;

   task body Writer is
      Chunk : Sample_Array (0 .. 511);
      Got : Natural;
      Err : aliased int;
      R : int;
      pragma Unreferenced (R);
   begin
      accept Go;
      while not Stop_Requested loop
         Ring.Get (Chunk, Got);
         if Got = 0 then
            delay 0.002;
            --  Keep the stream alive with a little silence if starved
            Ring.Get (Chunk, Got);
         end if;
         if Muted then
            Chunk := (others => 0);
         end if;
         R := pa_simple_write (Handle, Chunk'Address,
                               size_t (Chunk'Length * 2), Err'Access);
      end loop;
   end Writer;

   ---------------------------------------------------------------------
   --  Local collection buffer (emulation thread)
   ---------------------------------------------------------------------

   Local : Sample_Array (0 .. 4095);
   Local_Fill : Natural := 0;

   procedure Push (S : Sound.Sample) is
   begin
      if Local_Fill <= Local'Last then
         Local (Local_Fill) := S;
         Local_Fill := Local_Fill + 1;
      end if;
   end Push;

   procedure Flush is
   begin
      if Handle /= System.Null_Address and then Local_Fill > 0 then
         Ring.Put (Local (0 .. Local_Fill - 1));
      end if;
      Local_Fill := 0;
   end Flush;

   function Buffered return Natural is (Ring.Count);

   function Available return Boolean is
     (Handle /= System.Null_Address);

   procedure Start is
      Spec : aliased constant Sample_Spec :=
        (Format => PA_SAMPLE_S16LE, Rate => Sound.Sample_Rate, Channels => 1);
      Attr : aliased constant Buffer_Attr :=
        (Max_Length => unsigned'Last,
         T_Length   => 2048 * 2,
         Pre_Buf    => unsigned'Last,
         Min_Req    => 512 * 2,
         Frag_Size  => unsigned'Last);
      Err : aliased int;
      App  : chars_ptr := New_String ("AdaZX");
      Desc : chars_ptr := New_String ("Sound");
   begin
      Handle := pa_simple_new (Null_Ptr, App, PA_STREAM_PLAYBACK, Null_Ptr,
                               Desc, Spec'Access, System.Null_Address,
                               Attr'Access, Err'Access);
      Free (App);
      Free (Desc);
      if Handle /= System.Null_Address then
         The_Writer := new Writer;
         The_Writer.Go;
      end if;
   end Start;

   procedure Stop is
   begin
      Stop_Requested := True;
   end Stop;

end Audio;
