with Alire.Config.Edit;
with Alire.Features.Index;
with Alire.Index;
with Alire.Milestones;
with Alire.Properties;
with Alire.Roots.Optional;
with Alire.Toolchains;
with Alire.Utils.Tables;

with Alr.Bootstrap;
with Alr.Paths;

with GNAT.Compiler_Version;
with GNAT.Source_Info;

with CLIC.User_Input;

package body Alr.Commands.Version is

   package GNAT_Version is new GNAT.Compiler_Version;

   -------------
   -- Execute --
   -------------

   overriding
   procedure Execute (Cmd  : in out Command;
                      Args :        AAA.Strings.Vector)
   is
      use all type Alire.Roots.Optional.States;
      Table : Alire.Utils.Tables.Table;
      Index_Outcome : Alire.Outcome;
      Indexes : constant Alire.Features.Index.Index_On_Disk_Set :=
                  Alire.Features.Index.Find_All
                    (Alire.Config.Edit.Indexes_Directory, Index_Outcome);
      Root : constant Alire.Roots.Optional.Root :=
               Alire.Roots.Optional.Search_Root (Alire.Directories.Current);
   begin
      if Args.Count /= 0 then
         Reportaise_Wrong_Arguments (Cmd.Name & " doesn't take arguments");
      end if;

      Table.Append ("APPLICATION").Append ("").New_Row;
      Table.Append ("alr version:").Append (Alire.Version.Current).New_Row;
      Table.Append ("libalire version:")
        .Append (Alire.Version.Current).New_Row;
      Table.Append ("compilation date:")
        .Append (GNAT.Source_Info.Compilation_ISO_Date & " "
                 & GNAT.Source_Info.Compilation_Time).New_Row;
      Table.Append ("compiler version:").Append (GNAT_Version.Version).New_Row;

      Table.Append ("").New_Row;
      Table.Append ("CONFIGURATION").New_Row;
      Table.Append ("config folder:").Append (Paths.Alr_Config_Folder).New_Row;
      Table.Append ("force flag:").Append (Alire.Force'Image).New_Row;
      Table.Append ("non-interactive flag:")
        .Append (CLIC.User_Input.Not_Interactive'Image).New_Row;
      Table.Append ("community index branch:")
        .Append (Alire.Index.Community_Branch).New_Row;
      Table.Append ("indexes folder:")
        .Append (Alire.Config.Edit.Indexes_Directory).New_Row;
      Table.Append ("indexes metadata:")
        .Append (if Index_Outcome.Success
                 then "OK"
                 else "ERROR: " & Index_Outcome.Message).New_Row;
      for Index of Indexes loop
         Table.Append ("index #"
                       & AAA.Strings.Trim (Index.Priority'Image) & ":")
           .Append ("(" & Index.Name & ") " & Index.Origin).New_Row;
      end loop;
      Table.Append ("toolchain assistant:")
        .Append (if Alire.Toolchains.Assistant_Enabled
                 then "enabled"
                 else "disabled").New_Row;
      declare
         I : Positive := 1;
      begin
         for Tool of Alire.Toolchains.Tools loop
            Table
              .Append ("tool #" & AAA.Strings.Trim (I'Image)
                       & " " & Tool.As_String & ":")
              .Append (if Alire.Toolchains.Tool_Is_Configured (Tool)
                       then Alire.Toolchains.Tool_Milestone (Tool).Image
                       else "not configured").New_Row;
            I := I + 1;
         end loop;
      end;

      Table.Append ("").New_Row;
      Table.Append ("WORKSPACE").New_Row;

      Table.Append ("root status:")
        .Append (Root.Status'Image).New_Row;
      Table.Append ("root release:")
        .Append (case Root.Status is
                    when Valid  => Root.Value.Release.Milestone.Image,
                    when others => "N/A").New_Row;
      Table.Append ("root load error:")
        .Append (case Root.Status is
                    when Broken  => Cmd.Optional_Root.Message,
                    when Valid   => "none",
                    when Outside => "N/A").New_Row;
      Table.Append ("root folder:")
        .Append (case Root.Status is
                    when Outside => "N/A",
                    when Broken  => "N/A",
                    when Valid   => Root.Value.Path).New_Row;
      Table.Append ("current folder:").Append (Alire.Directories.Current)
        .New_Row;

      Table.Append ("").New_Row;
      Table.Append ("SYSTEM").New_Row;
      for Prop of Platform.Properties loop
         Table.Append (Prop.Key & ":").Append (Prop.Image).New_Row;
      end loop;

      Table.Print (Level => Always);
   exception
      when E : others =>
         Alire.Log_Exception (E);
         Trace.Error ("Unexpected error during information gathering");
         Trace.Error ("Gathered information up to the error is:");
         Table.Print (Level => Always);
         raise;
   end Execute;

   ----------------------
   -- Long_Description --
   ----------------------

   overriding
   function Long_Description (Cmd : Command)
                              return AAA.Strings.Vector is
     (AAA.Strings.Empty_Vector
      .Append ("Shows assorted metadata about the alr executable,"
               & " and about the crate or sandbox found in the current"
               & " directory, if any."));

end Alr.Commands.Version;
