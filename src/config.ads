-- ***************************************************************************
--                              AdaZX - Config
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

--  The emulated model, shared by all hardware packages.

package Config is

   type Model_Type is (ZX48, ZX128, Plus2, Plus2A, Plus3, ZX81, ZX80);
   --  Plus2A is the black +2A / +2B (the +3 without its disc drive)

   Model : Model_Type := ZX48;

   function Is_ZX81 return Boolean is (Model in ZX81 | ZX80);
   --  The ZX81 family (ZX81 or ZX80): display, keyboard and memory
   function Is_ZX80 return Boolean is (Model = ZX80);
   function Is_128 return Boolean is (Model in ZX128 .. Plus3);

   --  AY sound boards for the ZX81 / ZX80: the ZON X-81 (Bi-Pak; ports
   --  &DF / &CF select a register, &0F writes it; 1.625 MHz) and the
   --  Quicksilva board (memory mapped: &7FFF select, &7FFE data; 0.8125 MHz)
   type ZX81_Sound_Type is (No_Board, ZON_X, Quicksilva);
   ZX81_Sound : ZX81_Sound_Type := No_Board;
   function Has_AY return Boolean is
     (Is_128 or else (Is_ZX81 and then ZX81_Sound /= No_Board));
   function Is_Plus3_Type return Boolean is (Model in Plus2A .. Plus3);

   function Model_Name (M : Model_Type) return String is
     (case M is
         when ZX48 => "ZX Spectrum 48K",
         when ZX128 => "ZX Spectrum 128K",
         when Plus2 => "ZX Spectrum +2",
         when Plus2A => "ZX Spectrum +2A",
         when Plus3 => "ZX Spectrum +3",
         when ZX81 => "Sinclair ZX81",
         when ZX80 => "Sinclair ZX80");

   function CPU_Clock return Natural is
     (case Model is
         when ZX48 => 3_500_000,
         when ZX81 | ZX80 => 3_250_000,
         when others => 3_546_900);

end Config;
