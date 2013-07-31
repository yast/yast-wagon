# encoding: utf-8

# File:
#	clients/wagon.ycp
#
# Module:
#	Wagon
#
# Authors:
#	Lukas Ocilka <locilka@suse.cz>
#	Alois Nebel <e-mail address is unknown>
#
# Summary:
#	Online Migration Tool
#
# $Id$
#
module Yast
  class WagonClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"
      Yast.import "ProductControl"
      Yast.import "Mode"
      Yast.import "Stage"
      Yast.import "Wizard"
      Yast.import "Directory"
      Yast.import "FileUtils"
      Yast.import "Wagon"
      Yast.import "CommandLine"
      Yast.import "PackageLock"
      Yast.import "PackageCallbacks"
      Yast.import "Report"

      Yast.include self, "wagon/common_func.rb"

      textdomain "wagon"

      # --> CommandLine support

      @wfm_args = WFM.Args
      Builtins.y2milestone("ARGS: %1", @wfm_args)

      @commands = CommandLine.Parse(@wfm_args)
      Builtins.y2milestone("Commands: %1", @commands)

      if Ops.get_string(@commands, "command", "") == "help" ||
          Ops.get_string(@commands, "command", "") == "longhelp" ||
          Ops.get_string(@commands, "command", "") == "xmlhelp"
        Wagon.ProcessCommandLine(@commands)
        return :auto
      end

      # <-- CommandLine support

      @do_restart = Ops.add(Directory.vardir, "/restart_yast")

      # Start workflow from step ...
      @current_step_file = Ops.add(
        Directory.vardir,
        "/wagon-current_workflow_step"
      )
      # Start with workflow
      @current_workflow_file = Ops.add(
        Directory.vardir,
        "/wagon-current_workflow_file"
      )

      @current_step = 0

      @custom_workflow_file = "/usr/share/YaST2/control/online_migration.xml"

      # Hooks for testing and manual changes
      # --> /usr/lib/YaST2/bin/wagon_hook_init
      Wagon.RunHook("init")

      Wagon.RunHooks("before_init")

      # main()
      HandleInit()

      Wizard.OpenNextBackStepsDialog
      Wizard.SetTitleIcon("yast-update")

      @ret = :auto

      # Exit WAGON if we can't initialize correctly
      if Init() != true
        @ret = :abort
      else
        @ret = ProductControl.RunFrom(@current_step, false)
      end

      # Wagon has been aborted, revert to the previous products
      # if possible
      if @ret == :abort || @ret == :cancel
        Wagon.RunHooks("before_abort")
        RevertToOldProducts()
      end

      Wizard.CloseDialog

      HandleRet(@ret)

      # Hooks for testing and manual changes
      # --> /usr/lib/YaST2/bin/wagon_hook_finish
      Wagon.RunHook("finish")

      Wagon.RunHooks("before_exit")

      @ret
    end

    def Init
      ProductControl.custom_control_file = @custom_workflow_file
      ProductControl.Init

      Mode.SetMode("update")
      Stage.Set("normal")

      ProductControl.AddWizardSteps(
        [{ "stage" => Stage.stage, "mode" => Mode.mode }]
      )

      # Can't acquire packager lock
      # BNC #616982
      pkg_connected = PackageLock.Connect(false)
      if Ops.get_boolean(pkg_connected, "connected", false) != true
        Builtins.y2warning("PackageLock not obtained")
        return false
      end

      Wagon.Init(@commands)

      true
    end

    # In case of restarting YaST, adjust the environment
    # Prepare YaST for restart
    def HandleRet(ret)
      if ret == :restart_same_step || ret == :restart_yast || ret == :reboot
        Builtins.y2milestone("YaST will be restarted, returned: %1", ret)
        SCR.Write(path(".target.ycp"), @do_restart, "restart_yast")

        if ret == :restart_same_step
          @current_step = ProductControl.CurrentStep
          # We actually don't want to restart the same step, we want to continue
          # directly with the very next step
          #
          # The current step + 1 == the very next step
          next_step = Ops.add(@current_step, 1)
          Builtins.y2milestone(
            "YaST will be restarted starting from the very next step: %1",
            next_step
          )
          SCR.Write(path(".target.ycp"), @current_step_file, next_step)

          # Also the current workflow type has to be stored
          current_workflow = Wagon.GetUpdateWorkflow
          Builtins.y2milestone("Current workflow is '%1'", current_workflow)
          SCR.Write(
            path(".target.ycp"),
            @current_workflow_file,
            current_workflow
          )

          # Store also current migration method
          current_method = Wagon.GetMigrationMethod
          Builtins.y2milestone(
            "Current migration method is '%1'",
            current_method
          )
          SCR.Write(
            path(".target.ycp"),
            Wagon.migration_method_file,
            current_method
          )
        end
      end

      if ret == :restart_same_step || ret == :restart_yast || ret == :reboot ||
          ret == :accept ||
          ret == :next
        Builtins.y2milestone("Storing all the current sources...")
        Pkg.SourceSaveAll
      end

      if ret == :restart_same_step || ret == :restart_yast || ret == :reboot
        Wagon.RunHooks("before_restart")
      end

      nil
    end

    # Checks whether YaST has been restarted
    # Adjust step to start with
    def HandleInit
      # logs what user does in UI
      UI.RecordMacro(Ops.add(Directory.logdir, "/macro_online_migration.ycp"))

      if FileUtils.Exists(@do_restart)
        Builtins.y2milestone("YaST has been restarted")
        SCR.Execute(path(".target.remove"), @do_restart)

        if FileUtils.Exists(@current_step_file)
          @current_step = Convert.to_integer(
            SCR.Read(path(".target.ycp"), @current_step_file)
          )
          SCR.Execute(path(".target.remove"), @current_step_file)

          if @current_step == nil || Ops.less_than(@current_step, 0)
            Builtins.y2error(
              "Current step is %1, running from the beginning",
              @current_step
            )
            @current_step = 0
          else
            Builtins.y2milestone("Adjusting starting step: %1", @current_step)
          end
        end

        if FileUtils.Exists(@current_workflow_file)
          workflow_type = Convert.to_string(
            SCR.Read(path(".target.ycp"), @current_workflow_file)
          )
          SCR.Execute(path(".target.remove"), @current_workflow_file)

          if workflow_type == nil || workflow_type == ""
            Builtins.y2error(
              "Requested workflow type is invalid: %1",
              workflow_type
            )
          else
            Builtins.y2milestone(
              "Adjusting required workflow type: %1",
              workflow_type
            )
            Wagon.SetUpdateWorkflow(workflow_type)
          end
        end

        if FileUtils.Exists(Wagon.migration_method_file)
          migration_method = Convert.to_string(
            SCR.Read(path(".target.ycp"), Wagon.migration_method_file)
          )
          SCR.Execute(path(".target.remove"), Wagon.migration_method_file)

          if migration_method == nil || migration_method == ""
            Builtins.y2error(
              "Migration method is invalid: %1",
              migration_method
            )
          else
            Builtins.y2milestone(
              "Adjusting to migration method: %1",
              migration_method
            )
            Wagon.SetMigrationMethod(migration_method)
          end
        end

        Wagon.RunHooks("after_restart")
      end

      nil
    end

    def RevertToOldProducts
      if Wagon.abort_can_revert_products != true
        Builtins.y2warning(
          "Cannot revert the previous state of products, sorry. Installed products were: %1, Migration products were: %2",
          Wagon.products_before_migration,
          Wagon.migration_products
        )

        Report.Warning(
          _(
            "Cannot revert to the previous state of installed products.\nYou will have to revert manually.\n"
          )
        )

        return false
      end


      Wizard.SetContents(
        _("Reverting Migration"),
        Label(
          _(
            "Migration tool has to remove the temporary migration products,\n" +
              "install the previously installed ones and contact Novell Customer Center\n" +
              "to get update repositories."
          )
        ),
        _(
          "<p>Several tasks can be done by the migration tool. If you skip this step,\nyou will have to do them manually.</p>"
        ),
        false,
        true
      )
      Wizard.EnableAbortButton

      cont = true
      while true
        ret = UI.UserInput
        if ret == :next
          cont = true
          break
        elsif ret == :abort || ret == :cancel
          if Popup.AnyQuestion(
              # popup dialog caption
              _("Migration Has to Be Reverted"),
              # popup dialog qustion
              _("Are you sure you want to skip reverting the migration?"),
              # button
              _("&Yes, Skip It"),
              # button
              _("&No"),
              :focus_no
            )
            cont = false
            break
          end
        end
      end

      if cont != true
        Builtins.y2warning("User decided not to rollback")
        return false
      end

      Wagon.RunHooks("before_abort_rollback")

      ResetPackager()

      Wizard.SetContents(
        _("Reverting Migration"),
        Label(_("Removing temporary migration products...")),
        "",
        false,
        true
      )

      Builtins.y2milestone(
        "Repositories disabled by migration: %1",
        Wagon.disabled_repositories
      )
      Builtins.foreach(Wagon.disabled_repositories) do |repo_alias|
        repo_id = FindRepoIdByAlias(repo_alias)
        if repo_id == nil
          Builtins.y2error(
            "Cannot enable repo (alias)%1, repo not found ",
            repo_alias
          )
          Report.Error(
            Builtins.sformat(
              _(
                "Cannot enable repository with alias\n" +
                  "%1\n" +
                  "Repository was not found."
              ),
              repo_alias
            )
          )
          next
        end
        Builtins.y2milestone(
          "Enabling repository %1 returned: %2",
          repo_id,
          Pkg.SourceSetEnabled(repo_id, true)
        )
      end

      Pkg.SourceSaveAll
      Wagon.InitPkg

      # Packages removed by this run
      removed_packages = []

      # Remove all the migration products using packages approach manually
      # Removing via ResolvableRemove + PkgSolve usually produces errors,
      # dependency loops etc.
      #
      Builtins.y2milestone(
        "Removing newly installed products: %1",
        Wagon.migration_products
      )
      Builtins.foreach(Wagon.migration_products) do |migration_product|
        Builtins.foreach(
          Pkg.ResolvableProperties(migration_product, :product, "")
        ) do |remove_product|
          remove_product = Wagon.MinimizeProductMap(remove_product)
          package_name = GetProductPackageName(remove_product)
          next if package_name == ""
          # Package has been already removed
          next if Builtins.contains(removed_packages, package_name)
          if Pkg.TargetRemove(package_name) != true
            Builtins.y2error("Cannot remove package %1", package_name)
            Report.Error(
              Builtins.sformat(
                _("Cannot remove product %1.\nRemove package %2 manually.\n"),
                Ops.get_locale(remove_product, "name", _("Unknown product")),
                package_name
              )
            )
            next
          end
          Builtins.y2milestone(
            "Product %1/%2 has been successfully removed",
            remove_product,
            package_name
          )
          # Do not try to remove it again
          removed_packages = Builtins.add(removed_packages, package_name)
        end
      end

      if Ops.greater_than(Builtins.size(removed_packages), 0)
        Builtins.y2milestone(
          "%1 products were removed, resetting packager",
          Builtins.size(removed_packages)
        )
        ResetPackager()

        Builtins.foreach(removed_packages) do |one_package|
          Builtins.y2milestone(
            "Removed product package check: %1",
            Pkg.ResolvableProperties(one_package, :package, "")
          )
        end
      end

      Builtins.y2milestone("Running registration")
      if WFM.call("inst_suse_register") == :abort
        Builtins.y2error("Unable to register")
        return false
      end

      Wagon.RunHooks("after_abort_rollback")

      true
    end
  end
end

Yast::WagonClient.new.main
