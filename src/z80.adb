-- ***************************************************************************
--                                AdaZX - Z80
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
with Tstates; use Tstates;

package body Z80 is

   FC : constant Byte := 16#01#;
   FN : constant Byte := 16#02#;
   FP : constant Byte := 16#04#;
   F3 : constant Byte := 16#08#;
   FH : constant Byte := 16#10#;
   F5 : constant Byte := 16#20#;
   FZ : constant Byte := 16#40#;
   FS : constant Byte := 16#80#;
   F35 : constant Byte := F3 or F5;

   type Table is array (Byte) of Byte;
   SZ53, SZ53P, Parity : Table;

   Last_Q : Byte := 0;
   Took_Int : Boolean := False;

   subtype Index_Mode is Natural range 0 .. 2;   --  HL, IX, IY

   ---------------------------------------------------------------------
   --  Bus cycles
   ---------------------------------------------------------------------

   procedure Inc_R is
   begin
      R := (R and 16#80#) or ((R + 1) and 16#7F#);
   end Inc_R;

   function IR return Word is (Make_Word (R, I));

   function Op_Fetch return Byte is
      V : Byte;
   begin
      T := T + Contend (PC) + 4;
      V := Fetch (PC);
      PC := PC + 1;
      Inc_R;
      return V;
   end Op_Fetch;

   function Rd (Addr : Word) return Byte is
   begin
      T := T + Contend (Addr) + 3;
      return Read (Addr);
   end Rd;

   procedure Wr (Addr : Word; V : Byte) is
   begin
      T := T + Contend (Addr) + 3;
      Write (Addr, V);
   end Wr;

   --  A 3 T-state memory cycle whose data is not used
   procedure Rd_Skip (Addr : Word) is
   begin
      T := T + Contend (Addr) + 3;
   end Rd_Skip;

   --  N internal cycles with Addr on the address bus (no MREQ)
   procedure NM (Addr : Word; N : Positive := 1) is
   begin
      for K in 1 .. N loop
         T := T + Contend_No_MREQ (Addr) + 1;
      end loop;
   end NM;

   function Rd_Word_PC return Word is
      Lo, Hi_B : Byte;
   begin
      Lo := Rd (PC);
      PC := PC + 1;
      Hi_B := Rd (PC);
      PC := PC + 1;
      return Make_Word (Lo, Hi_B);
   end Rd_Word_PC;

   procedure Push (V : Word) is
   begin
      SP := SP - 1;
      Wr (SP, Hi (V));
      SP := SP - 1;
      Wr (SP, Lo (V));
   end Push;

   function Pop return Word is
      Lo, Hi_B : Byte;
   begin
      Lo := Rd (SP);
      SP := SP + 1;
      Hi_B := Rd (SP);
      SP := SP + 1;
      return Make_Word (Lo, Hi_B);
   end Pop;

   procedure Set_F (V : Byte) is
   begin
      F := V;
      Q := V;
   end Set_F;

   ---------------------------------------------------------------------
   --  Registers by code
   ---------------------------------------------------------------------

   function Get_HL (X : Index_Mode) return Word is
     (case X is when 0 => HL, when 1 => IX, when 2 => IY);

   procedure Set_HL (X : Index_Mode; V : Word) is
   begin
      case X is
         when 0 => H := Hi (V); L := Lo (V);
         when 1 => IX := V;
         when 2 => IY := V;
      end case;
   end Set_HL;

   function Get_R (Code : Natural; X : Index_Mode) return Byte is
   begin
      case Code is
         when 0 => return B;
         when 1 => return C;
         when 2 => return D;
         when 3 => return E;
         when 4 => return (case X is when 0 => H, when 1 => Hi (IX),
                              when 2 => Hi (IY));
         when 5 => return (case X is when 0 => L, when 1 => Lo (IX),
                              when 2 => Lo (IY));
         when 7 => return A;
         when others => return 16#FF#;
      end case;
   end Get_R;

   procedure Set_R (Code : Natural; X : Index_Mode; V : Byte) is
   begin
      case Code is
         when 0 => B := V;
         when 1 => C := V;
         when 2 => D := V;
         when 3 => E := V;
         when 4 =>
            case X is
               when 0 => H := V;
               when 1 => IX := Make_Word (Lo (IX), V);
               when 2 => IY := Make_Word (Lo (IY), V);
            end case;
         when 5 =>
            case X is
               when 0 => L := V;
               when 1 => IX := Make_Word (V, Hi (IX));
               when 2 => IY := Make_Word (V, Hi (IY));
            end case;
         when 7 => A := V;
         when others => null;
      end case;
   end Set_R;

   --  rp table: BC, DE, HL (IX / IY), SP
   function Get_RP (P : Natural; X : Index_Mode) return Word is
     (case P is when 0 => BC, when 1 => DE, when 2 => Get_HL (X),
         when others => SP);

   procedure Set_RP (P : Natural; X : Index_Mode; V : Word) is
   begin
      case P is
         when 0 => B := Hi (V); C := Lo (V);
         when 1 => D := Hi (V); E := Lo (V);
         when 2 => Set_HL (X, V);
         when others => SP := V;
      end case;
   end Set_RP;

   function Condition (Y : Natural) return Boolean is
   begin
      case Y is
         when 0 => return (F and FZ) = 0;
         when 1 => return (F and FZ) /= 0;
         when 2 => return (F and FC) = 0;
         when 3 => return (F and FC) /= 0;
         when 4 => return (F and FP) = 0;
         when 5 => return (F and FP) /= 0;
         when 6 => return (F and FS) = 0;
         when others => return (F and FS) /= 0;
      end case;
   end Condition;

   function Disp (D_Byte : Byte) return Word is
     (if D_Byte < 128 then Word (D_Byte) else Word (D_Byte) or 16#FF00#);

   --  (IX+d) address: displacement fetch and 5 internal cycles
   function Index_Addr (X : Index_Mode) return Word is
      DB : Byte;
      Addr : Word;
   begin
      DB := Rd (PC);
      NM (PC, 5);
      PC := PC + 1;
      Addr := Get_HL (X) + Disp (DB);
      MEMPTR := Addr;
      return Addr;
   end Index_Addr;

   ---------------------------------------------------------------------
   --  Arithmetic
   ---------------------------------------------------------------------

   procedure Alu (Op : Natural; V : Byte) is
      Carry : constant Word := Word (F and FC);
      Res : Word;
      R8 : Byte;
   begin
      case Op is
         when 0 | 1 =>     --  ADD, ADC
            Res := Word (A) + Word (V) + (if Op = 1 then Carry else 0);
            R8 := Byte (Res and 16#FF#);
            Set_F (SZ53 (R8) or (if Res > 255 then FC else 0)
                   or ((A xor V xor R8) and FH)
                   or (Shift_Right ((A xor not V) and (A xor R8), 5)
                       and FP));
            A := R8;
         when 2 | 3 | 7 => --  SUB, SBC, CP
            Res := Word (A) - Word (V) - (if Op = 3 then Carry else 0);
            R8 := Byte (Res and 16#FF#);
            Set_F ((if Op = 7 then (SZ53 (R8) and not F35) or (V and F35)
                    else SZ53 (R8))
                   or FN or (if Res > 255 then FC else 0)
                   or ((A xor V xor R8) and FH)
                   or (Shift_Right ((A xor V) and (A xor R8), 5) and FP));
            if Op /= 7 then
               A := R8;
            end if;
         when 4 =>
            A := A and V;
            Set_F (SZ53P (A) or FH);
         when 5 =>
            A := A xor V;
            Set_F (SZ53P (A));
         when others =>
            A := A or V;
            Set_F (SZ53P (A));
      end case;
   end Alu;

   function Inc8 (V : Byte) return Byte is
      R8 : constant Byte := V + 1;
   begin
      Set_F ((F and FC) or (if R8 = 16#80# then FP else 0)
             or (if (R8 and 16#0F#) = 0 then FH else 0) or SZ53 (R8));
      return R8;
   end Inc8;

   function Dec8 (V : Byte) return Byte is
      R8 : constant Byte := V - 1;
   begin
      Set_F ((F and FC) or FN or (if (V and 16#0F#) = 0 then FH else 0)
             or (if R8 = 16#7F# then FP else 0) or SZ53 (R8));
      return R8;
   end Dec8;

   function Rot (Op : Natural; V : Byte) return Byte is
      R8 : Byte;
      Cy : Byte;
   begin
      case Op is
         when 0 => Cy := Shift_Right (V, 7); R8 := Shift_Left (V, 1) or Cy;
         when 1 => Cy := V and 1; R8 := Shift_Right (V, 1) or Shift_Left (Cy, 7);
         when 2 => Cy := Shift_Right (V, 7); R8 := Shift_Left (V, 1) or (F and FC);
         when 3 => Cy := V and 1;
            R8 := Shift_Right (V, 1) or Shift_Left (F and FC, 7);
         when 4 => Cy := Shift_Right (V, 7); R8 := Shift_Left (V, 1);
         when 5 => Cy := V and 1; R8 := Shift_Right (V, 1) or (V and 16#80#);
         when 6 => Cy := Shift_Right (V, 7); R8 := Shift_Left (V, 1) or 1;
         when others => Cy := V and 1; R8 := Shift_Right (V, 1);
      end case;
      Set_F (Cy or SZ53P (R8));
      return R8;
   end Rot;

   procedure Bit_Test (N : Natural; V : Byte; Bits35 : Byte) is
      Fl : Byte := (F and FC) or FH or (Bits35 and F35);
   begin
      if (V and Shift_Left (Byte'(1), N)) = 0 then
         Fl := Fl or FP or FZ;
      end if;
      if N = 7 and then (V and 16#80#) /= 0 then
         Fl := Fl or FS;
      end if;
      Set_F (Fl);
   end Bit_Test;

   procedure Add16 (X : Index_Mode; V : Word) is
      Old : constant Word := Get_HL (X);
      Res : constant Unsigned_32 := Unsigned_32 (Old) + Unsigned_32 (V);
      R16 : constant Word := Word (Res and 16#FFFF#);
   begin
      MEMPTR := Old + 1;
      Set_F ((F and (FP or FZ or FS)) or (if Res > 16#FFFF# then FC else 0)
             or (Hi (R16) and F35)
             or (Hi (Old xor V xor R16) and FH));
      Set_HL (X, R16);
   end Add16;

   procedure Adc16 (V : Word) is
      Old : constant Word := HL;
      Res : constant Unsigned_32 :=
        Unsigned_32 (Old) + Unsigned_32 (V) + Unsigned_32 (F and FC);
      R16 : constant Word := Word (Res and 16#FFFF#);
   begin
      MEMPTR := Old + 1;
      Set_F ((if Res > 16#FFFF# then FC else 0)
             or (if ((Old xor not V) and (Old xor R16) and 16#8000#) /= 0
                 then FP else 0)
             or (Hi (R16) and (F35 or FS))
             or (Hi (Old xor V xor R16) and FH)
             or (if R16 = 0 then FZ else 0));
      H := Hi (R16);
      L := Lo (R16);
   end Adc16;

   procedure Sbc16 (V : Word) is
      Old : constant Word := HL;
      Res : constant Unsigned_32 :=
        Unsigned_32 (Old) - Unsigned_32 (V) - Unsigned_32 (F and FC);
      R16 : constant Word := Word (Res and 16#FFFF#);
   begin
      MEMPTR := Old + 1;
      Set_F (FN or (if Res > 16#FFFF# then FC else 0)
             or (if ((Old xor V) and (Old xor R16) and 16#8000#) /= 0
                 then FP else 0)
             or (Hi (R16) and (F35 or FS))
             or (Hi (Old xor V xor R16) and FH)
             or (if R16 = 0 then FZ else 0));
      H := Hi (R16);
      L := Lo (R16);
   end Sbc16;

   procedure DAA is
      Add : Byte := 0;
      Carry : Byte := F and FC;
   begin
      if (F and FH) /= 0 or else (A and 16#0F#) > 9 then
         Add := 6;
      end if;
      if Carry /= 0 or else A > 16#99# then
         Add := Add or 16#60#;
      end if;
      if A > 16#99# then
         Carry := FC;
      end if;
      if (F and FN) /= 0 then
         Alu (2, Add);
      else
         Alu (0, Add);
      end if;
      Set_F ((F and not (FC or FP)) or Carry or Parity (A));
   end DAA;

   ---------------------------------------------------------------------
   --  Interrupts
   ---------------------------------------------------------------------

   procedure Leave_Halt is
   begin
      if Halted then
         Halted := False;
         PC := PC + 1;
      end if;
   end Leave_Halt;

   procedure Accept_NMI is
   begin
      Leave_Halt;
      IFF1 := False;
      Inc_R;
      T := T + 5;
      Push (PC);
      PC := 16#66#;
      MEMPTR := PC;
   end Accept_NMI;

   procedure Accept_INT is
      Data : constant Byte := Int_Data;
   begin
      Leave_Halt;
      IFF1 := False;
      IFF2 := False;
      Inc_R;
      T := T + 7;
      Push (PC);
      if IM = 2 then
         declare
            V : constant Word := Make_Word (Data, I);
            Lo_B, Hi_B : Byte;
         begin
            Lo_B := Rd (V);
            Hi_B := Rd (V + 1);
            PC := Make_Word (Lo_B, Hi_B);
         end;
      elsif IM = 0 and then (Data and 16#C7#) = 16#C7# then
         PC := Word (Data and 16#38#);     --  RST n on the bus
      else
         PC := 16#38#;
      end if;
      MEMPTR := PC;
   end Accept_INT;

   ---------------------------------------------------------------------
   --  CB prefix
   ---------------------------------------------------------------------

   procedure Exec_CB (Op : Byte) is
      X : constant Natural := Natural (Shift_Right (Op, 6));
      Y : constant Natural := Natural (Shift_Right (Op, 3) and 7);
      Z : constant Natural := Natural (Op and 7);
      V : Byte;
   begin
      if Z = 6 then
         V := Rd (HL);
         NM (HL);
         case X is
            when 0 => Wr (HL, Rot (Y, V));
            when 1 => Bit_Test (Y, V, Hi (MEMPTR));
            when 2 => Wr (HL, V and not Shift_Left (Byte'(1), Y));
            when others => Wr (HL, V or Shift_Left (Byte'(1), Y));
         end case;
      else
         V := Get_R (Z, 0);
         case X is
            when 0 => Set_R (Z, 0, Rot (Y, V));
            when 1 => Bit_Test (Y, V, V);
            when 2 => Set_R (Z, 0, V and not Shift_Left (Byte'(1), Y));
            when others => Set_R (Z, 0, V or Shift_Left (Byte'(1), Y));
         end case;
      end if;
   end Exec_CB;

   --  DD CB d op / FD CB d op
   procedure Exec_Index_CB (X_Mode : Index_Mode) is
      DB, Op : Byte;
      Addr : Word;
      V, Res : Byte;
   begin
      DB := Rd (PC);
      PC := PC + 1;
      Addr := Get_HL (X_Mode) + Disp (DB);
      MEMPTR := Addr;
      Op := Rd (PC);
      NM (PC, 2);
      PC := PC + 1;
      declare
         X : constant Natural := Natural (Shift_Right (Op, 6));
         Y : constant Natural := Natural (Shift_Right (Op, 3) and 7);
         Z : constant Natural := Natural (Op and 7);
      begin
         V := Rd (Addr);
         NM (Addr);
         if X = 1 then
            Bit_Test (Y, V, Hi (Addr));
            return;
         end if;
         case X is
            when 0 => Res := Rot (Y, V);
            when 2 => Res := V and not Shift_Left (Byte'(1), Y);
            when others => Res := V or Shift_Left (Byte'(1), Y);
         end case;
         Wr (Addr, Res);
         if Z /= 6 then
            Set_R (Z, 0, Res);       --  undocumented register copy
         end if;
      end;
   end Exec_Index_CB;

   ---------------------------------------------------------------------
   --  ED prefix
   ---------------------------------------------------------------------

   procedure Block_Op (Y, Z : Natural) is
      Inc : constant Boolean := Y = 4 or else Y = 6;
      Repeat : constant Boolean := Y >= 6;
      Delta_W : constant Word := (if Inc then 1 else 16#FFFF#);
      V, V2 : Byte;
   begin
      case Z is
         when 0 =>    --  LDI LDD LDIR LDDR
            V := Rd (HL);
            Wr (DE, V);
            NM (DE, 2);
            declare
               BC_N : constant Word := BC - 1;
            begin
               B := Hi (BC_N);
               C := Lo (BC_N);
            end;
            V := V + A;
            Set_F ((F and (FC or FZ or FS)) or (if BC /= 0 then FP else 0)
                   or (V and F3) or Shift_Left (V and 2, 4));
            if Repeat and then BC /= 0 then
               NM (DE, 5);
               PC := PC - 2;
               MEMPTR := PC + 1;
            end if;
            declare
               HL_N : constant Word := HL + Delta_W;
               DE_N : constant Word := DE + Delta_W;
            begin
               H := Hi (HL_N); L := Lo (HL_N);
               D := Hi (DE_N); E := Lo (DE_N);
            end;
         when 1 =>    --  CPI CPD CPIR CPDR
            V := Rd (HL);
            V2 := A - V;
            NM (HL, 5);
            declare
               BC_N : constant Word := BC - 1;
               Fl : Byte;
            begin
               B := Hi (BC_N);
               C := Lo (BC_N);
               Fl := (F and FC) or FN or (if BC_N /= 0 then FP else 0)
                 or ((A xor V xor V2) and FH)
                 or (if V2 = 0 then FZ else 0) or (V2 and FS);
               if (Fl and FH) /= 0 then
                  V2 := V2 - 1;
               end if;
               Fl := Fl or (V2 and F3) or Shift_Left (V2 and 2, 4);
               Set_F (Fl);
            end;
            if Repeat and then (F and (FP or FZ)) = FP then
               NM (HL, 5);
               PC := PC - 2;
               MEMPTR := PC + 1;
            else
               MEMPTR := MEMPTR + Delta_W;
            end if;
            declare
               HL_N : constant Word := HL + Delta_W;
            begin
               H := Hi (HL_N); L := Lo (HL_N);
            end;
         when 2 =>    --  INI IND INIR INDR
            NM (IR);
            V := In_Port (BC);
            Wr (HL, V);
            MEMPTR := BC + Delta_W;
            B := B - 1;
            V2 := V + (if Inc then C + 1 else C - 1);
            Set_F ((if (V and 16#80#) /= 0 then FN else 0)
                   or (if V2 < V then FH or FC else 0)
                   or Parity ((V2 and 7) xor B) or SZ53 (B));
            if Repeat and then B /= 0 then
               NM (HL, 5);
               PC := PC - 2;
            end if;
            declare
               HL_N : constant Word := HL + Delta_W;
            begin
               H := Hi (HL_N); L := Lo (HL_N);
            end;
         when others =>    --  OUTI OUTD OTIR OTDR
            NM (IR);
            V := Rd (HL);
            B := B - 1;
            MEMPTR := BC + Delta_W;
            Out_Port (BC, V);
            declare
               HL_N : constant Word := HL + Delta_W;
            begin
               H := Hi (HL_N); L := Lo (HL_N);
            end;
            V2 := V + L;
            Set_F ((if (V and 16#80#) /= 0 then FN else 0)
                   or (if V2 < V then FH or FC else 0)
                   or Parity ((V2 and 7) xor B) or SZ53 (B));
            if Repeat and then B /= 0 then
               NM (BC, 5);
               PC := PC - 2;
            end if;
      end case;
   end Block_Op;

   procedure Exec_ED (Op : Byte) is
      X : constant Natural := Natural (Shift_Right (Op, 6));
      Y : constant Natural := Natural (Shift_Right (Op, 3) and 7);
      Z : constant Natural := Natural (Op and 7);
      P : constant Natural := Y / 2;
      V : Byte;
   begin
      if X = 2 and then Z <= 3 and then Y >= 4 then
         Block_Op (Y, Z);
         return;
      elsif X /= 1 then
         return;     --  8 T-state NOP
      end if;
      case Z is
         when 0 =>    --  IN r,(C)
            MEMPTR := BC + 1;
            V := In_Port (BC);
            Set_F ((F and FC) or SZ53P (V));
            if Y /= 6 then
               Set_R (Y, 0, V);
            end if;
         when 1 =>    --  OUT (C),r
            MEMPTR := BC + 1;
            Out_Port (BC, (if Y = 6 then 0 else Get_R (Y, 0)));
         when 2 =>
            NM (IR, 7);
            if Y mod 2 = 0 then
               Sbc16 (Get_RP (P, 0));
            else
               Adc16 (Get_RP (P, 0));
            end if;
         when 3 =>
            declare
               Addr : constant Word := Rd_Word_PC;
               W : Word;
               Lo_B, Hi_B : Byte;
            begin
               if Y mod 2 = 0 then
                  W := Get_RP (P, 0);
                  Wr (Addr, Lo (W));
                  MEMPTR := Addr + 1;
                  Wr (Addr + 1, Hi (W));
               else
                  Lo_B := Rd (Addr);
                  MEMPTR := Addr + 1;
                  Hi_B := Rd (Addr + 1);
                  Set_RP (P, 0, Make_Word (Lo_B, Hi_B));
               end if;
            end;
         when 4 =>    --  NEG
            V := A;
            A := 0;
            Alu (2, V);
         when 5 =>    --  RETN / RETI
            IFF1 := IFF2;
            PC := Pop;
            MEMPTR := PC;
         when 6 =>
            IM := (case Y is when 0 | 1 | 4 | 5 => 0, when 2 | 6 => 1,
                      when others => 2);
         when others =>
            case Y is
               when 0 => NM (IR); I := A;
               when 1 => NM (IR); R := A;
               when 2 | 3 =>
                  NM (IR);
                  A := (if Y = 2 then I else R);
                  Set_F ((F and FC) or SZ53 (A)
                         or (if IFF2 then FP else 0));
               when 4 | 5 =>   --  RRD / RLD
                  V := Rd (HL);
                  NM (HL, 4);
                  if Y = 4 then
                     Wr (HL, Shift_Left (A, 4) or Shift_Right (V, 4));
                     A := (A and 16#F0#) or (V and 16#0F#);
                  else
                     Wr (HL, Shift_Left (V, 4) or (A and 16#0F#));
                     A := (A and 16#F0#) or Shift_Right (V, 4);
                  end if;
                  Set_F ((F and FC) or SZ53P (A));
                  MEMPTR := HL + 1;
               when others => null;
            end case;
      end case;
   end Exec_ED;

   ---------------------------------------------------------------------
   --  Unprefixed (and DD / FD) opcodes
   ---------------------------------------------------------------------

   procedure Jump_Rel is
      DB : Byte;
   begin
      DB := Rd (PC);
      NM (PC, 5);
      PC := PC + Disp (DB) + 1;
      MEMPTR := PC;
   end Jump_Rel;

   procedure Exec_Main (Op : Byte; Xm : Index_Mode) is
      X : constant Natural := Natural (Shift_Right (Op, 6));
      Y : constant Natural := Natural (Shift_Right (Op, 3) and 7);
      Z : constant Natural := Natural (Op and 7);
      P : constant Natural := Y / 2;
      Qb : constant Natural := Y mod 2;
      V : Byte;
      W : Word;
      Addr : Word;
   begin
      case X is
         when 0 =>
            case Z is
               when 0 =>
                  case Y is
                     when 0 => null;
                     when 1 =>
                        declare
                           TA : constant Byte := A;
                           TF : constant Byte := F;
                        begin
                           A := A2; F := F2; A2 := TA; F2 := TF;
                        end;
                     when 2 =>    --  DJNZ
                        NM (IR);
                        B := B - 1;
                        if B /= 0 then
                           Jump_Rel;
                        else
                           Rd_Skip (PC);
                           PC := PC + 1;
                        end if;
                     when 3 => Jump_Rel;
                     when others =>
                        if Condition (Y - 4) then
                           Jump_Rel;
                        else
                           Rd_Skip (PC);
                           PC := PC + 1;
                        end if;
                  end case;
               when 1 =>
                  if Qb = 0 then
                     Set_RP (P, Xm, Rd_Word_PC);
                  else
                     NM (IR, 7);
                     Add16 (Xm, Get_RP (P, Xm));
                  end if;
               when 2 =>
                  case Y is
                     when 0 | 2 =>   --  LD (BC),A / LD (DE),A
                        W := (if Y = 0 then BC else DE);
                        Wr (W, A);
                        MEMPTR := Make_Word (Lo (W + 1), A);
                     when 1 | 3 =>   --  LD A,(BC) / LD A,(DE)
                        W := (if Y = 1 then BC else DE);
                        A := Rd (W);
                        MEMPTR := W + 1;
                     when 4 =>       --  LD (nn),HL
                        Addr := Rd_Word_PC;
                        W := Get_HL (Xm);
                        Wr (Addr, Lo (W));
                        MEMPTR := Addr + 1;
                        Wr (Addr + 1, Hi (W));
                     when 5 =>       --  LD HL,(nn)
                        Addr := Rd_Word_PC;
                        V := Rd (Addr);
                        MEMPTR := Addr + 1;
                        Set_HL (Xm, Make_Word (V, Rd (Addr + 1)));
                     when 6 =>       --  LD (nn),A
                        Addr := Rd_Word_PC;
                        Wr (Addr, A);
                        MEMPTR := Make_Word (Lo (Addr + 1), A);
                     when others =>  --  LD A,(nn)
                        Addr := Rd_Word_PC;
                        A := Rd (Addr);
                        MEMPTR := Addr + 1;
                  end case;
               when 3 =>
                  NM (IR, 2);
                  Set_RP (P, Xm, Get_RP (P, Xm) +
                            (if Qb = 0 then 1 else 16#FFFF#));
               when 4 | 5 =>
                  if Y = 6 then
                     Addr := (if Xm = 0 then HL else Index_Addr (Xm));
                     V := Rd (Addr);
                     NM (Addr);
                     Wr (Addr, (if Z = 4 then Inc8 (V) else Dec8 (V)));
                  else
                     V := Get_R (Y, Xm);
                     Set_R (Y, Xm, (if Z = 4 then Inc8 (V) else Dec8 (V)));
                  end if;
               when 6 =>
                  if Y = 6 then
                     if Xm = 0 then
                        V := Rd (PC);
                        PC := PC + 1;
                        Wr (HL, V);
                     else
                        declare
                           DB : constant Byte := Rd (PC);
                        begin
                           PC := PC + 1;
                           Addr := Get_HL (Xm) + Disp (DB);
                           MEMPTR := Addr;
                           V := Rd (PC);
                           NM (PC, 2);
                           PC := PC + 1;
                           Wr (Addr, V);
                        end;
                     end if;
                  else
                     V := Rd (PC);
                     PC := PC + 1;
                     Set_R (Y, Xm, V);
                  end if;
               when others =>
                  case Y is
                     when 0 =>   --  RLCA
                        A := Shift_Left (A, 1) or Shift_Right (A, 7);
                        Set_F ((F and (FP or FZ or FS)) or (A and (F35 or FC)));
                     when 1 =>   --  RRCA
                        Set_F ((F and (FP or FZ or FS)) or (A and FC));
                        A := Shift_Right (A, 1) or Shift_Left (A, 7);
                        Set_F (F or (A and F35));
                     when 2 =>   --  RLA
                        V := A;
                        A := Shift_Left (A, 1) or (F and FC);
                        Set_F ((F and (FP or FZ or FS)) or (A and F35)
                               or Shift_Right (V, 7));
                     when 3 =>   --  RRA
                        V := A;
                        A := Shift_Right (A, 1) or Shift_Left (F and FC, 7);
                        Set_F ((F and (FP or FZ or FS)) or (A and F35)
                               or (V and FC));
                     when 4 => DAA;
                     when 5 =>   --  CPL
                        A := not A;
                        Set_F ((F and (FC or FP or FZ or FS)) or (A and F35)
                               or FN or FH);
                     when 6 =>   --  SCF
                        Set_F ((F and (FP or FZ or FS))
                               or (((Last_Q xor F) or A) and F35) or FC);
                     when others =>   --  CCF
                        Set_F ((F and (FP or FZ or FS))
                               or (if (F and FC) /= 0 then FH else FC)
                               or (((Last_Q xor F) or A) and F35));
                  end case;
            end case;

         when 1 =>
            if Op = 16#76# then
               Halted := True;
               PC := PC - 1;
            elsif Y = 6 then
               Addr := (if Xm = 0 then HL else Index_Addr (Xm));
               Wr (Addr, Get_R (Z, 0));
            elsif Z = 6 then
               Addr := (if Xm = 0 then HL else Index_Addr (Xm));
               Set_R (Y, 0, Rd (Addr));
            else
               Set_R (Y, Xm, Get_R (Z, Xm));
            end if;

         when 2 =>
            if Z = 6 then
               Addr := (if Xm = 0 then HL else Index_Addr (Xm));
               Alu (Y, Rd (Addr));
            else
               Alu (Y, Get_R (Z, Xm));
            end if;

         when others =>
            case Z is
               when 0 =>    --  RET cc
                  NM (IR);
                  if Condition (Y) then
                     PC := Pop;
                     MEMPTR := PC;
                  end if;
               when 1 =>
                  if Qb = 0 then
                     W := Pop;
                     if P = 3 then
                        A := Hi (W);
                        F := Lo (W);
                     else
                        Set_RP (P, Xm, W);
                     end if;
                  else
                     case P is
                        when 0 =>
                           PC := Pop;
                           MEMPTR := PC;
                        when 1 =>   --  EXX
                           declare
                              T1 : Byte;
                           begin
                              T1 := B; B := B2; B2 := T1;
                              T1 := C; C := C2; C2 := T1;
                              T1 := D; D := D2; D2 := T1;
                              T1 := E; E := E2; E2 := T1;
                              T1 := H; H := H2; H2 := T1;
                              T1 := L; L := L2; L2 := T1;
                           end;
                        when 2 => PC := Get_HL (Xm);
                        when others =>
                           NM (IR, 2);
                           SP := Get_HL (Xm);
                     end case;
                  end if;
               when 2 =>    --  JP cc,nn
                  MEMPTR := Rd_Word_PC;
                  if Condition (Y) then
                     PC := MEMPTR;
                  end if;
               when 3 =>
                  case Y is
                     when 0 =>
                        MEMPTR := Rd_Word_PC;
                        PC := MEMPTR;
                     when 1 => null;    --  CB handled by Step
                     when 2 =>    --  OUT (n),A
                        V := Rd (PC);
                        PC := PC + 1;
                        W := Make_Word (V, A);
                        MEMPTR := Make_Word (V + 1, A);
                        Out_Port (W, A);
                     when 3 =>    --  IN A,(n)
                        V := Rd (PC);
                        PC := PC + 1;
                        W := Make_Word (V, A);
                        MEMPTR := W + 1;
                        A := In_Port (W);
                     when 4 =>    --  EX (SP),HL
                        declare
                           Lo_B, Hi_B : Byte;
                        begin
                           W := Get_HL (Xm);
                           Lo_B := Rd (SP);
                           Hi_B := Rd (SP + 1);
                           NM (SP + 1);
                           Wr (SP + 1, Hi (W));
                           Wr (SP, Lo (W));
                           NM (SP, 2);
                           MEMPTR := Make_Word (Lo_B, Hi_B);
                           Set_HL (Xm, MEMPTR);
                        end;
                     when 5 =>    --  EX DE,HL
                        declare
                           T1 : Byte;
                        begin
                           T1 := D; D := H; H := T1;
                           T1 := E; E := L; L := T1;
                        end;
                     when 6 =>
                        IFF1 := False;
                        IFF2 := False;
                     when others =>
                        IFF1 := True;
                        IFF2 := True;
                        After_EI := True;
                  end case;
               when 4 =>    --  CALL cc,nn
                  MEMPTR := Rd_Word_PC;
                  if Condition (Y) then
                     NM (PC - 1);
                     Push (PC);
                     PC := MEMPTR;
                  end if;
               when 5 =>
                  if Qb = 0 then
                     NM (IR);
                     Push (if P = 3 then AF else Get_RP (P, Xm));
                  elsif P = 0 then    --  CALL nn
                     MEMPTR := Rd_Word_PC;
                     NM (PC - 1);
                     Push (PC);
                     PC := MEMPTR;
                  end if;
               when 6 =>
                  V := Rd (PC);
                  PC := PC + 1;
                  Alu (Y, V);
               when others =>    --  RST
                  NM (IR);
                  Push (PC);
                  PC := Word (Y * 8);
                  MEMPTR := PC;
            end case;
      end case;
   end Exec_Main;

   ---------------------------------------------------------------------

   procedure Reset is
   begin
      PC := 0;
      I := 0;
      R := 0;
      IFF1 := False;
      IFF2 := False;
      IM := 0;
      Halted := False;
      After_EI := False;
      NMI_Pending := False;
      MEMPTR := 0;
      Q := 0;
      Last_Q := 0;
      A := 16#FF#; F := 16#FF#;
      SP := 16#FFFF#;
   end Reset;

   function Interrupt_Accepted return Boolean is (Took_Int);

   procedure Step is
      Op : Byte;
      Xm : Index_Mode := 0;
   begin
      Took_Int := False;
      if NMI_Pending then
         NMI_Pending := False;
         After_EI := False;
         Q := 0;
         Accept_NMI;
         return;
      end if;
      if INT_Line and then IFF1 and then not After_EI then
         Q := 0;
         Accept_INT;
         Took_Int := True;
         return;
      end if;
      After_EI := False;
      Last_Q := Q;
      Q := 0;
      Op := Op_Fetch;
      loop
         if Op = 16#DD# then
            Xm := 1;
         elsif Op = 16#FD# then
            Xm := 2;
         else
            exit;
         end if;
         Op := Op_Fetch;
      end loop;
      case Op is
         when 16#CB# =>
            if Xm = 0 then
               Exec_CB (Op_Fetch);
            else
               Exec_Index_CB (Xm);
            end if;
         when 16#ED# =>
            Exec_ED (Op_Fetch);
         when others =>
            Exec_Main (Op, Xm);
      end case;
   end Step;

begin
   for V in Byte loop
      declare
         Bits : Natural := 0;
      begin
         for K in 0 .. 7 loop
            if (V and Shift_Left (Byte'(1), K)) /= 0 then
               Bits := Bits + 1;
            end if;
         end loop;
         Parity (V) := (if Bits mod 2 = 0 then FP else 0);
         SZ53 (V) := (V and (FS or F35)) or (if V = 0 then FZ else 0);
         SZ53P (V) := SZ53 (V) or Parity (V);
      end;
   end loop;
end Z80;
