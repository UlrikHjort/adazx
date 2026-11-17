-- ***************************************************************************
--                               AdaZX - Adazx
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

--  AdaZX - a ZX Spectrum, ZX81 and ZX80 emulator written in Ada with GtkAda.
--
--  Usage: adazx [options] [file.tap|file.tzx|file.z80|file.sna|file.p|...]
--    --48 / --128 / --plus2 / --plus2a / --plus3 / --pentagon / --tc2048
--    / --16 / --48ntsc / --tc2068 / --zx81 / --zx80
--    --ulaplus          the ULAplus 64-colour palette (Spectrum models)
--                       model (default: last used, 48K)
--    --roms DIR         ROM directory (default: roms/ next to the program)
--    --1k               ZX81 / ZX80 without the 16K RAM pack
--    --zonx / --quicksilva  ZX81 / ZX80 AY sound board
--    --print-log        echo what the 48K ROM prints (RST 16) to stdout
--    --ram2000          ZX81 with 8K RAM at &2000 (hi-res programs)
--    --issue2           48K issue 2 keyboard (EAR bit)
--    --real-tape        no flash loading: load tapes in real time
--    --attach FILE      insert a tape without starting it
--    --disc FILE        insert a .dsk in drive A of the +3
--    --if1              fit the Interface 1 (48K / 128K)
--    --mdr FILE         Interface 1 with the .mdr cartridge in Microdrive 1
--    --beta             the Beta 128 disk interface (TR-DOS) on a 48K / 128K
--    --trd FILE         a .trd / .scl disc in TR-DOS drive A (and --beta)
--    --new-trd FILE     a new blank .trd in drive A
--    --disassemble FROM TO FILE  headless, at the end: memory as source
--    --entry ADDR       a code entry point for --disassemble (repeatable)
--    --mouse            the Kempston mouse (--mouse-set X Y BUTTONS: fixed)
--    --printer PNG      the ZX Printer; headless: the paper saved as PNG
--    --multiface        the Multiface 128 (roms/mf128.rom; NMI = red button)
--    --divmmc           DivMMC with esxDOS (roms/esxmmc.bin)
--    --sd FILE          DivMMC with FILE (an SD card image) in its slot
--    --sd-dir DIR       DivMMC with a card built from the folder DIR (and
--                       esxdos/ from the ROM folder: SYS, BIN, TMP)
--    --new-sd FILE      a new card image (with esxdos/ when found)
--    --nmi-at FRAME     headless: press the NMI button at FRAME
--    --new-mdr FILE     create a blank Microdrive cartridge and exit
--    --new-disc FILE    create a blank, formatted +3 .dsk and exit
--    --headless N       run N frames without GUI, then save a screenshot
--    --png FILE         screenshot file for headless mode (default shot.png)
--    --type TEXT        type TEXT at the BASIC prompt (\n = ENTER)
--    --type-at F TEXT   type TEXT at frame F (repeatable)
--    --screen           headless: print the screen text after the run
--    --wav FILE         headless: record the sound to a WAV file
--    --dump FILE        headless: write the 64K memory map after the run
--    --save-tape FILE   headless: save what was SAVEd (.tap / .p)
--    --record-rzx FILE  headless: record the run as an RZX input recording
--    --load-snapshot F / --save-snapshot F   before / after the run
--    --monitor "CMDS"   headless: monitor commands after the run (; = next)
--    --break ADDR       headless: stop at a breakpoint (hex)
--    --watch ADDR       headless: stop when ADDR is read or written (hex)
--    --break-if ADDR C  headless: stop at ADDR when the condition C holds
--    --profile          headless: profile the run, print the top 20
--    --basic SRC        tokenize a BASIC text file into a .tap / .p, exit
--    --list FILE        list the BASIC program of a .tap or .p, exit
--    --asm SRC          assemble a Z80 source file and exit
--    --forge [SRC]      open the forge (assembler IDE and debugger)

