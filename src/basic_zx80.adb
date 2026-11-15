with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Interfaces; use Interfaces;

package body Basic_ZX80 is

   use Ada.Strings.Unbounded;

   --  Codes 0 .. 63 (2 .. 11 are block graphics, shown as '#')
   Chars : constant String :=
     " """ & "##########" & "`$:?()-+*/=><;,." &
     "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

   function To_Code (C : Character) return Byte is
      U : constant Character := To_Upper (C);
   begin
      if U = '#' then
         return 15;
      end if;
      for K in Chars'Range loop
         if Chars (K) = U and then K - 1 not in 2 .. 11 then
            return Byte (K - 1);
         end if;
      end loop;
      return 15;           --  ?
   end To_Code;

   function From_Code (B : Byte) return Character is
     (Chars (Natural (B and 16#3F#) + 1));

   type Name is access constant String;
   function "+" (S : String) return Name is (new String'(S));

   Tokens : constant array (Byte range 16#D4# .. 16#FF#) of Name :=
     (+"""", +"THEN", +"TO", +";", +",", +")", +"(", +"NOT", +"-", +"+",
      +"*", +"/", +"AND", +"OR", +"**", +"=", +">", +"<",
      +"LIST", +"RETURN", +"CLS", +"DIM", +"SAVE", +"FOR", +"GO TO",
      +"POKE", +"INPUT", +"RANDOMISE", +"LET", +"", +"", +"NEXT", +"PRINT",
      +"", +"NEW", +"RUN", +"STOP", +"CONTINUE", +"IF", +"GO SUB", +"LOAD",
      +"CLEAR", +"REM", +"");

   function Token_Text (Code : Byte) return String is
     (if Code >= 16#D4# then Tokens (Code).all else "");

   --  SHIFT keys of the operator tokens (from the ROM's key table)
   Shift_Keys : constant array (Byte range 16#D4# .. 16#E5#) of Character :=
     ('Y', '3', '4', 'X', '.', 'O', 'I', '1', 'J', 'K', 'P', 'V', '2', 'B',
      'H', 'L', 'M', 'N');

   procedure Key_Of (Code : Byte; Kind : out Natural; Key : out Character) is
   begin
      Kind := 0;
      Key := ' ';
      if Code in 16#E6# .. 16#FF# and then Token_Text (Code) /= "" then
         Kind := 1;
         Key := Character'Val (Character'Pos ('A') + Natural (Code) - 16#E6#);
      elsif Code in Shift_Keys'Range then
         Kind := 2;
         Key := Shift_Keys (Code);
      end if;
   end Key_Of;

   function Is_Alnum (C : Character) return Boolean is
     (Is_Letter (C) or else Is_Digit (C));

   procedure Tokenize_Line
     (Text : String; Number : Natural;
      Line : out Unbounded_String; Error : out Unbounded_String) is
      P : Natural := Text'First;
      Trail : Natural := 0;       --  spaces at the end of Line
      In_Rem : Boolean := False;
      Inverse : Boolean := False;

      procedure Put (B : Byte) is
      begin
         Append (Line, Character'Val (B));
         Trail := 0;
      end Put;

      procedure Put_Char (C : Character) is
      begin
         Put (To_Code (C) or (if Inverse then 16#80# else 0));
         Inverse := False;
         if C = ' ' then
            Trail := 1;
         end if;
      end Put_Char;

      procedure Drop_Spaces is
      begin
         while Trail > 0 and then Length (Line) > 2
           and then Element (Line, Length (Line)) = Character'Val (0)
         loop
            Delete (Line, Length (Line), Length (Line));
         end loop;
         Trail := 0;
      end Drop_Spaces;

      --  The longest keyword at P (word keywords end a word)
      function Keyword (Len : out Natural) return Integer is
         Best : Integer := -1;
      begin
         Len := 0;
         for Code in Tokens'Range loop
            declare
               K : constant String := Tokens (Code).all;
               I : Natural := P;
               Ok : Boolean := K'Length > 0 and then K /= """";
            begin
               if Ok then
                  for J in K'Range loop
                     if K (J) = ' ' then
                        while I <= Text'Last and then Text (I) = ' ' loop
                           I := I + 1;
                        end loop;
                     elsif I > Text'Last or else To_Upper (Text (I)) /= K (J)
                     then
                        Ok := False;
                        exit;
                     else
                        I := I + 1;
                     end if;
                  end loop;
               end if;
               if Ok and then Is_Letter (K (K'First)) then
                  Ok := (P = Text'First or else not Is_Alnum (Text (P - 1)))
                    and then (I > Text'Last
                              or else not (Is_Alnum (Text (I))
                                           or else Text (I) = '$'));
               end if;
               if Ok and then I - P > Len then
                  Len := I - P;
                  Best := Integer (Code);
               end if;
            end;
         end loop;
         return Best;
      end Keyword;
   begin
      Line := Null_Unbounded_String;
      Error := Null_Unbounded_String;
      Put (Byte (Number / 256));
      Put (Byte (Number mod 256));
      while P <= Text'Last loop
         declare
            C : constant Character := Text (P);
            Len : Natural;
            Code : Integer;
         begin
            if In_Rem then
               Put_Char (C);
               P := P + 1;
            elsif C = '"' then
               Put (1);
               P := P + 1;
               while P <= Text'Last and then Text (P) /= '"' loop
                  if Text (P) = '%' and then P < Text'Last then
                     Inverse := True;
                  else
                     Put_Char (Text (P));
                  end if;
                  P := P + 1;
               end loop;
               if P > Text'Last then
                  Error := To_Unbounded_String ("missing closing quote");
               else
                  Put (1);
                  P := P + 1;
               end if;
            elsif C = '%' and then P < Text'Last then
               Inverse := True;
               P := P + 1;
            else
               Code := Keyword (Len);
               if Code >= 0 then
                  Drop_Spaces;
                  Put (Byte (Code));
                  P := P + Len;
                  while P <= Text'Last and then Text (P) = ' ' loop
                     P := P + 1;
                  end loop;
                  In_Rem := Code = 16#FE#;
               else
                  Put_Char (C);
                  P := P + 1;
               end if;
            end if;
         end;
      end loop;
      if not In_Rem then
         Drop_Spaces;
      end if;
      Put (16#76#);
   end Tokenize_Line;

   function List (Data : Byte_Array) return String is
      R : Unbounded_String;
      P : Natural := Data'First;
   begin
      while P + 2 <= Data'Last loop
         declare
            Num : constant Natural :=
              Natural (Data (P)) * 256 + Natural (Data (P + 1));
            L : Unbounded_String;
            In_Rem, In_Quote : Boolean := False;
         begin
            exit when Num > 9999 or else Data (P) >= 16#80#;
            P := P + 2;
            while P <= Data'Last and then Data (P) /= 16#76# loop
               declare
                  B : constant Byte := Data (P);
               begin
                  if B >= 16#D4# and then not In_Rem and then not In_Quote then
                     declare
                        K : constant String := Token_Text (B);
                     begin
                        if Is_Letter (K (K'First)) and then Length (L) > 0
                          and then Element (L, Length (L)) /= ' '
                        then
                           Append (L, ' ');
                        end if;
                        Append (L, K);
                        if Is_Letter (K (K'Last)) then
                           Append (L, ' ');
                        end if;
                        In_Rem := B = 16#FE#;
                     end;
                  elsif B = 1 then
                     Append (L, '"');
                     In_Quote := not In_Quote;
                  elsif (B and 16#7F#) < 64 then
                     if B >= 128 then
                        Append (L, '%');
                     end if;
                     if (B and 16#3F#) in 2 .. 11 then
                        Append (L, "\{" & Ada.Strings.Fixed.Trim
                                  (B'Image, Ada.Strings.Left) & "}");
                     else
                        Append (L, From_Code (B));
                     end if;
                  else
                     Append (L, "\{" & Ada.Strings.Fixed.Trim
                               (B'Image, Ada.Strings.Left) & "}");
                  end if;
               end;
               P := P + 1;
            end loop;
            P := P + 1;
            Append (R, Ada.Strings.Fixed.Trim (Num'Image, Ada.Strings.Left)
                    & " " & Ada.Strings.Fixed.Trim (To_String (L),
                                                    Ada.Strings.Right)
                    & ASCII.LF);
         end;
      end loop;
      return To_String (R);
   end List;

   function Default_Sysvars return Byte_Array is
     (0 .. 39 => 0);

   function Make_O (Prog : Byte_Array; Sysvars : Byte_Array)
                    return Byte_Array is
      Vars : constant Natural := 16#4028# + Prog'Length;
      E_Line : constant Natural := Vars + 1;
      Img : Byte_Array (0 .. E_Line - 16#4000# - 1) := (others => 0);
      procedure W (Addr, V : Natural) is
      begin
         Img (Addr - 16#4000#) := Byte (V mod 256);
         Img (Addr - 16#4000# + 1) := Byte (V / 256 mod 256);
      end W;
   begin
      Img (0 .. 39) := Sysvars (Sysvars'First .. Sysvars'First + 39);
      Img (40 .. 40 + Prog'Length - 1) := Prog;
      Img (Vars - 16#4000#) := 16#80#;
      W (16#4008#, Vars);
      W (16#400A#, E_Line);
      W (16#400C#, E_Line + 2);     --  D_FILE (rebuilt after LOAD)
      W (16#4002#, 16#FFFE#);       --  PPC: no line running
      return Img;
   end Make_O;

end Basic_ZX80;
