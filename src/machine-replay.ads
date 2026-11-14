--  RZX input recordings: playback and recording.
--
--  An RZX file holds a snapshot and, for every frame, the number of
--  opcode fetches (M1 cycles, as counted by the R register) until the
--  frame's interrupt, and every byte the program read from a port.  On
--  playback the frame ends after that many fetches and IN returns the
--  recorded bytes, so the program runs exactly as it was recorded.

private package Machine.Replay is

   --  Playback
   procedure Open (Path : String; Ok : out Boolean);
   --  Read the recording and prepare its first part (Has_Snapshot etc.).
   function Playing return Boolean;
   procedure Stop_Playing;

   function Has_Snapshot return Boolean;
   function Snapshot_Kind return String;      --  "szx", "z80", "sna"
   function Snapshot_Data return Byte_Array;
   function Start_T return Natural;

   function Frame_Fetches return Natural;
   function Next_In return Byte;
   procedure Next_Frame (New_Part : out Boolean);
   --  Move on; New_Part: the next part of the recording starts (load its
   --  snapshot); Playing becomes False at the end.
   function Progress return String;

   --  Recording
   procedure Start_Recording (Snapshot : Byte_Array; T_Start : Natural);
   function Recording return Boolean;
   procedure Record_In (Value : Byte);
   procedure Record_Frame (Fetches : Natural);
   procedure Stop_Recording (Path : String; Ok : out Boolean);
   --  Write the recording (Path = "": discard it).

   function Error_Message return String;

end Machine.Replay;
