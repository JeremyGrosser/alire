with GNAT.OS_Lib;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Alire_Early_Elaboration;
with Alire.Environment.Formatting;
with Alire.Errors;
with Alire.Properties.Environment; use Alire.Properties.Environment;
with Alire.OS_Lib;
with Alire.GPR;
with Alire.Properties.Scenarios;
with Alire.Releases;
with Alire.Roots.Editable;
with Alire.Solutions;
with Alire.Toolchains.Solutions;
with Alire.Utils.TTY;
with Alire.Platforms.Current;

with GNAT.IO;

package body Alire.Environment is

   ---------------------
   -- Already_Defines --
   ---------------------

   function Already_Defines (Existing, Value : String) return Boolean
   --  Check that Value is a path-delimited identical value in Existing
   is (for some Part of AAA.Strings.Vector'
         (AAA.Strings.Split (Existing, GNAT.OS_Lib.Path_Separator)) =>
          Part = Value);

   ---------
   -- Add --
   ---------

   procedure Add (This : in out Context; Name : String; Action : Env_Action) is
   begin
      if not This.Actions.Contains (+Name) then
         declare
            Empty_Vect : Action_Vectors.Vector;
         begin
            This.Actions.Include (+Name, Empty_Vect);
         end;
      end if;

      This.Actions.Reference (+Name).Append (Action);
   end Add;

   ---------
   -- Set --
   ---------

   procedure Set (This : in out Context; Name, Value, Origin : String) is
      Action : constant Env_Action := (Set, +Value, +Origin);
   begin
      This.Add (Name, Action);
   end Set;

   ------------
   -- Append --
   ------------

   procedure Append (This : in out Context; Name, Value, Origin : String) is
      Action : constant Env_Action := (Append, +Value, +Origin);
   begin
      This.Add (Name, Action);
   end Append;

   -------------
   -- Prepend --
   -------------

   procedure Prepend (This : in out Context; Name, Value, Origin : String) is
      Action : constant Env_Action := (Prepend, +Value, +Origin);
   begin
      This.Add (Name, Action);
   end Prepend;

   ----------
   -- Load --
   ----------

   Already_Warned : Boolean := False;

   procedure Load (This : in out Context;
                   Root : in out Alire.Roots.Root)
   is
      Solution : constant Solutions.Solution :=
                   Toolchains.Solutions.Add_Toolchain (Root.Solution);
      Tool_Root : Roots.Editable.Root :=
                    Roots.Editable.New_Root (Root);
      --  We use a copy of the base root to add the toolchain elements that
      --  might be missing from its solution
   begin
      Tool_Root.Set (Solution);

      --  Load platform environment
      Alire.Platforms.Current.Load_Environment (This);

      --  Warnings when setting up an incomplete environment

      if not Solution.Is_Complete then
         Trace.Debug ("Generating possibly incomplete environment"
                      & " because of missing dependencies");

         --  Normally we would generate a warning, but since that will pollute
         --  the output making it unusable, for once we write directly to
         --  stderr (unless quiet is in effect):

         if not Alire_Early_Elaboration.Switch_Q and then not Already_Warned
         then
            Already_Warned := True;

            GNAT.IO.Put_Line
              (GNAT.IO.Standard_Error,
               TTY.Warn ("warn:")
               & " Generating possibly incomplete environment"
               & " because of missing dependencies");
         end if;
      end if;

      --  Project paths for all releases in the solution, implicitly defined by
      --  supplied project files.

      declare
         Sorted_Paths : constant AAA.Strings.Set :=
                          Tool_Root.Current.Project_Paths;
      begin
         if not Sorted_Paths.Is_Empty then
            for Path of Sorted_Paths loop
               This.Append ("GPR_PROJECT_PATH", Path, "crates");
            end loop;
         end if;
      end;

      --  Custom definitions provided by each release

      for Rel of Solution.Releases.Including (Root.Release) loop
         This.Load (Root            => Tool_Root,
                    Crate           => Rel.Name);
      end loop;

      This.Set ("ALIRE", "True", "Alire");
   end Load;

   ----------
   -- Load --
   ----------

   procedure Load (This            : in out Context;
                   Root            : in out Roots.Editable.Root;
                   Crate           : Crate_Name)
   is
      Env    : constant Properties.Vector := Root.Current.Environment;
      Rel    : constant Releases.Release := Root.Current.Release (Crate);
      Origin : constant String := Rel.Name_Str;

      Release_Base : constant String := Root.Current.Release_Base (Rel.Name);
   begin
      Trace.Debug ("Loading environment for crate "
                   & Alire.Utils.TTY.Name (Crate)
                   & " release: " & Rel.Milestone.TTY_Image);

      --  Environment variables defined in the crate manifest
      for Act of Rel.Environment (Env) loop
         Trace.Debug ("Processing env entry: " & Act.Name
                      & " of type " & Act.Action'Image
                      & " with value " & Act.Value);
         begin
            declare
               Value : constant String :=
                 Formatting.Format (Release_Base, Act.Value);
            begin
               case Act.Action is

               when Properties.Environment.Set =>

                  This.Set (Act.Name, Value, Origin & " (env)");

               when Properties.Environment.Append =>

                  This.Append (Act.Name, Value, Origin & " (env)");

               when Properties.Environment.Prepend =>

                  This.Prepend (Act.Name, Value, Origin & " (env)");

               end case;
            end;
         exception
            when Formatting.Unknown_Formatting_Key =>
               Raise_Checked_Error
                 ("Unknown environment variable formatting key in var '" &
                    Act.Name & " of '" & Origin & "'");
         end;
      end loop;

      --  Environment variables for GPR external scenario variables
      for Property of Rel.On_Platform_Properties (Env) loop
         if Property in Alire.Properties.Scenarios.Property'Class then
            declare
               use all type Alire.GPR.Variable_Kinds;
               Variable : constant Alire.GPR.Variable :=
                 Alire.Properties.Scenarios.Property (Property).Value;
            begin
               if Variable.Kind = External then
                  This.Set (Variable.Name, Variable.External_Value,
                           Origin & " (gpr ext)");
               end if;
            end;
         end if;
      end loop;

      --  Set the crate PREFIX location for access to resources
      This.Set (AAA.Strings.To_Upper_Case (+Rel.Name) & "_ALIRE_PREFIX",
                Release_Base,
                "Crate prefix for resources location");
   end Load;

   -----------------
   -- Print_Shell --
   -----------------

   procedure Print_Shell (This : Context; Kind : Platforms.Shells) is
   begin
      --  TODO: PowerShell or CMD version for Windows. Is it possible to detect
      --  the kind of shell we are running in?
      for Elt of This.Compile loop
         case Kind is
         when Platforms.Unix =>
            Trace.Always (To_String ("export " & Elt.Key & "=""" &
                            Elt.Value & """"));
         when Platforms.PowerShell =>
            Trace.Always (To_String ("$env:" & Elt.Key & " = """ &
                            Elt.Value & """"));
         when Platforms.WinCmd =>
            Trace.Always (To_String ("set " & Elt.Key & "=" & Elt.Value));
         end case;
      end loop;
   end Print_Shell;

   -------------------
   -- Print_Details --
   -------------------

   procedure Print_Details (This : Context) is
   begin
      for C in This.Actions.Iterate loop
         declare
            Key : constant String := To_String (Action_Maps.Key (C));
         begin
            Trace.Always (" - variable: '" & Key & "'");
            for Act of This.Actions (C) loop
               case Act.Kind is
               when Properties.Environment.Set =>
                  Trace.Always ("   - Set to '" & To_String (Act.Value) &
                                  "' by '" & To_String (Act.Origin)  & "'");

               when Properties.Environment.Append =>
                  Trace.Always ("   - Appended with '" &
                                  To_String (Act.Value) &
                                  "' by '" & To_String (Act.Origin)  & "'");

               when Properties.Environment.Prepend =>
                  Trace.Always ("   - Prepended with '" &
                                  To_String (Act.Value) &
                                  "' by '" & To_String (Act.Origin)  & "'");

               end case;
            end loop;
         end;
      end loop;
   end Print_Details;

   -------------
   -- Compile --
   -------------

   function Compile (Key  : Unbounded_String;
                     Vect : Action_Vectors.Vector)
                     return Var
   is
      Separator : constant Character := GNAT.OS_Lib.Path_Separator;

      Value : Unbounded_String := +OS_Lib.Getenv (+Key);
      --  Pre-existing value, and new value when no conflict
   begin

      for Act of Vect loop

         --  Print some helpful details to inspect a conflict
         case Act.Kind is
            when Properties.Environment.Set =>
               Trace.Detail
                 (+("Env: " & Act.Origin &
                    " sets '" & Act.Value & "' to '" & Key & "'"));

            when Properties.Environment.Append =>

               Trace.Detail
                 (+("Env: " & Act.Origin &
                    " appends '" & Act.Value & "' to '" & Key & "'"));

            when Properties.Environment.Prepend =>
               Trace.Detail
                 (+("Env: " & Act.Origin &
                    " prepends '" & Act.Value & "' to '" & Key & "'"));
         end case;

         if Length (Value) = 0 then
            Value := Act.Value;
         else
            case Act.Kind is

            when Properties.Environment.Set =>
               if Value = Act.Value then
                  Trace.Debug ("Skipping identical key value: "
                               & (+Key) & "=" & (+Value));
                  --  We can silently ignore the attempt to set to the same
                  --  value. This is not ideal, but is more flexible for the
                  --  cases where we may end exporting the same environment
                  --  twice. Long-term, something like Boost.Process would be
                  --  more robust to call subprocesses without pilfering our
                  --  own environment.
               else
                  Raise_Checked_Error
                    (Errors.Wrap
                       ("Trying to set an already defined environment "
                        & "variable",
                        (+Key) & " is already defined as '" & (+Value)
                        & "' but new value is '" & (+Act.Value) & "'"));
               end if;

            when Properties.Environment.Append =>
               if Already_Defines (+Value, +Act.Value) then
                  Trace.Debug ("Skipping identical key value: "
                               & (+Key) & "=" & (+Value));
               else
                  Value := Value & Separator & Act.Value;
               end if;

            when Properties.Environment.Prepend =>
               if Already_Defines (+Value, +Act.Value) then
                  Trace.Debug ("Skipping identical key value: "
                               & (+Key) & "=" & (+Value));
               else
                  Value := Act.Value & Separator & Value;
               end if;
            end case;
         end if;
      end loop;

      return (Key => Key, Value => Value);
   end Compile;

   -------------
   -- Compile --
   -------------

   function Compile (This : Context) return Var_Array is
      Result : Var_Array (1 .. Natural (This.Actions.Length));
      Index  : Natural := Result'First;
   begin
      for C in This.Actions.Iterate loop
         Result (Index) := Compile (Action_Maps.Key (C), This.Actions (C));
         Index := Index + 1;
      end loop;

      --  Sort results for predictable output
      Sort (Result);

      return Result;
   end Compile;

   ------------
   -- Export --
   ------------

   procedure Export (This : Context) is
   begin
      for Var of This.Compile loop
         OS_Lib.Setenv (+Var.Key, +Var.Value);
      end loop;
   end Export;

end Alire.Environment;
