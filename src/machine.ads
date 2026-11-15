-- ***************************************************************************
--                              AdaZX - Machine
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

--  The complete machine: CPU, memory, ULA, ports, tape and the run loop
--  for the Spectrum models and the ZX81, plus the debugger.

with Types; use Types;
with Config;
private with Z80;

package Machine is

   subtype Model_Type is Config.Model_Type;
   function ZX48 return Model_Type renames Config.ZX48;
   function ZX128 return Model_Type renames Config.ZX128;
   function Plus2 return Model_Type renames Config.Plus2;
   function Plus2A return Model_Type renames Config.Plus2A;
   function Plus3 return Model_Type renames Config.Plus3;
   function ZX81 return Model_Type renames Config.ZX81;

   procedure Power_On (M : Model_Type; ROM_Dir : String; Ok : out Boolean);
   --  Load the ROMs of the model and perform a power-on reset.

   function Model return Model_Type;
   function Is_ZX81 return Boolean;    --  ZX81 or ZX80
   function Is_ZX80 return Boolean;
   function Error_Message return String;

   procedure Reset;
   --  Power-on reset (memory cleared).

   procedure NMI_Button;
   --  An NMI (the reset-to-BASIC button of many interfaces; on a ZX81 it
   --  does nothing visible).

   procedure Run_Frame;
   --  Emulate one 50 Hz frame (returns early when the debugger stops).

   function Frame_Rate return Float;

   --  Options (take effect at the next power-on where noted)
   Issue_2 : Boolean := False;      --  48K: EAR bit as on issue 2 boards
   Print_Log : Boolean := False;
   --  echo what the 48K ROM prints through RST 16 to standard output
   --  (and keep SCR_CT up, so the ROM never stops at "scroll?")
   ZX81_16K : Boolean := True;      --  ZX81 with the 16K RAM pack (else 1K)
   ZX81_RAM_2000 : Boolean := False;   --  ZX81: 8K RAM at &2000 (hi-res)

   --  Typing and starting programs
   procedure Type_Text (S : String);
   --  Type text through the keyboard (LF = ENTER).  BASIC keywords are
   --  typed the way the machine expects them (one key in K mode on the
   --  48K / ZX81, spelt out on the 128K).
   function Typing_Busy return Boolean;
   function At_Prompt return Boolean;
   --  The machine waits for a BASIC command (K cursor, editor ready).

   procedure Autostart (Path : String; Ok : out Boolean);
   --  Reset (if needed) and load / run a tape, snapshot, .p or program.
   function Autostart_Busy return Boolean;

   procedure Inject_And_Run (Data : Byte_Array; Load : Word;
                             Command : String; With_Reset : Boolean := True;
                             Is_Basic : Boolean := False;
                             Start : Integer := -1);
   --  Reset (optional), wait for the BASIC prompt, put Data into memory at
   --  Load (Is_Basic: a tokenised program at PROG, with the system
   --  variables updated), then type Command, or jump to Start when
   --  Command is "" and Start >= 0.

   function Frame_Count return Natural;
   function Peek (Addr : Word) return Byte;     --  CPU view, no side effects
   procedure Poke (Addr : Word; Value : Byte);  --  RAM only
   function Peek_Word (Addr : Word) return Word;
   function Bank_Peek (Bank : Natural; Offset : Natural) return Byte;
   procedure Bank_Poke (Bank : Natural; Offset : Natural; Value : Byte);
   function Screen_Bank return Natural;        --  RAM bank shown (5 / 7)
   function Get_PC return Word;
   function Screen_Text return String;
   --  The screen as text lines (ROM font recognised on the Spectrum, the
   --  display file on the ZX81), for tests.
   function Screen_Contains (Text : String) return Boolean;
   function Border_Colour return Natural;

   --  Tape
   procedure Attach_Tape (Path : String; Ok : out Boolean);
   procedure Eject_Tape;
   function Tape_Name return String;
   procedure Tape_Rewind;
   procedure Tape_Play;
   procedure Tape_Stop;
   function Tape_Motor return Boolean;          --  the tape is running
   function Tape_Recorded return Natural;       --  bytes saved to tape
   procedure Save_Tape_Recording (Path : String; Ok : out Boolean);
   Flash_Load : Boolean := True;
   --  Load standard ROM blocks instantly (else in real time).
   Auto_Play : Boolean := True;
   --  Start the tape when the ROM's loader runs.

   --  +3 discs (.dsk) in drive A (0) / B (1)
   procedure Insert_Disc (Path : String; Ok : out Boolean;
                          Drive : Natural := 0);
   procedure Eject_Disc (Drive : Natural := 0);
   function Disc_Name (Drive : Natural := 0) return String;
   procedure Create_Disc (Path : String; Ok : out Boolean);
   --  A blank, formatted +3 disc image.
   function Disc_Active return Boolean;   --  the drive is working (LED)

   --  Interface 1 and Microdrives (48K / 128K / +2)
   procedure Set_Interface_1 (On : Boolean);

   --  Beta 128 disk interface (TR-DOS; built into the Pentagon)
   Beta_Wanted : Boolean := False;   --  fitted on a 48K / 128K / +2 too
   procedure Set_Beta (On : Boolean);
   procedure Set_Multiface (On : Boolean);   --  Multiface 128, from a reset
   function Beta_Fitted return Boolean;
   procedure Insert_TRD (Drive : Natural; Path : String; Ok : out Boolean);
   procedure Eject_TRD (Drive : Natural);
   function TRD_Name (Drive : Natural) return String;
   function TRD_Active return Boolean;
   procedure Create_TRD (Path : String; Ok : out Boolean);

   --  DivMMC (esxDOS) and its SD card
   procedure Set_DivMMC (On : Boolean);       --  fitted from the next reset
   function DivMMC_Fitted return Boolean;
   procedure Insert_SD (Path : String; Ok : out Boolean);
   procedure Eject_SD;
   function SD_Name return String;
   function SD_Active return Boolean;
   procedure SD_From_Folder (Dir : String; Ok : out Boolean);
   --  A card image (in ~/.cache/adazx) with the folder's files, and the
   --  esxDOS system folders when esxdos/ is in the ROM folder
   procedure New_SD (Path : String; Ok : out Boolean);
   --  A new card image with the esxDOS system folders (when found)
   --  Fit or remove the Interface 1 (a power-on follows).
   function Interface_1_Fitted return Boolean;
   procedure Insert_Microdrive (Drive : Positive; Path : String;
                                Ok : out Boolean);
   procedure Eject_Microdrive (Drive : Positive);
   function Microdrive_Name (Drive : Positive) return String;
   procedure Create_Microdrive (Path : String; Ok : out Boolean);
   function Microdrive_Active return Boolean;

   --  Snapshots: .z80 / .szx / .sna (Spectrum), .azx (AdaZX, all models),
   --  .rzx (an input recording: played back from its snapshot)
   procedure Save_Snapshot (Path : String; Ok : out Boolean);
   procedure Load_Snapshot (Path : String; Ok : out Boolean);

   --  RZX input recordings (.rzx is played through Load_Snapshot / Autostart)
   procedure Start_RZX_Recording;
   procedure Stop_RZX_Recording (Path : String; Ok : out Boolean);
   --  Path = "": discard the recording.
   function RZX_Recording return Boolean;
   function RZX_Status return String;   --  "RZX frame n / m" during playback

   --  Debugger
   procedure Step_Instruction;
   procedure Step_Over;
   procedure Step_Out;
   procedure Run_To (Addr : Word);
   procedure Request_Break;

   type Stop_Reason is (None, Breakpoint, Watch_Read, Watch_Write,
                        Step_Done, Paused, Basic_Line);
   function Last_Stop return Stop_Reason;
   function Stop_Text return String;

   --  BASIC debugging: stop when the interpreter starts a statement of a
   --  line with a breakpoint (or, after Step_Basic_Line, any other line)
   procedure Clear_Basic_Breakpoints;
   procedure Add_Basic_Breakpoint (Line_Number : Natural);
   procedure Step_Basic_Line;
   function Basic_Stop_Line return Integer;   --  -1 = none
   function Basic_Current_Line return Integer;
   --  The line BASIC is running, -1 when it is not running a program.

   procedure Add_Watch (From, To : Word; On_Read, On_Write : Boolean);
   procedure Remove_Watch (From : Word);
   procedure Clear_Watches;
   function Watch_List return String;

   procedure Set_Breakpoint (Addr : Word; Condition : String := "");
   --  With a condition (see Cond_Expr: "a = 3 and [hl] <> 0", labels of
   --  the last assembly) it stops only when that holds; setting an
   --  existing breakpoint again replaces its condition.
   function Breakpoint_Condition (Addr : Word) return String;
   function Condition_Error (Condition : String) return String;
   --  "" when the condition is valid, else what is wrong

   --  Reverse engineering: From .. To as assembler source (Disasm_Export);
   --  code from the entries and from what the profiler saw executing
   type Address_List is array (Positive range <>) of Word;
   procedure Export_Source (From, To : Word; Entries : Address_List;
                            Path : String; Ok : out Boolean;
                            Code_Bytes : out Natural);

   --  Profiler: executions and T-states per instruction address
   procedure Profile_Start;               --  clears the counts
   procedure Profile_Stop;
   function Profiling return Boolean;
   function Profile_Total return Long_Long_Integer;      --  T-states
   function Profile_Time (Addr : Word) return Long_Long_Integer;
   function Profile_Count (Addr : Word) return Natural;
   type Name_Func is access function (Addr : Word) return String;
   function Profile_Report (Top : Positive; Name : Name_Func := null)
                            return String;
   --  The Top addresses by time: share, address, T-states, executions,
   --  Name (label / source), instruction
   procedure Clear_Breakpoint (Addr : Word);
   procedure Clear_Breakpoints;
   function Breakpoint_List return String;
   function Is_Breakpoint (Addr : Word) return Boolean;
   function Break_Hit return Boolean;
   procedure Resume;
   function Register_Text return String;
   function Monitor_Peek (Addr : Word) return Byte;
   procedure Monitor_Poke (Addr : Word; Value : Byte);
   function CPU_PC return Word;
   procedure Monitor_Set_PC (Addr : Word);
   function Cycle_Count return Long_Long_Integer;
   function Debug_Info return String;

   function ROM_File (Name : String) return String;
   --  Where the ROM file Name is found ("" when it is not).

   procedure Shutdown;

private

   function Bus_Read (Addr : Word) return Byte;
   procedure Bus_Write (Addr : Word; Value : Byte);
   function Bus_Fetch (Addr : Word) return Byte;
   function Contend (Addr : Word) return Natural;
   function Contend_No_MREQ (Addr : Word) return Natural;
   function Port_In (Port : Word) return Byte;
   procedure Port_Out (Port : Word; Value : Byte);
   function Int_Data return Byte;

   package CPU is new Z80 (Bus_Read, Bus_Write, Bus_Fetch, Contend,
                           Contend_No_MREQ, Port_In, Port_Out, Int_Data);

   Last_FE : Byte := 0;            --  last value written to the ULA port

   --  ZX81 display state (saved in snapshots)
   NMI_Gen : Boolean := False;
   VSync : Boolean := False;
   Line_Counter : Natural range 0 .. 7 := 0;
   Next_HSync : Integer := 0;

   procedure Restart_Frame_State;
   --  After loading state: resynchronise ULA / sound / tape timing.

end Machine;
