-- ***************************************************************************
--                              AdaZX - Memory
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

with Interfaces; use Interfaces;
with Config; use Config;
with Interface_1;
with DivMMC;
with Beta_Disk;

package body Memory is

   function S (A : Word) return Slot is (Slot (Shift_Right (A, 14)));

   procedure Set_Slot (N : Slot; Base : Natural; Writable : Boolean;
                       Contend : Boolean) is
   begin
      Slot_Base (N) := Base;
      Slot_Writable (N) := Writable;
      Slot_Contended (N) := Contend;
   end Set_Slot;

   function Bank_Contended (Bank : Natural) return Boolean is
     (case Model is
         when ZX48 | TC2048 => Bank = 5,
         when Pentagon => False,
         when ZX128 | Plus2 => Bank mod 2 = 1,
         when Plus2A | Plus3 => Bank >= 4,
         when ZX81 | ZX80 => False);

   procedure Set_RAM (N : Slot; Bank : Natural) is
   begin
      Set_Slot (N, RAM_Base (Bank), True, Bank_Contended (Bank));
   end Set_RAM;

   procedure Update_Map is
   begin
      if Model in ZX48 | TC2048 or else Is_ZX81 then
         Set_Slot (0, ROM_Base (0), False, False);
         Set_RAM (1, 5);
         Set_RAM (2, 2);
         Set_RAM (3, 0);
         return;
      end if;
      if Special_Paging then
         case Shift_Right (Port_1FFD, 1) and 3 is
            when 0 => Set_RAM (0, 0); Set_RAM (1, 1); Set_RAM (2, 2);
               Set_RAM (3, 3);
            when 1 => Set_RAM (0, 4); Set_RAM (1, 5); Set_RAM (2, 6);
               Set_RAM (3, 7);
            when 2 => Set_RAM (0, 4); Set_RAM (1, 5); Set_RAM (2, 6);
               Set_RAM (3, 3);
            when others => Set_RAM (0, 4); Set_RAM (1, 7); Set_RAM (2, 6);
               Set_RAM (3, 3);
         end case;
         return;
      end if;
      Set_Slot (0, ROM_Base (Current_ROM), False, False);
      Set_RAM (1, 5);
      Set_RAM (2, 2);
      Set_RAM (3, Natural (Port_7FFD and 7));
   end Update_Map;

   function Special_Paging return Boolean is
     (Is_Plus3_Type and then (Port_1FFD and 1) /= 0);

   function Current_ROM return Natural is
     (case Model is
         when ZX48 | TC2048 | ZX81 | ZX80 => 0,
         when ZX128 | Plus2 | Pentagon =>
            Natural (Shift_Right (Port_7FFD, 4) and 1),
         when Plus2A | Plus3 =>
            Natural (Shift_Right (Port_7FFD, 4) and 1)
            + 2 * Natural (Shift_Right (Port_1FFD, 2) and 1));

   function Basic48_ROM return Natural is
     (case Model is
         when ZX48 | TC2048 | ZX81 | ZX80 => 0,
         when ZX128 | Plus2 | Pentagon => 1,
         when Plus2A | Plus3 => 3);

   function Screen_Bank return Natural is
     (if Is_128 and then (Port_7FFD and 8) /= 0 then 7 else 5);

   procedure Reset_Paging is
   begin
      Port_7FFD := 0;
      Port_1FFD := 0;
      Paging_Locked := False;
      Update_Map;
   end Reset_Paging;

   procedure Clear_RAM is
   begin
      Store (0 .. 8 * Bank_Size - 1) := (others => 0);
   end Clear_RAM;

   procedure Write_7FFD (V : Byte) is
   begin
      if Is_128 and then not Paging_Locked then
         Port_7FFD := V;
         Paging_Locked := (V and 16#20#) /= 0;
         Update_Map;
      end if;
   end Write_7FFD;

   procedure Write_1FFD (V : Byte) is
   begin
      if Is_Plus3_Type and then not Paging_Locked then
         Port_1FFD := V;
         Update_Map;
      end if;
   end Write_1FFD;

   function ZX81_Offset (Addr : Word) return Integer is
      A : constant Natural := Natural (Addr and 16#7FFF#);
   begin
      if A < 16#2000# then
         return ROM_Base (0) + A;
      elsif A < 16#4000# then
         if ZX81_RAM_2000 then
            return RAM_Base (1) + A;
         end if;
         return ROM_Base (0) + A - 16#2000#;
      else
         return RAM_Base (0) + (A - 16#4000#) mod ZX81_RAM_Size;
      end if;
   end ZX81_Offset;

   function Read (Addr : Word) return Byte is
   begin
      if Is_ZX81 then
         return Store (ZX81_Offset (Addr));
      end if;
      if Addr < 16#4000# then
         if Beta_Disk.Active then
            return Beta_Disk.ROM_Byte (Addr);
         elsif DivMMC.Active then
            return DivMMC.Read (Addr);
         elsif Interface_1.Paged then
            return Interface_1.ROM_Byte (Addr);
         end if;
      end if;
      return Store (Slot_Base (S (Addr)) + Natural (Addr and 16#3FFF#));
   end Read;

   procedure Write (Addr : Word; V : Byte) is
   begin
      if Is_ZX81 then
         declare
            O : constant Natural := ZX81_Offset (Addr);
         begin
            if O < ROM_Base (0) then
               Store (O) := V;
            end if;
         end;
      elsif Addr < 16#4000# and then DivMMC.Active then
         DivMMC.Write (Addr, V);
      elsif Slot_Writable (S (Addr)) then
         Store (Slot_Base (S (Addr)) + Natural (Addr and 16#3FFF#)) := V;
      end if;
   end Write;

   procedure Poke_Any (Addr : Word; V : Byte) is
   begin
      if Is_ZX81 then
         Store (ZX81_Offset (Addr)) := V;
      else
         Store (Slot_Base (S (Addr)) + Natural (Addr and 16#3FFF#)) := V;
      end if;
   end Poke_Any;

   function Contended (Addr : Word) return Boolean is
     (Slot_Contended (S (Addr)));

   function Screen_Byte (Offset : Natural) return Byte is
     (Store (RAM_Base (Screen_Bank) + Offset));

   function Bank_Of (Addr : Word) return Integer is
     (if Is_ZX81 or else not Slot_Writable (S (Addr)) then -1
      else Slot_Base (S (Addr)) / Bank_Size);

end Memory;
