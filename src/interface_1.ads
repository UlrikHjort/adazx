--  Sinclair ZX Interface 1 with up to eight Microdrives (48K / 128K).
--
--  The Interface 1's 8K ROM is paged in over the Spectrum ROM when the
--  CPU fetches an opcode from &0008 (the error restart, where the shadow
--  ROM catches the new BASIC syntax) or &1708 (CLOSE #), and paged out
--  after the opcode fetch at &0700.  Ports (A0 = 1): &E7 Microdrive
--  data, &EF control / status, &F7 network and RS232 (not connected).
--
--  Microdrive cartridges are .mdr files: blocks of 543 bytes (a 15 byte
--  header record and a 528 byte data record) and a write-protect byte.
--  The tape loop is modelled the way Fuse does it: the head moves on as
--  bytes are transferred, the GAP and SYNC status bits come and go as the
--  ROM polls the control port, and every control port access puts the
--  head at the start of the current record.

with Types; use Types;

package Interface_1 is

   Enabled : Boolean := False;     --  fitted (takes effect at reset)

   procedure Load_ROM (Path : String; Ok : out Boolean);
   function ROM_Loaded return Boolean;

   Paged : Boolean := False;       --  the shadow ROM is mapped in
   function ROM_Byte (Addr : Word) return Byte with Inline;

   procedure Reset;

   function Port_Selected (Port : Word) return Boolean with Inline;
   function Port_In (Port : Word) return Byte;
   procedure Port_Out (Port : Word; Value : Byte);

   --  Cartridges in drives 1 .. 8
   subtype Drive_Number is Positive range 1 .. 8;
   procedure Insert (Drive : Drive_Number; Path : String; Ok : out Boolean);
   procedure Eject (Drive : Drive_Number);
   function Name (Drive : Drive_Number) return String;
   procedure Create (Path : String; Ok : out Boolean);
   --  A blank (unformatted) cartridge of 180 blocks.
   function Motor_On return Boolean;
   procedure Flush_All;
   function Error_Message return String;

end Interface_1;
