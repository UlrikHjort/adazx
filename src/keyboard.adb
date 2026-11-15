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

with Interfaces; use Interfaces;
with Config;

package body Keyboard is

   type Caps_Mode is (Natural_Caps, Force_Caps, Force_No_Caps);

   type Mapping is record
      Valid : Boolean := False;
      Key   : Key_Pos;
      Has_Key : Boolean := False;
      Caps  : Caps_Mode := Natural_Caps;
      Sym   : Boolean := False;
      Joy   : Byte := 0;            --  joystick bits instead of a key
   end record;

   No_Map : constant Mapping := (others => <>);

   Active : array (0 .. 1023) of Mapping := (others => No_Map);
   type Row_Bits is array (Row) of Byte;
   Matrix : Row_Bits := (others => 0);    --  1 = down
   Extra  : Row_Bits := (others => 0);    --  Press / typing
   Host_Bits : Byte := 0;
   Joy_Bits  : Byte := 0;          --  bit 0 up, 1 down, 2 left, 3 right, 4 fire

   Letters : constant array (Character range 'A' .. 'Z') of Key_Pos :=
     ((1, 0), (7, 4), (0, 3), (1, 2), (2, 2), (1, 3), (1, 4), (6, 4),
      (5, 2), (6, 3), (6, 2), (6, 1), (7, 2), (7, 3), (5, 1), (5, 0),
      (2, 0), (2, 3), (1, 1), (2, 4), (5, 3), (0, 4), (2, 1), (0, 2),
      (5, 4), (0, 1));
   Digit_Keys : constant array (Character range '0' .. '9') of Key_Pos :=
     ((4, 0), (3, 0), (3, 1), (3, 2), (3, 3), (3, 4), (4, 4), (4, 3),
      (4, 2), (4, 1));

   function Letter (C : Character) return Key_Pos is (Letters (C));
   function Digit (C : Character) return Key_Pos is (Digit_Keys (C));

   function Key (P : Key_Pos; C : Caps_Mode := Natural_Caps;
                 Sym : Boolean := False) return Mapping is
     ((Valid => True, Key => P, Has_Key => True, Caps => C, Sym => Sym,
       Joy => 0));
   function SS (P : Key_Pos) return Mapping is
     (Key (P, Force_No_Caps, True));
   function CS (P : Key_Pos) return Mapping is (Key (P, Force_Caps));
   function Joy (Bits : Byte) return Mapping is
     ((Valid => True, Key => (0, 0), Has_Key => False,
       Caps => Natural_Caps, Sym => False, Joy => Bits));

   --  GDK key values
   GDK_BackSpace : constant := 16#FF08#;
   GDK_Tab       : constant := 16#FF09#;
   GDK_Return    : constant := 16#FF0D#;
   GDK_Escape    : constant := 16#FF1B#;
   GDK_Home      : constant := 16#FF50#;
   GDK_Left      : constant := 16#FF51#;
   GDK_Up        : constant := 16#FF52#;
   GDK_Right     : constant := 16#FF53#;
   GDK_Down      : constant := 16#FF54#;
   GDK_Page_Up   : constant := 16#FF55#;
   GDK_Page_Down : constant := 16#FF56#;
   GDK_End       : constant := 16#FF57#;
   GDK_Insert    : constant := 16#FF63#;
   GDK_Delete    : constant := 16#FFFF#;
   GDK_KP_Enter  : constant := 16#FF8D#;
   GDK_KP_Home   : constant := 16#FF95#;
   GDK_KP_Left   : constant := 16#FF96#;
   GDK_KP_Up     : constant := 16#FF97#;
   GDK_KP_Right  : constant := 16#FF98#;
   GDK_KP_Down   : constant := 16#FF99#;
   GDK_KP_Page_Up : constant := 16#FF9A#;
   GDK_KP_Page_Down : constant := 16#FF9B#;
   GDK_KP_End    : constant := 16#FF9C#;
   GDK_KP_Begin  : constant := 16#FF9D#;
   GDK_KP_Insert : constant := 16#FF9E#;
   GDK_KP_0      : constant := 16#FFB0#;
   GDK_Shift_L   : constant := 16#FFE1#;
   GDK_Shift_R   : constant := 16#FFE2#;
   GDK_Control_L : constant := 16#FFE3#;
   GDK_Control_R : constant := 16#FFE4#;
   GDK_Caps_Lock : constant := 16#FFE5#;
   GDK_Alt_R     : constant := 16#FFEA#;
   GDK_Sterling  : constant := 16#00A3#;

   J_Up    : constant Byte := 1;
   J_Down  : constant Byte := 2;
   J_Left  : constant Byte := 4;
   J_Right : constant Byte := 8;
   J_Fire  : constant Byte := 16;

   function Joystick_Mapping (KV : Unsigned_32) return Mapping is
   begin
      if Joystick = No_Joystick then
         return No_Map;
      end if;
      case Joystick_Keys is
         when Keypad =>
            case KV is
               when GDK_KP_0 + 8 | GDK_KP_Up => return Joy (J_Up);
               when GDK_KP_0 + 2 | GDK_KP_Down => return Joy (J_Down);
               when GDK_KP_0 + 4 | GDK_KP_Left => return Joy (J_Left);
               when GDK_KP_0 + 6 | GDK_KP_Right => return Joy (J_Right);
               when GDK_KP_0 + 7 | GDK_KP_Home => return Joy (J_Up or J_Left);
               when GDK_KP_0 + 9 | GDK_KP_Page_Up =>
                  return Joy (J_Up or J_Right);
               when GDK_KP_0 + 1 | GDK_KP_End => return Joy (J_Down or J_Left);
               when GDK_KP_0 + 3 | GDK_KP_Page_Down =>
                  return Joy (J_Down or J_Right);
               when GDK_KP_0 | GDK_KP_Insert | GDK_KP_0 + 5 | GDK_KP_Begin
                  | GDK_KP_Enter =>
                  return Joy (J_Fire);
               when others => return No_Map;
            end case;
         when Cursor_Keys =>
            case KV is
               when GDK_Up => return Joy (J_Up);
               when GDK_Down => return Joy (J_Down);
               when GDK_Left => return Joy (J_Left);
               when GDK_Right => return Joy (J_Right);
               when GDK_Alt_R => return Joy (J_Fire);
               when others => return No_Map;
            end case;
      end case;
   end Joystick_Mapping;

   --  Characters on a Spectrum (L mode; SYMBOL SHIFT symbols)
   function Spectrum_Char (C : Character) return Mapping is
   begin
      case C is
         when 'a' .. 'z' =>
            return Key (Letters (Character'Val (Character'Pos (C) - 32)),
                        Force_No_Caps);
         when 'A' .. 'Z' => return CS (Letters (C));
         when '0' .. '9' => return Key (Digit_Keys (C), Force_No_Caps);
         when ' ' => return Key (K_Space, Force_No_Caps);
         when ':' => return SS (Letters ('Z'));
         when '?' => return SS (Letters ('C'));
         when '/' => return SS (Letters ('V'));
         when '<' => return SS (Letters ('R'));
         when '>' => return SS (Letters ('T'));
         when '!' => return SS (Digit_Keys ('1'));
         when '@' => return SS (Digit_Keys ('2'));
         when '#' => return SS (Digit_Keys ('3'));
         when '$' => return SS (Digit_Keys ('4'));
         when '%' => return SS (Digit_Keys ('5'));
         when '&' => return SS (Digit_Keys ('6'));
         when ''' => return SS (Digit_Keys ('7'));
         when '(' => return SS (Digit_Keys ('8'));
         when ')' => return SS (Digit_Keys ('9'));
         when '_' => return SS (Digit_Keys ('0'));
         when '"' => return SS (Letters ('P'));
         when ';' => return SS (Letters ('O'));
         when '=' => return SS (Letters ('L'));
         when '+' => return SS (Letters ('K'));
         when '-' => return SS (Letters ('J'));
         when '^' => return SS (Letters ('H'));
         when '.' => return SS (Letters ('M'));
         when ',' => return SS (Letters ('N'));
         when '*' => return SS (Letters ('B'));
         when '`' => return SS (Letters ('X'));      --  pound sign
         when others => return No_Map;
      end case;
   end Spectrum_Char;

   --  Characters on a ZX81 (capitals only; SHIFT symbols)
   function ZX81_Char (C : Character) return Mapping is
      SH : constant array (Character range ' ' .. '`') of Character :=
        (' ' => ' ', ':' => 'Z', ';' => 'X', '?' => 'C', '/' => 'V',
         '"' => 'P', ')' => 'O', '(' => 'I', '$' => 'U', '=' => 'L',
         '+' => 'K', '-' => 'J', '*' => 'B', '<' => 'N', '>' => 'M',
         ',' => '.', '`' => ' ', others => '#');
   begin
      case C is
         when 'a' .. 'z' =>
            return Key (Letters (Character'Val (Character'Pos (C) - 32)),
                        Force_No_Caps);
         when 'A' .. 'Z' => return Key (Letters (C), Force_No_Caps);
         when '0' .. '9' => return Key (Digit_Keys (C), Force_No_Caps);
         when ' ' => return Key (K_Space, Force_No_Caps);
         when '.' => return Key (K_Sym, Force_No_Caps);
         when '`' => return Key (K_Space, Force_Caps);   --  pound sign
         when ',' => return Key (K_Sym, Force_Caps);
         when others =>
            if Config.Is_ZX80 and then C = '"' then
               return Key (Letters ('Y'), Force_Caps);
            elsif Config.Is_ZX80 and then C = '*' then
               return Key (Letters ('P'), Force_Caps);
            elsif C in SH'Range and then SH (C) in 'A' .. 'Z' then
               return Key (Letters (SH (C)), Force_Caps);
            end if;
            return No_Map;
      end case;
   end ZX81_Char;

   function Char_Map (C : Character) return Mapping is
     (if Config.Is_ZX81 then ZX81_Char (C) else Spectrum_Char (C));

   function Char_Combo (C : Character; Found : out Boolean) return Combo is
      M : constant Mapping := Char_Map (C);
   begin
      Found := M.Valid;
      return (Key => M.Key, Caps => M.Caps = Force_Caps, Sym => M.Sym);
   end Char_Combo;

   function Map_Key (KV : Unsigned_32) return Mapping is
      J : constant Mapping := Joystick_Mapping (KV);
      ZX81 : constant Boolean := Config.Is_ZX81;
   begin
      if J.Valid then
         return J;
      end if;
      if KV in 16#20# .. 16#7E# then
         return Char_Map (Character'Val (KV));
      end if;
      case KV is
         when GDK_Return | GDK_KP_Enter => return Key (K_Enter);
         when GDK_BackSpace | GDK_Delete => return CS (Digit_Keys ('0'));
         when GDK_Left => return CS (Digit_Keys ('5'));
         when GDK_Down => return CS (Digit_Keys ('6'));
         when GDK_Up => return CS (Digit_Keys ('7'));
         when GDK_Right => return CS (Digit_Keys ('8'));
         when GDK_Shift_L | GDK_Shift_R => return Key (K_Caps);
         when GDK_Control_L | GDK_Control_R =>
            return (if ZX81 then Key (K_Caps) else Key (K_Sym));
         when GDK_Escape =>        --  BREAK
            return (if ZX81 then Key (K_Space) else CS (K_Space));
         when GDK_Tab =>           --  extended mode / FUNCTION
            return (if ZX81 then CS (K_Enter)
                    else Key (K_Sym, Force_Caps, True));
         when GDK_Caps_Lock =>
            return (if ZX81 then No_Map else CS (Digit_Keys ('2')));
         when GDK_Home | GDK_Insert =>     --  EDIT
            return CS (Digit_Keys ('1'));
         when GDK_End | GDK_Page_Down =>   --  GRAPHICS
            return CS (Digit_Keys ('9'));
         when GDK_Sterling => return Char_Map ('`');
         when others => return No_Map;
      end case;
   end Map_Key;

   --  Positional mapping by X11 hardware keycode (evdev code + 8)
   function Positional_Map (Code : Natural) return Mapping is
      Top : constant String := "QWERTYUIOP";
      Mid : constant String := "ASDFGHJKL";
      Bot : constant String := "ZXCVBNM";
   begin
      case Code is
         when 10 .. 18 => return Key (Digit_Keys (Character'Val (48 + Code - 9)));
         when 19 => return Key (Digit_Keys ('0'));
         when 24 .. 33 => return Key (Letters (Top (Code - 23)));
         when 38 .. 46 => return Key (Letters (Mid (Code - 37)));
         when 52 .. 58 => return Key (Letters (Bot (Code - 51)));
         when 36 | 104 => return Key (K_Enter);
         when 65 => return Key (K_Space);
         when 50 => return Key (K_Caps);
         when 62 | 37 | 105 | 59 | 60 => return Key (K_Sym);
         when 22 => return CS (Digit_Keys ('0'));
         when others => return No_Map;
      end case;
   end Positional_Map;

   procedure Set_Bit (M : in out Byte; B : Key_Bit; Down : Boolean) is
   begin
      if Down then
         M := M or Shift_Left (1, B);
      else
         M := M and not Shift_Left (1, B);
      end if;
   end Set_Bit;

   procedure Rebuild is
      Force_C, Force_NC, Force_S : Boolean := False;
      J : Byte := Host_Bits;
   begin
      Matrix := Extra;
      for M of Active loop
         if M.Valid then
            if M.Joy /= 0 then
               J := J or M.Joy;
            elsif M.Has_Key then
               Set_Bit (Matrix (M.Key.R), M.Key.B, True);
               case M.Caps is
                  when Force_Caps => Force_C := True;
                  when Force_No_Caps => Force_NC := True;
                  when Natural_Caps => null;
               end case;
               Force_S := Force_S or else M.Sym;
            end if;
         end if;
      end loop;
      if Force_C then
         Set_Bit (Matrix (0), 0, True);
      elsif Force_NC then
         Set_Bit (Matrix (0), 0, False);
      end if;
      if Force_S then
         Set_Bit (Matrix (K_Sym.R), K_Sym.B, True);
      end if;
      Joy_Bits := J;
      --  Joysticks that are keys
      declare
         procedure Joy_Key (Mask : Byte; D : Character) is
         begin
            if (J and Mask) /= 0 then
               Set_Bit (Matrix (Digit_Keys (D).R), Digit_Keys (D).B, True);
            end if;
         end Joy_Key;
      begin
         case Joystick is
            when Sinclair_1 =>
               Joy_Key (J_Left, '6'); Joy_Key (J_Right, '7');
               Joy_Key (J_Down, '8'); Joy_Key (J_Up, '9');
               Joy_Key (J_Fire, '0');
            when Sinclair_2 =>
               Joy_Key (J_Left, '1'); Joy_Key (J_Right, '2');
               Joy_Key (J_Down, '3'); Joy_Key (J_Up, '4');
               Joy_Key (J_Fire, '5');
            when Cursor_Joystick =>
               Joy_Key (J_Left, '5'); Joy_Key (J_Down, '6');
               Joy_Key (J_Up, '7'); Joy_Key (J_Right, '8');
               Joy_Key (J_Fire, '0');
            when others => null;
         end case;
      end;
   end Rebuild;

   procedure Key_Event (Keyval : Unsigned_32; Keycode : Natural;
                        Pressed : Boolean) is
      Code : constant Natural := Keycode mod Active'Length;
   begin
      if Pressed then
         declare
            J : constant Mapping := Joystick_Mapping (Keyval);
            PM : constant Mapping :=
              (if Positional and then not J.Valid
               then Positional_Map (Keycode) else No_Map);
            M : constant Mapping :=
              (if PM.Valid then PM else Map_Key (Keyval));
         begin
            if M.Valid then
               Active (Code) := M;
            end if;
         end;
      else
         Active (Code) := No_Map;
      end if;
      Rebuild;
   end Key_Event;

   procedure Release_All is
   begin
      Active := (others => No_Map);
      Extra := (others => 0);
      Rebuild;
   end Release_All;

   procedure Press (K : Key_Pos; Down : Boolean) is
   begin
      Set_Bit (Extra (K.R), K.B, Down);
      Rebuild;
   end Press;

   function Is_Down (K : Key_Pos) return Boolean is
     ((Matrix (K.R) and Shift_Left (1, K.B)) /= 0);

   procedure Set_Host_Joystick (Bits : Byte) is
   begin
      if Bits /= Host_Bits then
         Host_Bits := Bits;
         Rebuild;
      end if;
   end Set_Host_Joystick;

   function Read_Rows (High : Byte) return Byte is
      V : Byte := 0;
   begin
      for R in Row loop
         if (High and Shift_Left (1, R)) = 0 then
            V := V or Matrix (R);
         end if;
      end loop;
      return (not V) and 16#1F#;
   end Read_Rows;

   function Kempston_Bits return Byte is
   begin
      if Joystick /= Kempston then
         return 0;
      end if;
      return (if (Joy_Bits and J_Right) /= 0 then 1 else 0)
        or (if (Joy_Bits and J_Left) /= 0 then 2 else 0)
        or (if (Joy_Bits and J_Down) /= 0 then 4 else 0)
        or (if (Joy_Bits and J_Up) /= 0 then 8 else 0)
        or (if (Joy_Bits and J_Fire) /= 0 then 16 else 0);
   end Kempston_Bits;

   ---------------------------------------------------------------------
   --  Typing
   ---------------------------------------------------------------------

   type Entry_Type is record
      C : Combo;
      Frames : Natural := 2;
      Pause : Boolean := False;
   end record;

   Queue : array (1 .. 16_384) of Entry_Type;
   Q_Len, Q_Pos : Natural := 0;
   Phase : Natural := 0;
   Holding : Boolean := False;

   procedure Add (E : Entry_Type) is
   begin
      if Q_Len < Queue'Last then
         Q_Len := Q_Len + 1;
         Queue (Q_Len) := E;
      end if;
   end Add;

   procedure Type_Combo (C : Combo; Hold_Frames : Positive := 2) is
   begin
      Add ((C => C, Frames => Hold_Frames, Pause => False));
   end Type_Combo;

   procedure Type_Pause (Frames : Positive) is
   begin
      Add ((C => (others => <>), Frames => Frames, Pause => True));
   end Type_Pause;

   procedure Type_Keys (S : String) is
      Found : Boolean;
      C : Combo;
   begin
      for Ch of S loop
         if Ch = ASCII.LF or else Ch = ASCII.CR then
            Type_Combo ((Key => K_Enter, others => False));
         else
            C := Char_Combo (Ch, Found);
            if Found then
               Type_Combo (C);
            end if;
         end if;
      end loop;
   end Type_Keys;

   function Typing_Busy return Boolean is (Q_Pos < Q_Len);

   procedure Clear_Typing is
   begin
      Q_Len := 0;
      Q_Pos := 0;
      Phase := 0;
      if Holding then
         Extra := (others => 0);
         Holding := False;
         Rebuild;
      end if;
   end Clear_Typing;

   procedure Set_Combo (C : Combo; Down : Boolean) is
   begin
      Set_Bit (Extra (C.Key.R), C.Key.B, Down);
      if C.Caps then
         Set_Bit (Extra (0), 0, Down);
      end if;
      if C.Sym then
         Set_Bit (Extra (K_Sym.R), K_Sym.B, Down);
      end if;
      Rebuild;
   end Set_Combo;

   procedure Tick_Typing is
   begin
      if Q_Pos >= Q_Len then
         Q_Pos := 0;
         Q_Len := 0;
         return;
      end if;
      declare
         E : Entry_Type renames Queue (Q_Pos + 1);
         Release : constant Natural :=
           (if Config.Is_ZX80 then 10
            elsif Config.Is_ZX81 then 6
            elsif Q_Pos + 2 <= Q_Len
              and then Queue (Q_Pos + 2).C.Key = E.C.Key
              and then not Queue (Q_Pos + 2).Pause
            then 6 else 2);
      begin
         Phase := Phase + 1;
         if E.Pause then
            if Phase >= E.Frames then
               Phase := 0;
               Q_Pos := Q_Pos + 1;
            end if;
            return;
         end if;
         if Phase = 1 then
            if Config.Is_ZX81 and then E.Frames < 4 then
               E.Frames := 4;    --  the ZX81 reads the keyboard slowly
            end if;
            if Config.Is_ZX80 and then E.Frames < 10 then
               E.Frames := 10;   --  the ZX80 debounces over several frames
            end if;
            Set_Combo (E.C, True);
            Holding := True;
         elsif Phase = 1 + E.Frames then
            Set_Combo (E.C, False);
            Holding := False;
         elsif Phase >= 1 + E.Frames + Release then
            Phase := 0;
            Q_Pos := Q_Pos + 1;
         end if;
      end;
   end Tick_Typing;

   function Keys_Help return String is
     ("Keyboard mapping is symbolic: type the character you mean." &
      ASCII.LF &
      "Shift = CAPS SHIFT, Ctrl = SYMBOL SHIFT (ZX81: Shift / Ctrl = SHIFT)," &
      ASCII.LF &
      "Tab = extended mode (ZX81: FUNCTION), Backspace = DELETE," &
      ASCII.LF &
      "cursor keys = CAPS SHIFT + 5-8, Esc = BREAK, Home = EDIT," &
      ASCII.LF &
      "End = GRAPHICS, Caps Lock = CAPS LOCK, ` = pound sign." & ASCII.LF &
      "Joystick (Kempston, Sinclair or Cursor; Input menu): keypad" &
      ASCII.LF &
      "8/2/4/6 (diagonals 7/9/1/3), fire = keypad 0/5/Enter.");

end Keyboard;
