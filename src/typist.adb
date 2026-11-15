-- ***************************************************************************
--                              AdaZX - Typist
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

with Config;
with Keyboard; use Keyboard;
with Basic;
with Basic_ZX80;
use type Basic.Dialect;
use type Basic.Key_Kind;
with Interfaces; use Interfaces;
with Memory;
with P_Files;

package body Typist is

   procedure Press (K : Key_Pos; Caps : Boolean := False;
                    Sym : Boolean := False) is
   begin
      Type_Combo ((Key => K, Caps => Caps, Sym => Sym));
   end Press;

   function Key_Of (C : Character) return Key_Pos is
     (if C in '0' .. '9' then Digit (C)
      elsif C = '.' then K_Sym             --  the "." key (ZX80 / ZX81)
      else Letter (C));

   procedure Enter_E_Mode is
   begin
      if Config.Is_ZX81 then
         Press (K_Enter, Caps => True);      --  FUNCTION
      else
         Press (K_Sym, Caps => True);     --  CAPS + SYMBOL SHIFT
      end if;
   end Enter_E_Mode;

   procedure Type_Line (Line : String) is
      D : constant Basic.Dialect :=
        (if Config.Is_ZX80 then Basic.ZX80
         elsif Config.Is_ZX81 then Basic.ZX81 else Basic.Spectrum);
      K_Mode : Boolean := True;
   begin
      Basic.Tokenize_Text ("1 " & Line, D);
      declare
         P : constant Byte_Array := Basic.Program;
         I : Natural := P'First + (if D = Basic.ZX80 then 2 else 4);
         Last : constant Natural := P'Last - 1;     --  before ENTER
      begin
         while I <= Last loop
            declare
               B : constant Byte := P (I);
               Kind : Basic.Key_Kind;
               Key : Character;
            begin
               if (D = Basic.Spectrum and then B = 16#0E#)
                 or else (D = Basic.ZX81 and then B = 16#7E#)
               then
                  I := I + 5;                --  hidden number
               else
                  Basic.Keyword_Key (B, D, Kind, Key);
                  case Kind is
                     when Basic.K_Mode =>
                        Press (Key_Of (Key));
                        K_Mode := False;
                     when Basic.Symbol_Shift =>
                        if Config.Is_ZX81 then
                           Press (Key_Of (Key), Caps => True);
                        else
                           Press (Key_Of (Key), Sym => True);
                        end if;
                        --  THEN starts a statement
                        K_Mode := Basic.Token_Text (B, D) = "THEN";
                     when Basic.Extended =>
                        Enter_E_Mode;
                        Press (Key_Of (Key));
                        K_Mode := False;
                     when Basic.Extended_Symbol =>
                        Enter_E_Mode;
                        Press (Key_Of (Key), Sym => True);
                        K_Mode := False;
                     when Basic.Not_Keyword =>
                        declare
                           C : constant Character :=
                             (if D = Basic.ZX80 then Basic_ZX80.From_Code (B)
                              elsif D = Basic.ZX81 then Basic.From_ZX81 (B)
                              elsif B < 128 then Character'Val (B) else '?');
                           Found : Boolean;
                           Combo_K : constant Combo := Char_Combo (C, Found);
                        begin
                           if D = Basic.ZX81 and then B = 11 then
                              Press (Letter ('P'), Caps => True);
                           elsif D = Basic.ZX80 and then B = 1 then
                              Press (Letter ('Y'), Caps => True);
                           elsif Found then
                              Type_Combo (Combo_K);
                           end if;
                           if C = ':' then
                              K_Mode := True;
                           elsif C not in '0' .. '9' | ' ' then
                              K_Mode := False;
                           end if;
                        end;
                  end case;
               end if;
            end;
            I := I + 1;
         end loop;
      end;
   end Type_Line;

   procedure Type_Text (S : String) is
      Plain : constant Boolean :=
        Config.Is_128 and then Memory.Current_ROM /= Memory.Basic48_ROM;
      Start : Natural := S'First;
   begin
      if Plain then
         Type_Keys (S);
         return;
      end if;
      for I in S'Range loop
         if S (I) = ASCII.LF then
            if I > Start then
               Type_Line (S (Start .. I - 1));
            end if;
            Press (K_Enter);
            if Config.Is_ZX81 then
               Type_Wait (200);     --  until the editor is ready again
            else
               Type_Pause (3);
            end if;
            Start := I + 1;
         end if;
      end loop;
      if Start <= S'Last then
         Type_Line (S (Start .. S'Last));
      end if;
   end Type_Text;

   procedure Type_Load is
   begin
      if Config.Is_ZX80 then
         Type_Text ("LOAD" & ASCII.LF);       --  no file names on the ZX80
      else
         Type_Text ("LOAD """"" & ASCII.LF);
      end if;
   end Type_Load;

   procedure Put_Word (Addr : Natural; V : Natural) is
   begin
      Memory.Poke_Any (Types.Word (Addr), Byte (V mod 256));
      Memory.Poke_Any (Types.Word (Addr + 1), Byte (V / 256 mod 256));
   end Put_Word;

   function Get_Word (Addr : Natural) return Natural is
     (Natural (Memory.Read (Types.Word (Addr)))
      + 256 * Natural (Memory.Read (Types.Word (Addr + 1))));

   procedure Install_Program (Data : Byte_Array; Run_Line : Integer := -1) is
   begin
      if Config.Is_ZX80 then
         declare
            Live : Byte_Array (0 .. 39);
         begin
            for K in Live'Range loop
               Live (K) := Memory.Read (16#4000# + Types.Word (K));
            end loop;
            P_Files.Set_Image (Basic_ZX80.Make_O (Data, Live));
         end;
         Type_Load;
         return;
      elsif Config.Is_ZX81 then
         P_Files.Set_Image (Basic.Make_P (Data, Run_Line));
         Type_Load;
         return;
      end if;
      declare
         Prog : constant Natural := Get_Word (23635);
         Vars : constant Natural := Prog + Data'Length;
         E_Line : constant Natural := Vars + 1;
         Worksp : constant Natural := E_Line + 2;
      begin
         for K in Data'Range loop
            Memory.Poke_Any (Types.Word (Prog + K - Data'First), Data (K));
         end loop;
         Memory.Poke_Any (Types.Word (Vars), 16#80#);
         Memory.Poke_Any (Types.Word (E_Line), 16#0D#);
         Memory.Poke_Any (Types.Word (E_Line + 1), 16#80#);
         Put_Word (23627, Vars);
         Put_Word (23641, E_Line);
         Put_Word (23643, E_Line);          --  K_CUR
         Put_Word (23645, E_Line);          --  CH_ADD
         Put_Word (23647, 0);               --  X_PTR
         Put_Word (23649, Worksp);
         Put_Word (23651, Worksp);          --  STKBOT
         Put_Word (23653, Worksp);          --  STKEND
         Put_Word (23639, Prog - 1);        --  DATADD
         Put_Word (23637, Prog);            --  NXTLIN
      end;
   end Install_Program;

end Typist;