with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Directories;
with Ada.Characters.Handling;
with Ada.Streams.Stream_IO;
with Types; use Types;
with Machine;
with Config;
use type Config.Model_Type;
with Blit;
with Sound;
with Wav_Sink;
with GUI;
with Basic;
with Asm;
with Monitor_Commands;
with Interface_1;
with DivMMC;
with Peripherals;

procedure AdaZX is
   Model    : Machine.Model_Type := Machine.ZX48;
   Model_Given : Boolean := False;
   ROM_Dir  : Unbounded_String;
   Headless : Natural := 0;
   PNG      : Unbounded_String := To_Unbounded_String ("shot.png");
   File     : Unbounded_String;
   Text     : Unbounded_String;
   Wav      : Unbounded_String;
   Print_Screen : Boolean := False;
   Attach_File : Unbounded_String;
   Dump : Unbounded_String;
   Save_Tape : Unbounded_String;
   Save_Snap, Load_Snap : Unbounded_String;
   Monitor_Cmds : Unbounded_String;
   Record_RZX : Unbounded_String;
   Disc_A : Unbounded_String;
   MDR : Unbounded_String;
   Printout : Unbounded_String;      --  --printer: the paper as a PNG
   Dis_File : Unbounded_String;      --  --disassemble FROM TO FILE
   Dis_From, Dis_To : Word := 0;
   Entry_Points : Machine.Address_List (1 .. 64);
   Entry_Count : Natural := 0;
   Profile : Boolean := False;
   type Timed_Text is record
      Frame : Natural := 0;
      Text  : Unbounded_String;
   end record;
   Timed : array (1 .. 1024) of Timed_Text;
   Timed_Count : Natural := 0;
   I  : Positive := 1;
   Ok : Boolean;

   function Forge_File_Type (Path : String) return Boolean is
      L : constant String := Ada.Characters.Handling.To_Lower (Path);
      function Ends (E : String) return Boolean is
        (L'Length > E'Length
         and then L (L'Last - E'Length + 1 .. L'Last) = E);
   begin
      return Asm.Is_Source (Path) or else Basic.Is_Source (Path)
        or else Ends (".udg") or else Ends (".zxs") or else Ends (".z81s")
        or else Ends (".png");
   end Forge_File_Type;

   function Unescape (S : String) return String is
      R : Unbounded_String;
      J : Positive := S'First;
   begin
      while J <= S'Last loop
         if S (J) = '\' and then J < S'Last and then S (J + 1) = 'n' then
            Append (R, ASCII.LF);
            J := J + 2;
         else
            Append (R, S (J));
            J := J + 1;
         end if;
      end loop;
      return To_String (R);
   end Unescape;

   function Default_ROM_Dir return String is
      Exe : constant String := Command_Name;
      Dir : constant String :=
        (if Ada.Strings.Fixed.Index (Exe, "/") > 0
         then Ada.Directories.Containing_Directory (Exe) else ".");
   begin
      if Ada.Directories.Exists (Dir & "/../roms") then
         return Dir & "/../roms";
      end if;
      return "roms";
   end Default_ROM_Dir;

   Usage : constant String :=
     "Usage: adazx [options] [file]" & ASCII.LF &
     "  file: .tap .tzx .z80 .szx .sna .azx .rzx .dsk .mdr .trd .scl .p .81" & ASCII.LF &
     "        .o .80 .scr .bas .b81 .b80 .asm (started the way a user would)" & ASCII.LF &
     "" & ASCII.LF &
     "Machine" & ASCII.LF &
     "  --48 --16 --48ntsc --128 --plus2 --plus2a --plus3 --pentagon" & ASCII.LF &
     "  --tc2048 --tc2068 --zx81 --zx80     the model (default: the last used)" & ASCII.LF &
     "  --roms DIR          ROM folder (default: roms/ next to the program)" & ASCII.LF &
     "  --issue2            48K issue 2 keyboard (EAR bit)" & ASCII.LF &
     "  --1k, --ram2000     ZX81 / ZX80 without the 16K pack, ZX81 8K at &2000" & ASCII.LF &
     "  --real-tape         load tapes in real time (no flash loading)" & ASCII.LF &
     "" & ASCII.LF &
     "Add-ons" & ASCII.LF &
     "  --if1, --mdr FILE   Interface 1, a cartridge in Microdrive 1" & ASCII.LF &
     "  --disc FILE         a .dsk in the +3's drive A" & ASCII.LF &
     "  --beta, --trd FILE  Beta 128 (TR-DOS), a .trd / .scl in drive A" & ASCII.LF &
     "  --divmmc, --sd FILE, --sd-dir DIR   DivMMC (esxDOS), an SD card image or" & ASCII.LF &
     "                      a card built from a folder" & ASCII.LF &
     "  --multiface         Multiface 128 (Alt+N / --nmi-at = the red button)" & ASCII.LF &
     "  --mouse             Kempston mouse" & ASCII.LF &
     "  --printer PNG       ZX Printer (headless: the paper saved as PNG)" & ASCII.LF &
     "  --ulaplus           ULAplus palette" & ASCII.LF &
     "  --zonx, --quicksilva  ZX81 / ZX80 AY sound board" & ASCII.LF &
     "  --attach FILE       insert a tape without starting it" & ASCII.LF &
     "" & ASCII.LF &
     "Tools (no emulator window; they exit)" & ASCII.LF &
     "  --basic SRC         tokenise BASIC into a .tap / .p / .o" & ASCII.LF &
     "  --asm SRC           assemble Z80 source (binary, tape, labels)" & ASCII.LF &
     "  --list FILE         list the BASIC in a .tap / .p / .o" & ASCII.LF &
     "  --new-disc FILE, --new-mdr FILE, --new-trd FILE, --new-sd FILE" & ASCII.LF &
     "                      blank +3 disc, cartridge, TR-DOS disc, SD card" & ASCII.LF &
     "" & ASCII.LF &
     "Forge" & ASCII.LF &
     "  --forge [SRC]       open Forge (assembler IDE and debugger) with SRC" & ASCII.LF &
     "" & ASCII.LF &
     "Headless runs (tests and scripts)" & ASCII.LF &
     "  --headless N        run N frames without a window, then save a picture" & ASCII.LF &
     "  --png FILE          that picture (default shot.png)" & ASCII.LF &
     "  --screen            print the screen as text" & ASCII.LF &
     "  --wav FILE          record the sound" & ASCII.LF &
     "  --print-log         echo what the 48K ROM prints" & ASCII.LF &
     "  --type TEXT, --type-at FRAME TEXT   type at the prompt / at a frame" & ASCII.LF &
     "                      (\n = ENTER)" & ASCII.LF &
     "  --nmi-at FRAME      press NMI;  --mouse-set X Y BUTTONS  fix the mouse" & ASCII.LF &
     "  --break ADDR, --break-if ADDR CONDITION, --watch ADDR   stop there" & ASCII.LF &
     "  --profile           profile the run and print the top 20" & ASCII.LF &
     "  --disassemble FROM TO FILE [--entry ADDR ...]  memory as source" & ASCII.LF &
     "  --load-snapshot F, --save-snapshot F, --save-tape F, --record-rzx F," & ASCII.LF &
     "  --dump F            snapshot / tape / RZX / memory before / after" & ASCII.LF &
     "  --monitor ""CMDS""    monitor commands after the run (; separates, h lists)" & ASCII.LF;

   procedure Monitor_Print (S : String) is
   begin
      Put_Line (S);
   end Monitor_Print;

begin
   ROM_Dir := To_Unbounded_String (Default_ROM_Dir);
   while I <= Argument_Count loop
      declare
         A : constant String := Argument (I);
         function Next return String is
         begin
            I := I + 1;
            return (if I <= Argument_Count then Argument (I) else "");
         end Next;
      begin
         if A = "--help" or else A = "-h" then
            Put (Usage);
            return;
         elsif A = "--48" or else A = "--128" or else A = "--plus2"
           or else A = "--plus2a" or else A = "--plus3" or else A = "--zx81"
           or else A = "--zx80" or else A = "--pentagon"
           or else A = "--tc2048" or else A = "--16" or else A = "--48ntsc"
           or else A = "--tc2068"
         then
            Model := (if A = "--128" then Machine.ZX128
                      elsif A = "--plus2" then Machine.Plus2
                      elsif A = "--plus2a" then Machine.Plus2A
                      elsif A = "--plus3" then Machine.Plus3
                      elsif A = "--zx81" then Machine.ZX81
                      elsif A = "--zx80" then Config.ZX80
                      elsif A = "--pentagon" then Config.Pentagon
                      elsif A = "--tc2048" then Config.TC2048
                      elsif A = "--tc2068" then Config.TC2068
                      elsif A = "--16" then Config.ZX16
                      elsif A = "--48ntsc" then Config.ZX48_NTSC
                      else Machine.ZX48);
            Model_Given := True;
         elsif A = "--ulaplus" then
            Config.ULAplus := True;
         elsif A = "--roms" then
            ROM_Dir := To_Unbounded_String (Next);
         elsif A = "--1k" then
            Machine.ZX81_16K := False;
         elsif A = "--print-log" then
            Machine.Print_Log := True;
         elsif A = "--zonx" then
            Config.ZX81_Sound := Config.ZON_X;
         elsif A = "--quicksilva" then
            Config.ZX81_Sound := Config.Quicksilva;
         elsif A = "--ram2000" then
            Machine.ZX81_RAM_2000 := True;
         elsif A = "--issue2" then
            Machine.Issue_2 := True;
         elsif A = "--real-tape" then
            Machine.Flash_Load := False;
         elsif A = "--headless" then
            Headless := Natural'Value (Next);
         elsif A = "--png" then
            PNG := To_Unbounded_String (Next);
         elsif A = "--type" then
            Text := To_Unbounded_String (Unescape (Next));
         elsif A = "--nmi-at" then
            declare
               F : constant Natural := Natural'Value (Next);
            begin
               if Timed_Count < Timed'Last then
                  Timed_Count := Timed_Count + 1;
                  Timed (Timed_Count) :=
                    (F, To_Unbounded_String ((1 => ASCII.NUL)));
               end if;
            end;
         elsif A = "--type-at" then
            declare
               F : constant Natural := Natural'Value (Next);
               T : constant String := Unescape (Next);
            begin
               if Timed_Count < Timed'Last then
                  Timed_Count := Timed_Count + 1;
                  Timed (Timed_Count) := (F, To_Unbounded_String (T));
               end if;
            end;
         elsif A = "--attach" then
            Attach_File := To_Unbounded_String (Next);
         elsif A = "--save-tape" then
            Save_Tape := To_Unbounded_String (Next);
         elsif A = "--save-snapshot" then
            Save_Snap := To_Unbounded_String (Next);
         elsif A = "--load-snapshot" then
            Load_Snap := To_Unbounded_String (Next);
         elsif A = "--sd-dir" or else A = "--new-sd" then
            declare
               Arg : constant String := Next;
               Ok_SD : Boolean;
            begin
               if A = "--sd-dir" then
                  Machine.SD_From_Folder (Arg, Ok_SD);
               else
                  Machine.New_SD (Arg, Ok_SD);
               end if;
               if not Ok_SD then
                  Put_Line (Machine.Error_Message);
               elsif A = "--new-sd" then
                  Put_Line ("wrote " & Arg);
               end if;
            end;
         elsif A = "--beta" then
            Machine.Beta_Wanted := True;
         elsif A = "--trd" or else A = "--new-trd" then
            declare
               P : constant String := Next;
               Ok_T : Boolean := True;
            begin
               Machine.Beta_Wanted := True;
               if A = "--new-trd" then
                  Machine.Create_TRD (P, Ok_T);
               end if;
               if Ok_T then
                  Machine.Insert_TRD (0, P, Ok_T);
               end if;
               if not Ok_T then
                  Put_Line (Machine.Error_Message);
               end if;
            end;
         elsif A = "--disassemble" then          --  FROM TO FILE (hex)
            Dis_From := Word'Value ("16#" & Next & "#");
            Dis_To := Word'Value ("16#" & Next & "#");
            Dis_File := To_Unbounded_String (Next);
         elsif A = "--entry" then
            if Entry_Count < Entry_Points'Last then
               Entry_Count := Entry_Count + 1;
               Entry_Points (Entry_Count) := Word'Value ("16#" & Next & "#");
            end if;
         elsif A = "--mouse" then
            Peripherals.Mouse_On := True;
         elsif A = "--mouse-set" then              --  X Y BUTTONS (headless)
            Peripherals.Mouse_On := True;
            Peripherals.Mouse_X := Byte'Value (Next);
            Peripherals.Mouse_Y := Byte'Value (Next);
            Peripherals.Mouse_Buttons := Byte'Value (Next);
         elsif A = "--printer" then
            Peripherals.Printer_On := True;
            Printout := To_Unbounded_String (Next);
         elsif A = "--multiface" then
            Peripherals.MF_Enabled := True;
         elsif A = "--divmmc" then
            DivMMC.Enabled := True;
         elsif A = "--sd" then
            DivMMC.Enabled := True;
            declare
               P : constant String := Next;
               Ok_SD : Boolean;
            begin
               DivMMC.Insert (P, Ok_SD);
               if not Ok_SD then
                  Put_Line (DivMMC.Error_Message);
               end if;
            end;
         elsif A = "--if1" then
            Interface_1.Enabled := True;
         elsif A = "--mdr" then
            MDR := To_Unbounded_String (Next);
            Interface_1.Enabled := True;
         elsif A = "--new-mdr" then
            Machine.Create_Microdrive (Next, Ok);
            Set_Exit_Status (if Ok then 0 else 1);
            return;
         elsif A = "--disc" then
            Disc_A := To_Unbounded_String (Next);
         elsif A = "--new-disc" then
            Machine.Create_Disc (Next, Ok);
            if not Ok then
               Put_Line ("cannot create " & Argument (I));
            end if;
            Set_Exit_Status (if Ok then 0 else 1);
            return;
         elsif A = "--record-rzx" then
            Record_RZX := To_Unbounded_String (Next);
         elsif A = "--dump" then
            Dump := To_Unbounded_String (Next);
         elsif A = "--monitor" then
            Monitor_Cmds := To_Unbounded_String (Next);
         elsif A = "--watch" then
            declare
               W : constant Word := Word'Value ("16#" & Next & "#");
            begin
               Machine.Add_Watch (W, W, True, True);
            end;
         elsif A = "--break" then
            Machine.Set_Breakpoint (Word'Value ("16#" & Next & "#"));
         elsif A = "--break-if" then
            declare
               Addr : constant Word := Word'Value ("16#" & Next & "#");
               Cond : constant String := Next;
               E : constant String := Machine.Condition_Error (Cond);
            begin
               if E /= "" then
                  Put_Line ("condition: " & E);
                  Set_Exit_Status (1);
                  return;
               end if;
               Machine.Set_Breakpoint (Addr, Cond);
            end;
         elsif A = "--profile" then
            Profile := True;
         elsif A = "--forge" then
            GUI.Open_Forge := True;
            if I < Argument_Count and then Argument (I + 1) (1) /= '-' then
               GUI.Forge_File := To_Unbounded_String (Next);
            end if;
         elsif A = "--basic" then
            declare
               Src : constant String := Next;
               Out_Name : Unbounded_String;
            begin
               Basic.Report := Put_Line'Access;
               Config.Model := Model;
               Basic.Build (Src, (if Model = Config.ZX80 then Basic.ZX80
                                  elsif Model = Config.ZX81 then Basic.ZX81
                                  else Basic.Spectrum), Out_Name, Ok);
               Set_Exit_Status (if Ok then 0 else 1);
               return;
            end;
         elsif A = "--list" then
            declare
               T : constant String := Basic.List_File (Next, Ok);
            begin
               Put (T);
               Set_Exit_Status (if Ok then 0 else 1);
               return;
            end;
         elsif A = "--asm" then
            declare
               Out_Name : Unbounded_String;
            begin
               Asm.Report := Put_Line'Access;
               Asm.Target := (if Model = Config.ZX80 then Asm.ZX80
                              elsif Model = Config.ZX81 then Asm.ZX81
                              else Asm.Spectrum);
               Asm.Build (Next, Out_Name, Ok);
               Set_Exit_Status (if Ok then 0 else 1);
               return;
            end;
         elsif A = "--screen" then
            Print_Screen := True;
         elsif A = "--wav" then
            Wav := To_Unbounded_String (Next);
         elsif A'Length > 0 and then A (A'First) /= '-' then
            File := To_Unbounded_String (A);
         else
            Put_Line ("unknown option " & A);
            Set_Exit_Status (2);
            return;
         end if;
      end;
      I := I + 1;
   end loop;

   if Headless > 0 then
      Machine.Power_On (Model, To_String (ROM_Dir), Ok);
      if not Ok then
         Put_Line ("Cannot start: " & Machine.Error_Message);
         Set_Exit_Status (1);
         return;
      end if;
      if Profile then
         Machine.Profile_Start;
      end if;
      if Length (Wav) > 0 then
         Sound.Sink := Wav_Sink.Push'Access;
      end if;
      if Length (MDR) > 0 then
         Machine.Insert_Microdrive (1, To_String (MDR), Ok);
         if not Ok then
            Put_Line ("cannot insert " & To_String (MDR) & ": " &
                        Machine.Error_Message);
         end if;
      end if;
      if Length (Disc_A) > 0 then
         Machine.Insert_Disc (To_String (Disc_A), Ok);
         if not Ok then
            Put_Line ("cannot insert " & To_String (Disc_A) & ": " &
                        Machine.Error_Message);
         end if;
      end if;
      if Length (Attach_File) > 0 then
         Machine.Attach_Tape (To_String (Attach_File), Ok);
         if not Ok then
            Put_Line ("cannot attach " & To_String (Attach_File));
         end if;
      end if;
      if Length (File) > 0 then
         Machine.Autostart (To_String (File), Ok);
         if not Ok then
            Put_Line ("cannot start " & To_String (File) & ": " &
                        Machine.Error_Message);
         end if;
      end if;
      if Length (Load_Snap) > 0 then
         Machine.Load_Snapshot (To_String (Load_Snap), Ok);
         if not Ok then
            Put_Line ("cannot load snapshot: " & Machine.Error_Message);
         end if;
      end if;
      if Length (Record_RZX) > 0 then
         Machine.Start_RZX_Recording;
      end if;
      for F in 1 .. Headless loop
         if Length (Text) > 0 and then F >= 20
           and then (Machine.At_Prompt or else F >= 300)
           and then not Machine.Autostart_Busy
         then
            Machine.Type_Text (To_String (Text));
            Text := Null_Unbounded_String;
         end if;
         for T of Timed (1 .. Timed_Count) loop
            if T.Frame = F then
               if To_String (T.Text) = (1 => ASCII.NUL) then
                  Machine.NMI_Button;       --  --nmi-at
               else
                  Machine.Type_Text (To_String (T.Text));
               end if;
            end if;
         end loop;
         Machine.Run_Frame;
         exit when Machine.Break_Hit;
      end loop;
      if Machine.Break_Hit then
         Put_Line ("stopped: " & Machine.Stop_Text);
      end if;
      if Length (Dis_File) > 0 then
         declare
            Bytes : Natural;
         begin
            Machine.Export_Source
              (Dis_From, Dis_To,
               (if Entry_Count = 0 then (1 => Dis_From)
                else Entry_Points (1 .. Entry_Count)),
               To_String (Dis_File), Ok, Bytes);
            Put_Line ("disassembled to " & To_String (Dis_File) & ":" &
                      Natural'Image (Bytes) & " bytes of code");
         end;
      end if;
      if Length (Printout) > 0 then
         Peripherals.Save_Printout (To_String (Printout), Ok);
         Put_Line ("printer:" & Natural'Image (Peripherals.Printed_Lines) &
                   " lines" & (if Ok then "" else " (not written)"));
      end if;
      if Profile then
         Put_Line ("profile:" & Long_Long_Integer'Image (Machine.Profile_Total)
                   & " T-states");
         Put (Machine.Profile_Report (20));
      end if;
      if Length (Record_RZX) > 0 then
         Machine.Stop_RZX_Recording (To_String (Record_RZX), Ok);
         if not Ok then
            Put_Line ("cannot write " & To_String (Record_RZX));
         end if;
      end if;
      Blit.Save_PNG (To_String (PNG));
      if Length (Wav) > 0 then
         Wav_Sink.Save (To_String (Wav));
      end if;
      if Length (Save_Tape) > 0 then
         Machine.Save_Tape_Recording (To_String (Save_Tape), Ok);
         Put_Line ("tape recording:" & Machine.Tape_Recorded'Image &
                   " bytes" & (if Ok then "" else " (not written)"));
      end if;
      if Length (Save_Snap) > 0 then
         Machine.Save_Snapshot (To_String (Save_Snap), Ok);
         if not Ok then
            Put_Line ("cannot save snapshot: " & Machine.Error_Message);
         end if;
      end if;
      if Length (Dump) > 0 then
         declare
            package SIO renames Ada.Streams.Stream_IO;
            F : SIO.File_Type;
         begin
            SIO.Create (F, SIO.Out_File, To_String (Dump));
            for Addr in Word'Range loop
               Byte'Write (SIO.Stream (F), Machine.Peek (Addr));
            end loop;
            SIO.Close (F);
         end;
      end if;
      if Print_Screen then
         Put (Machine.Screen_Text);
      end if;
      if Length (Monitor_Cmds) > 0 then
         Monitor_Commands.Output := Monitor_Print'Unrestricted_Access;
         declare
            S : constant String := To_String (Monitor_Cmds);
            Start : Positive := S'First;
         begin
            for K in S'Range loop
               if S (K) = ';' or else K = S'Last then
                  Monitor_Commands.Execute
                    (Ada.Strings.Fixed.Trim
                       (S (Start .. (if S (K) = ';' then K - 1 else K)),
                        Ada.Strings.Both));
                  Start := K + 1;
               end if;
            end loop;
         end;
      end if;
      Put_Line (Machine.Debug_Info);
      Machine.Shutdown;
      return;
   end if;

   if Ada.Strings.Fixed.Index (Command_Name, "forge") > 0 then
      GUI.Open_Forge := True;
   end if;
   if GUI.Open_Forge and then Length (File) > 0
     and then Forge_File_Type (To_String (File))
   then
      GUI.Forge_File := File;
      File := Null_Unbounded_String;
   end if;
   GUI.Run (Model, To_String (ROM_Dir), To_String (File),
            To_String (Attach_File), Model_Given);
end AdaZX;
