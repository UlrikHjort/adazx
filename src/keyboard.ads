-- ***************************************************************************
--                             AdaZX - Keyboard
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

--  The Sinclair keyboard: 8 half-rows of 5 keys, read through port &FE
--  with the half-rows selected by address lines A8 .. A15 (active low).
--
--    row 0  CAPS SHIFT  Z  X  C  V      row 4  0  9  8  7  6
--    row 1  A  S  D  F  G               row 5  P  O  I  U  Y
--    row 2  Q  W  E  R  T               row 6  ENTER  L  K  J  H
--    row 3  1  2  3  4  5               row 7  SPACE  SYMBOL SHIFT  M  N  B
--
--  (on the ZX81 CAPS SHIFT is SHIFT and SYMBOL SHIFT is the "." key).
--  Host keys are mapped symbolically by default: typing '"' presses
--  SYMBOL SHIFT + P on a Spectrum and SHIFT + P on a ZX81.

with Interfaces;
with Types; use Types;

package Keyboard is

   subtype Row is Natural range 0 .. 7;
   subtype Key_Bit is Natural range 0 .. 4;

   type Key_Pos is record
      R : Row := 0;
      B : Key_Bit := 0;
   end record;

   K_Caps   : constant Key_Pos := (0, 0);
   K_Sym    : constant Key_Pos := (7, 1);    --  ZX81: the "." key
   K_Enter  : constant Key_Pos := (6, 0);
   K_Space  : constant Key_Pos := (7, 0);

   function Letter (C : Character) return Key_Pos;   --  'A' .. 'Z'
   function Digit (C : Character) return Key_Pos;    --  '0' .. '9'

   --  A key with the shifts held for it
   type Combo is record
      Key  : Key_Pos;
      Caps : Boolean := False;
      Sym  : Boolean := False;
   end record;

   Positional : Boolean := False;
   --  True: host key positions = Spectrum key positions.

   --  Joystick emulation from the keypad / cursor keys and game
   --  controllers: Kempston (port &1F), Sinclair 1 (keys 6-0),
   --  Sinclair 2 (keys 1-5), Cursor / Protek (5-8, 0)
   type Joy_Type is (No_Joystick, Kempston, Sinclair_1, Sinclair_2,
                     Cursor_Joystick);
   Joystick : Joy_Type := Kempston;
   type Joy_Keyset is (Keypad, Cursor_Keys);
   Joystick_Keys : Joy_Keyset := Keypad;

   procedure Key_Event (Keyval : Interfaces.Unsigned_32; Keycode : Natural;
                        Pressed : Boolean);
   procedure Release_All;

   function Read_Rows (High : Byte) return Byte;
   --  Bits 0 .. 4 (active low, 1 = up) of the half-rows whose address
   --  line is low in High (A8 .. A15).
   function Kempston_Bits return Byte;
   --  Port &1F: bit 0 right, 1 left, 2 down, 3 up, 4 fire (1 = active).

   procedure Press (K : Key_Pos; Down : Boolean);
   function Is_Down (K : Key_Pos) return Boolean;
   procedure Set_Host_Joystick (Bits : Byte);
   --  Game controller: bit 0 up, 1 down, 2 left, 3 right, 4 fire.

   function Char_Combo (C : Character; Found : out Boolean) return Combo;
   --  The key (with shifts) that types C in the current machine's
   --  L / C mode (Spectrum) or as a ZX81 character.

   procedure Type_Combo (C : Combo; Hold_Frames : Positive := 2);
   procedure Type_Keys (S : String);
   --  Queue keys to be pressed (one per few frames); LF = ENTER.
   procedure Type_Pause (Frames : Positive);
   procedure Type_Wait (Max_Frames : Positive);
   --  Wait until Ready says the machine waits for a key again (at least
   --  a few frames, at most Max_Frames).
   type Ready_Func is access function return Boolean;
   Ready : Ready_Func := null;
   function Typing_Busy return Boolean;
   procedure Clear_Typing;
   procedure Tick_Typing;
   --  Advance typing; call once per frame.

   function Keys_Help return String;

end Keyboard;
