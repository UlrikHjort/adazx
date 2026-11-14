-- ***************************************************************************
--                               AdaZX - Tape
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

--  Spectrum tapes: .tap and .tzx images played as the EAR signal (with the
--  real pulse timings, so turbo and custom loaders work), flash loading
--  of standard ROM blocks, and recording of what the ROM saves.
--
--  Times are T-states of the 3.5 MHz clock (TZX timings), counted in the
--  frame's T-state coordinates like Tstates.T.

with Types; use Types;

package Tape is

   procedure Insert (Path : String; Ok : out Boolean);
   procedure Eject;
   function Name return String;           --  "" when no tape
   function Loaded return Boolean;

   procedure Play;
   procedure Stop;
   function Playing return Boolean;
   procedure Rewind;

   function Ear (T : Integer) return Boolean;
   --  The EAR level at T-state T (the tape runs up to T first).
   procedure End_Frame (Frame_T : Natural);

   type Level_Proc is access procedure (Level : Boolean; T : Integer);
   On_Edge : Level_Proc := null;     --  each level change (for the sound)

   --  Flash loading
   function At_Standard_Block return Boolean;
   --  The tape is at (or in the pilot of) a standard speed data block.
   function Take_Block return Byte_Array;
   --  The data of that block (flag, data, checksum); the tape moves on to
   --  the next block.

   --  Blocks (for display)
   function Block_Count return Natural;
   function Current_Block return Natural;      --  1-based, 0 = end
   function Block_Text (I : Positive) return String;

   --  Recording (saves trapped in the ROM)
   procedure Record_Block (Data : Byte_Array);
   function Recorded_Bytes return Natural;
   procedure Save_Recording (Path : String; Ok : out Boolean);
   procedure Clear_Recording;

   function Error_Message return String;

end Tape;
