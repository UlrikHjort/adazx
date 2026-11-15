-- ***************************************************************************
--                             AdaZX - Fat_Image
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

--  Builds an SD card image: a FAT16 file system without a partition
--  table (a "superfloppy"), from the files and folders in host folders.
--  Names become upper case 8.3 names (long names are shortened as
--  NAME~1.EXT); hidden files (".name") are left out.  The size is 64 MB,
--  or larger (up to 1 GB) when the files need it.

package Fat_Image is

   type Folder_List is array (Positive range <>) of access constant String;

   procedure Build (Image : String; Folders : Folder_List; Ok : out Boolean);
   --  All the folders' contents are merged into the root directory.

   procedure Blank (Image : String; Ok : out Boolean);
   --  An empty 64 MB card.

   function Error_Message return String;

end Fat_Image;
