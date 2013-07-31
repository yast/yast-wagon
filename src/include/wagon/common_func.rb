# encoding: utf-8

# File:
#	include/wagon/common_func.ycp
#
# Module:
#	Wagon
#
# Authors:
#	Lukas Ocilka <locilka@suse.cz>
#
# Summary:
#	Online Migration Tool
#
# $Id$
#
module Yast
  module WagonCommonFuncInclude
    def initialize_wagon_common_func(include_target)
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "wagon"

      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "PackagesUI"
      Yast.import "Wagon"
      Yast.import "Wizard"
      Yast.import "GetInstArgs"
      Yast.import "Report"
      Yast.import "Directory"
      Yast.import "FileUtils"

      @solver_testcase_dir = Builtins.sformat(
        "%1/wagon_solver_testcase",
        Directory.logdir
      )

      # Full paths to product files
      @checked_product_files = {}
    end

    def SolverRunWithFeedback
      UI.OpenDialog(Label(_("Solving the package dependencies...")))

      ret = Pkg.PkgSolve(true)

      # BNC #582046: Store a solver testcase in case of solver issue
      if ret != true
        Builtins.y2warning(
          "Solver failed, storing solver testcase to %1",
          @solver_testcase_dir
        )

        if FileUtils.Exists(@solver_testcase_dir)
          Builtins.y2warning(
            "Directory %1 exists, removing first",
            @solver_testcase_dir
          )
          SCR.Execute(
            path(".target.bash"),
            Builtins.sformat("rm -rf %1", @solver_testcase_dir)
          )
        end

        Pkg.CreateSolverTestCase(@solver_testcase_dir)
        Builtins.y2milestone("Done")
      end

      UI.CloseDialog

      ret
    end

    def SolveDependencies
      ret = :auto

      solved = nil

      while solved != true
        # Trying to solve automatically
        solved = SolverRunWithFeedback()
        ret_sel = nil

        # PkgSolve didn't report any problem
        if solved == true
          Builtins.y2milestone("Solved automatically")
          ret = :auto 
          # There are some issues in selecting the patches
        else
          Builtins.y2milestone("Cannot be solved automatically")
          while true
            # Try to solve them manually
            ret_sel = PackagesUI.RunPackageSelector({ "mode" => :summaryMode })

            # Cannot or don't want to accept the proposal
            if ret_sel == :cancel
              # Confirmed
              if Popup.AnyQuestion(
                  # TRANSLATORS: headline
                  _("Aborting the Upgrade"),
                  # TRANSLATORS: pop-up question
                  _(
                    "Cannot continue without installing the required patches.\nAre you sure you want to abort the upgrade process?\n"
                  ),
                  _("Abort Upgrade"),
                  Label.NoButton,
                  :yes_button
                )
                ret = :abort
                break 
                # Try again
              else
                next
              end 
              # Solved manually
            elsif ret_sel == :accept
              ret = :auto
              solved = true
              break
            end
          end
        end

        if ret == :abort
          solved = nil
          Builtins.y2warning("Aborting...")
          break
        end

        if !Wagon.AcceptLicenses
          Builtins.y2warning(
            "Some license(s) have been rejected, running solver again"
          )
          solved = nil
        end
      end

      ret
    end

    def ResetPackager
      Wizard.SetContents(
        _("Resetting Software Manager"),
        Label(_("Resetting software manager...")),
        "",
        false,
        true
      )

      Builtins.y2milestone("Resetting Pkg")

      repos = Pkg.GetUpgradeRepos
      if Ops.greater_than(Builtins.size(repos), 0)
        Builtins.y2milestone("Resetting upgrade repos config")
        Builtins.foreach(repos) { |repo| Pkg.RemoveUpgradeRepo(repo) }
      end

      # reset solver flags
      Pkg.SetSolverFlags({ "reset" => true })

      Pkg.TargetFinish
      Pkg.SourceFinishAll

      Wagon.InitPkg

      Builtins.y2milestone("Running solver")
      Pkg.PkgSolve(true)

      nil
    end

    def FindRepoIdByAlias(repo_alias)
      repo_id = nil

      one_repo = {}

      Builtins.foreach(
        Pkg.SourceGetCurrent(
          false # all repos
        )
      ) do |repo_id_to_check|
        one_repo = Pkg.SourceGeneralData(repo_id_to_check)
        if Ops.get_string(one_repo, "alias", "") == repo_alias
          repo_id = repo_id_to_check
          raise Break
        end
      end

      repo_id
    end

    # During the first (migration) registration, it's not needed to include
    # the optional data as it is also faster but after the migration, it's
    # better to to include them.
    # @see #BNC 576553
    def AdjustSuseRegisterDefaults
      argmap = GetInstArgs.argmap

      if Ops.get_string(argmap, "suse_register_defaults", "") == "none"
        Builtins.y2milestone(
          "suse_register: no optional data selected by default (%1/%2/%3)",
          SCR.Write(path(".sysconfig.suse_register.SUBMIT_OPTIONAL"), "false"),
          SCR.Write(path(".sysconfig.suse_register.SUBMIT_HWDATA"), "false"),
          SCR.Write(path(".sysconfig.suse_register"), nil)
        )
      elsif Ops.get_string(argmap, "suse_register_defaults", "") == "selected"
        Builtins.y2milestone(
          "suse_register: all optional data selected by default (%1/%2/%3)",
          SCR.Write(path(".sysconfig.suse_register.SUBMIT_OPTIONAL"), "true"),
          SCR.Write(path(".sysconfig.suse_register.SUBMIT_HWDATA"), "true"),
          SCR.Write(path(".sysconfig.suse_register"), nil)
        )
      else
        Builtins.y2warning(
          "Undefined how to handled suse_register optional data"
        )
      end

      nil
    end

    # Finds a package that provides the required product
    # defined by parameter.
    #
    # @return [String] product_package
    def GetProductPackageName(product)
      product = deep_copy(product)
      product = Wagon.MinimizeProductMap(product)
      product_file = Ops.get_string(product, "product_file", "")

      # undefined product file
      if product_file == nil || product_file == ""
        Builtins.y2error(
          "Cannot remove product: %1, no product file defined",
          product
        )
        Report.Error(
          Builtins.sformat(
            _("Cannot remove product %1."),
            Ops.get_locale(product, "name", _("Unknown product"))
          )
        )
        return ""
      end

      # unify the product file path
      if !Builtins.regexpmatch(product_file, "^/etc/products\\.d/.+")
        product_file = Builtins.sformat("/etc/products.d/%1", product_file)
      end

      # use a cached value
      if Builtins.haskey(@checked_product_files, product_file)
        if Ops.get(@checked_product_files, product_file, "") == ""
          return ""
        else
          return Ops.get(@checked_product_files, product_file, "")
        end
      end

      package_name = Wagon.GetFileOwner(product_file)

      # no package owns the file
      if package_name == nil || package_name == ""
        Builtins.y2error("Cannot find out file owner %1", product_file)
        Report.Error(
          Builtins.sformat(
            _("Cannot find out owner of product %1."),
            Ops.get_locale(product, "name", _("Unknown product"))
          )
        )
        return ""
      end

      # cache the value
      Ops.set(@checked_product_files, product_file, package_name)

      package_name
    end
  end
end
