# encoding: utf-8

# File:	modules/Wagon.ycp
# Package:	WAGON
# Summary:	Functions and handlers for WAGON
# Authors:	Lukas Ocilka <locilka@suse.cz>
# Internal
#
# $Id$
#
# Module for handling WAGON.
#
require "yast"

module Yast
  class WagonClass < Module
    def main
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "wagon"

      Yast.import "Installation"
      Yast.import "PackageCallbacks"
      Yast.import "CommandLine"
      Yast.import "Mode"
      Yast.import "Stage"
      Yast.import "Directory"
      Yast.import "XML"
      Yast.import "ProductControl"
      Yast.import "Popup"
      Yast.import "Label"
      Yast.import "Report"
      Yast.import "ProductFeatures"
      Yast.import "Update"
      Yast.import "FileUtils"
      Yast.import "String"
      Yast.import "Packages"
      Yast.import "PackageInstallation"
      Yast.import "RegistrationStatus"

      Yast.include self, "wagon/wagon_helpers.rb"

      @running_by_applet = false

      @update_workflow_type = "manual"

      # Products installed for the time of the migration
      @migration_products = []

      # Products installed before the migration
      @products_before_migration = []

      # Repositories that were disabled by wagon during migration
      # List of aliases (unique identification)
      # BNC #573092
      @disabled_repositories = []
      @repositories_to_disable = []

      # When aborting before the real migration starts, we can still
      # revert to the old products
      @abort_can_revert_products = true

      # Registration can be skipped, this variable tells whether some repos were already
      # added by registration
      @repos_already_registered = false

      # Script suse_register changes the repositories automatically.
      # Additionally, Wagon also disables some repositories. This option provides
      # the possibility to check what was changed and how and/or add/remove some more.
      # BNC #579905
      @check_repositories_manually = false

      @check_repos_module = "wagon_check_repositories"

      @hook_dir = "/var/lib/YaST2/wagon/hooks/"

      @download_mode_link = "wagon-download_in_advance"

      @migration_method = nil

      @migration_method_file = Builtins.sformat(
        "%1/wagon_migration_method",
        Directory.vardir
      )

      # do the distribution upgrade from selected repositories
      @dup_repos = []

      @manual_repo_selection = false

      # list of repositories (aliases) added by suse_register
      @new_registration_repos = []

      # migration type, one of `minimal, `full, `custom
      @migration_type = :minimal

      @already_proposed = false

      # YaST can be restarted but some data have to be kept
      @migration_products_store_file = Builtins.sformat(
        "%1/wagon_products_before_migration",
        Directory.vardir
      )
    end

    def SetUpdateWorkflow(new_update_workflow_type)
      # FIXME: check

      Builtins.y2milestone("New workflow type: %1", new_update_workflow_type)
      @update_workflow_type = new_update_workflow_type

      nil
    end

    def GetUpdateWorkflow
      @update_workflow_type
    end

    def GetDownloadModeLink
      @download_mode_link
    end

    def SetMigrationMethod(m_method)
      Builtins.y2milestone("Setting migration method: %1", m_method)

      if m_method == "suse_register" || m_method == "custom"
        @migration_method = m_method
      else
        Builtins.y2error("Unknown migration method: %1", m_method)
        Report.Error(
          Builtins.sformat(
            _(
              "Error switching migration method.\nUnknown migration method: %1.\n"
            ),
            m_method
          )
        )
        return false
      end

      true
    end

    def GetMigrationMethod
      @migration_method
    end

    def DupRepos
      deep_copy(@dup_repos)
    end

    def SetDupRepos(repos)
      repos = deep_copy(repos)
      @dup_repos = deep_copy(repos)

      nil
    end

    # manual or automatic DUP repo selection?
    def ManualRepoSelection
      @manual_repo_selection
    end

    def SetManualRepoSelection(manual)
      Builtins.y2milestone("Manual DUP repo selection: %1", manual)
      @manual_repo_selection = manual

      nil
    end

    # returns list of repositories (aliases) added by suse_register
    def RegistrationRepos
      deep_copy(@new_registration_repos)
    end

    # set list of repositories (aliases) added by suse_register
    def SetRegistrationRepos(repos)
      repos = deep_copy(repos)
      Builtins.y2milestone(
        "Repositories added by registration: %1",
        @new_registration_repos
      )
      @new_registration_repos = deep_copy(repos)

      nil
    end

    # get the current migration type
    def MigrationType
      @migration_type
    end

    # set the migration type
    # @param type Type of migration (`minimal, `full, `custom)
    # @return boolean true on success
    def SetMigrationType(type)
      if Builtins.contains([:minimal, :full, :custom], type)
        @migration_type = type
        Builtins.y2milestone("Setting migration type: %1", type)
        return true
      else
        Builtins.y2error("Invalid migration type: %1", type)
        Builtins.y2warning("Keeping the current type: %1", @migration_type)
        return false
      end
    end

    def ResetWorkflowSteps
      ProductControl.UnDisableAllModulesAndProposals(Mode.mode, Stage.stage)

      nil
    end

    # Replaces the current workflow steps with a new one.
    def SetWizardSteps
      # Adjusting the steps this way:
      #   * Disable all steps
      #   * Enable only the requierd ones

      ResetWorkflowSteps()

      ProductControl.DisableAllModulesAndProposals(Mode.mode, Stage.stage)

      subworkflows = Convert.convert(
        ProductFeatures.GetFeature("globals", "subworkflows"),
        :from => "any",
        :to   => "list <map <string, any>>"
      )

      found = false

      Builtins.foreach(subworkflows) do |one_subworkflow|
        if Ops.get_string(one_subworkflow, "name", "") == @update_workflow_type
          modules = Ops.get_list(one_subworkflow, "modules", [])
          Builtins.y2milestone("Modules to enable: %1", modules)

          Builtins.foreach(modules) do |one_module|
            ProductControl.EnableModule(one_module)
          end if modules != nil &&
            modules != []

          proposals = Ops.get_list(one_subworkflow, "proposals", [])
          Builtins.y2milestone("Proposals to enable: %1", proposals)

          Builtins.foreach(proposals) do |one_proposal|
            ProductControl.EnableProposal(one_proposal)
          end if proposals != nil &&
            proposals != []

          found = true
          raise Break
        end
      end

      if found != true
        Builtins.y2error("Unknown workflow: %1", @update_workflow_type)
        Builtins.y2milestone("Known workflows: %1", subworkflows)
        # TRANSLATORS: error message
        Report.Error(_("No workflow defined."))
        return false
      end

      true
    end

    # Handles the optional workflow steps according to the current settigns.
    def AdjustVariableSteps
      Builtins.y2milestone(
        "Adjusting variable steps to '%1' migration method",
        @migration_method
      )

      # BNC #587506: enable/disable steps according to selected method
      #
      # User will not have to enter migration repositories manually
      # registration takes care about it
      if @migration_method == "suse_register"
        ProductControl.DisableModule("wagon_manual_url_repositories")
        ProductControl.EnableModule("suse_register_workflow")

        # BNC #579905: Check modified repositories manually.
        if @check_repositories_manually != false
          Builtins.y2milestone("Enabling module %1", @check_repos_module)
          ProductControl.EnableModule(@check_repos_module)
        else
          Builtins.y2milestone("Disabling module %1", @check_repos_module)
          ProductControl.DisableModule(@check_repos_module)
        end 
        # User has chosen to enter all migration repositories manually
      elsif @migration_method == "custom"
        ProductControl.DisableModule("wagon_check_repositories")
        ProductControl.DisableModule("suse_register_workflow")
        ProductControl.EnableModule("wagon_manual_url_repositories")
      end

      nil
    end

    # Redraws the wizard steps according to current workflow settings.
    def RedrawWizardSteps
      stage_mode = [{ "stage" => Stage.stage, "mode" => Mode.mode }]

      Builtins.y2milestone(
        "Updating wizard steps: %1, Disabled modules: %2, Disabled proposals: %3",
        stage_mode,
        ProductControl.GetDisabledModules,
        ProductControl.GetDisabledProposals
      )
      ProductControl.UpdateWizardSteps(stage_mode)

      nil
    end

    # Sets wizard steps and redraws the UI.
    def AdjustWizardSteps
      return false if SetWizardSteps() != true

      RedrawWizardSteps()

      true
    end

    # Initializes internal variables used later
    #
    # @param [Hash{String => Object}] commands as got from CommandLine::Parse()
    # @see CommandLine module
    def Init(commands)
      commands = deep_copy(commands)
      if Builtins.haskey(commands, "command")
        if Ops.get_string(commands, "command", "") == "cd_update"
          # Backward compatibility
          Ops.set(commands, "command", "PatchCD")
        end

        Builtins.y2milestone(
          "Starting workflow defined: %1",
          Ops.get_string(commands, "command", "")
        )
        SetUpdateWorkflow(Ops.get_string(commands, "command", ""))
      else
        default_subworkflow = ProductFeatures.GetStringFeature(
          "globals",
          "default_subworkflow"
        )

        if default_subworkflow == nil || default_subworkflow == ""
          default_subworkflow = "manual"
        end
        Builtins.y2milestone("Using default workflow: %1", default_subworkflow)
      end

      AdjustWizardSteps()

      nil
    end

    # Initializes the package manager
    def InitPkg
      if Pkg.TargetInitialize(Installation.destdir) != true
        Builtins.y2error("Cannot initialize target")
        return false
      end

      if Pkg.TargetLoad != true
        Builtins.y2error("Cannot load target")
        return false
      end

      if Pkg.SourceStartManager(true) != true
        Builtins.y2error("Cannot initialize sources")
        return false
      end

      # FIXME: what's missing here?

      true
    end

    # Processes the command-line parameters and prints
    # an appropriate command-line output.
    #
    # @param [Hash{String => Object}] commands as got from CommandLine::Parse()
    # @see CommandLine module
    def ProcessCommandLine(commands)
      commands = deep_copy(commands)
      Mode.SetUI("commandline")

      if Ops.get_string(commands, "command", "") == "help" ||
          Ops.get_string(commands, "command", "") == "longhelp"
        CommandLine.Print(
          _(
            "\n" +
              "This module does not support command-line interface.\n" +
              "Use zypper instead.\n"
          )
        )
      elsif Ops.get_string(commands, "command", "") == "xmlhelp"
        if !Builtins.haskey(Ops.get_map(commands, "options", {}), "xmlfile")
          CommandLine.Print(
            _(
              "Target file name ('xmlfile' option) is missing. Use xmlfile=<target_XML_file> command line option."
            )
          )
        else
          doc = {}

          Ops.set(
            doc,
            "listEntries",
            {
              "commands" => "command",
              "options"  => "option",
              "examples" => "example"
            }
          )

          Ops.set(
            doc,
            "systemID",
            Ops.add(Directory.schemadir, "/commandline.dtd")
          )
          Ops.set(doc, "typeNamespace", "http://www.suse.com/1.0/configns")
          Ops.set(doc, "rootElement", "commandline")
          XML.xmlCreateDoc(:xmlhelp, doc)

          exportmap = { "module" => "wagon" }

          XML.YCPToXMLFile(
            :xmlhelp,
            exportmap,
            Ops.get_string(commands, ["options", "xmlfile"], "")
          )
          Builtins.y2milestone("exported XML map: %1", exportmap)
        end
      end

      nil
    end

    # Goes through all selected packages one by one a check licenses to confirm.
    # These licenses are requested to be accepted by user. If user declines any
    # of them, a respective package is set to 'Taboo' and new solver run is
    # required.
    #
    # @return [Boolean] whether all licenses have been accepted
    def AcceptLicenses
      accepted = true

      Builtins.foreach(Pkg.GetPackages(:selected, true)) do |p|
        license = Pkg.PkgGetLicenseToConfirm(p)
        if license != nil && license != ""
          if license != nil && license != ""
            rt_license = Builtins.sformat("<p><b>%1</b></p>\n%2", p, license)

            if !Popup.AnyQuestionRichText(
                # popup heading, with rich text widget and Yes/No buttons
                _("Do you accept this license agreement?"),
                rt_license,
                70,
                20,
                Label.YesButton,
                Label.NoButton,
                :focus_none
              )
              Builtins.y2milestone("License not accepted: %1", p)
              Pkg.PkgTaboo(p)
              accepted = false
            else
              Pkg.PkgMarkLicenseConfirmed(p)
            end
          end
        end
      end

      accepted
    end

    def GetUpdateConf
      ret = {}

      sdp = Update.SilentlyDowngradePackages
      Ops.set(ret, "silent_downgrades", sdp) if sdp != nil

      Builtins.y2milestone("Using update configuration: %1", ret)

      deep_copy(ret)
    end

    def ResetDUPProposal
      @already_proposed = false

      nil
    end

    def ProposeDUP
      if @already_proposed == true
        Builtins.y2milestone("DUP already proposed")
        return true
      end

      # reset upgrade repo config
      Builtins.y2milestone("Resetting upgrade repos config")
      repos = Pkg.GetUpgradeRepos
      Builtins.foreach(repos) { |repo| Pkg.RemoveUpgradeRepo(repo) }

      # reset solver flags
      Pkg.SetSolverFlags({ "reset" => true })

      # add upgrade repositories
      Builtins.y2milestone("Adding upgrade repos: %1", @dup_repos)
      Builtins.foreach(@dup_repos) { |repo| Pkg.AddUpgradeRepo(repo) }

      # be compatible with "zypper dup --from"
      Pkg.SetSolverFlags({ "ignoreAlreadyRecommended" => true })

      # ensure the migration products are removed
      Builtins.foreach(@migration_products) do |migration_product|
        Builtins.y2milestone(
          "Removing migration product: %1",
          migration_product
        )
        Pkg.ResolvableRemove(migration_product, :product)
      end 


      if MigrationType() == :full
        # run the solver to evaluate applicable patches
        Pkg.PkgSolve(false)

        # preselect all applicable patches (except optional ones)
        patches = Pkg.ResolvablePreselectPatches(:all)
        Builtins.y2milestone("Preselected patches: %1", patches)
      end

      # set the solve error flag for packages proposal
      Update.solve_errors = Pkg.PkgSolve(true) ? 0 : Pkg.PkgSolveErrors

      if !AcceptLicenses()
        # rerun the solver after rejecting a package license
        # (setting the package to taboo state)
        Update.solve_errors = Pkg.PkgSolve(true) ? 0 : Pkg.PkgSolveErrors
      end

      Pkg.CreateSolverTestCase("/var/log/YaST2/wagon_test_case")

      @already_proposed = true

      true
    end

    def CheckDownloadSpace
      # display a warning if estimated free size after migration is below 100MB
      min_free_space = 100 << 20

      du = Pkg.TargetGetDU
      mounts = Builtins.maplist(du) { |dir, info| dir }

      zconfig = Pkg.ZConfig
      pkg_path = Ops.get_string(zconfig, "repo_packages_path", "")

      packages_mount = FindMountPoint(pkg_path, mounts)
      Builtins.y2milestone(
        "Packages will we downloaded to %1 (mountpoint %2)",
        pkg_path,
        packages_mount
      )

      # download size in bytes
      download_size = Packages.CountSizeToBeDownloaded
      Builtins.y2milestone(
        "Size of packages to download: %1MB",
        Ops.shift_right(download_size, 20)
      )

      # du contains maps: $[ "dir" : [ total, used, pkgusage, readonly ], .... ]
      after_install = Ops.get_integer(du, [packages_mount, 2], 0)
      total = Ops.get_integer(du, [packages_mount, 0], 0)
      Builtins.y2milestone(
        "Size after installation: %1MB (of %2MB)",
        Ops.shift_right(after_install, 20),
        Ops.shift_right(total, 20)
      )

      result = :ok
      message = ""

      if Ops.less_than(Ops.add(after_install, download_size), total)
        result = :error
        message = Builtins.sformat(
          _(
            "There is not enough free space to migrate the system using download in advance mode. Partition %1 needs at least %2MB more free disk space. (The needed size is estimated, it is recommended to add slightly more free space.) Add more disk space or disable download in advance mode."
          ),
          packages_mount,
          Ops.shift_right(
            Ops.subtract(Ops.add(after_install, download_size), total),
            20
          )
        )
        Builtins.y2error(
          "Not enough free space for download in advance upgrade: " +
            "estimated size after installation: %1MB, download size: %2MB, " +
            "total size: %3MB, estimated free space: %4MB",
          Ops.shift_right(after_install, 20),
          Ops.shift_right(download_size, 20),
          Ops.shift_right(total, 20),
          Ops.shift_right(
            Ops.subtract(Ops.subtract(total, after_install), download_size),
            20
          )
        )
      elsif Ops.less_than(
          Ops.add(Ops.add(after_install, download_size), min_free_space),
          total
        )
        result = :warning
        message = Builtins.sformat(
          _(
            "There might not be enough free space for download in advance mode migration. The estimated free space after migration is %2MB, it is recommended to increase the free space in case the estimation is inaccurate to avoid installation errors."
          ),
          Ops.shift_right(
            Ops.subtract(Ops.subtract(total, after_install), download_size),
            20
          )
        )
        Builtins.y2warning(
          "Low free space: estimated size after installation: %1MB, " +
            "download size: %2MB, total size: %3MB, estimated free space: %4MB",
          Ops.shift_right(after_install, 20),
          Ops.shift_right(download_size, 20),
          Ops.shift_right(total, 20),
          Ops.shift_right(
            Ops.subtract(Ops.subtract(total, after_install), download_size),
            20
          )
        )
      end

      { "result" => result, "message" => message }
    end

    def ProposeDownloadMode
      if PackageInstallation.DownloadInAdvance == nil
        dwspace = CheckDownloadSpace()

        PackageInstallation.SetDownloadInAdvance(
          Ops.get(dwspace, "result") == :ok
        )
        Builtins.y2milestone(
          "Proposed download in advance mode: %1",
          PackageInstallation.DownloadInAdvance
        )
      end

      nil
    end

    def MinimizeProductMap(product)
      product = deep_copy(product)
      Ops.set(product, "license", "...") if Builtins.haskey(product, "license")
      if Builtins.haskey(product, "description")
        Ops.set(product, "description", "...")
      end

      deep_copy(product)
    end

    def GetDisplayName(display_name, name)
      return display_name if display_name == name

      # 'Product Long Name (product-libzypp-name)'
      Builtins.sformat(_("%1 (%2)"), display_name, name)
    end

    def ProposalSummary
      ret = ""
      warning = ""

      products = Builtins.sort(Pkg.ResolvableProperties("", :product, "")) do |x, y|
        Ops.less_than(
          Ops.get_string(
            x,
            "display_name",
            Ops.get_string(x, "short_name", Ops.get_string(x, "name", "a"))
          ),
          Ops.get_string(
            y,
            "display_name",
            Ops.get_string(x, "short_name", Ops.get_string(x, "name", "b"))
          )
        )
      end

      # migration_products contains list of temporary products for migration process

      Builtins.y2milestone(
        "All known migration products: %1",
        @migration_products
      )

      display_name = nil
      name = nil
      transact_by = nil

      # list of all products that will be installed (are selected)
      products_to_be_installed = []
      Builtins.foreach(products) do |product|
        next if Ops.get_symbol(product, "status", :unknown) != :selected
        name = Ops.get_locale(product, "name", _("No short name defined."))
        products_to_be_installed = Builtins.add(products_to_be_installed, name)
      end

      # list of all products that will be upgraded
      products_to_be_upgraded = []

      products_removed_by_solver = 0

      # Products that are going to be removed
      Builtins.foreach(products) do |product|
        next if Ops.get_symbol(product, "status", :unknown) != :removed
        product = MinimizeProductMap(product)
        display_name = Ops.get_locale(
          product,
          "display_name",
          Ops.get_locale(
            product,
            "short_name",
            Ops.get_locale(product, "name", _("No name defined."))
          )
        )
        name = Ops.get_locale(product, "name", _("No short name defined."))
        transact_by = Ops.get_symbol(product, "transact_by", :unknown)
        # Removing product and installing the same one (name) means -> upgrade
        if Builtins.contains(products_to_be_installed, name) ||
            # Hack: SLES-for-VMware migration changes the product from "SUSE_SLES" to "SLES-for-VMware", check this upgrade
            name == "SUSE_SLES" &&
              Builtins.contains(products_to_be_installed, "SLES-for-VMware") ||
            # Hack: WebYaST migration changes the product from "sle-11-SP2-WebYaST" to "sle-11-WebYaST", check this upgrade
            name == "sle-11-SP2-WebYaST" &&
              Builtins.contains(products_to_be_installed, "sle-11-WebYaST")
          products_to_be_upgraded = Builtins.add(products_to_be_upgraded, name)
          Builtins.y2milestone(
            "Product to be upgraded: %1 (this is the removed one)",
            product
          )
          # Do not list this product as 'to removed', list it as 'to upgrade'
          next
        end
        # Removing a migration product is fine
        if Builtins.contains(
            @migration_products,
            Ops.get_string(product, "name", "")
          )
          Builtins.y2milestone("Migration product will be removed: %1", product)
          ret = Ops.add(
            Ops.add(
              Ops.add(ret, "<li>"),
              Builtins.sformat(
                _("Temporary migration product <b>%1</b> will be removed"),
                GetDisplayName(display_name, name)
              )
            ),
            "</li>\n"
          ) 
          # Removing another product might be an issue
          # (nevertheless selected by user or directly by YaST)
        elsif transact_by == :user || transact_by == :app_high
          Builtins.y2warning(
            "Product will be removed: %1 (%2)",
            product,
            transact_by
          )
          ret = Ops.add(
            Ops.add(
              Ops.add(ret, "<li>"),
              Builtins.sformat(
                _(
                  "<font color='red'><b>Warning:</b> Product <b>%1</b> will be removed.</font>"
                ),
                GetDisplayName(display_name, name)
              )
            ),
            "</li>\n"
          ) 
          # Not selected by user
          # @see BNC #575117
        else
          Builtins.y2warning(
            "Product will be removed: %1 (%2)",
            product,
            transact_by
          )
          ret = Ops.add(
            Ops.add(
              Ops.add(ret, "<li>"),
              Builtins.sformat(
                _(
                  "<font color='red'><b>Error:</b> Product <b>%1</b> will be automatically removed.</font>"
                ),
                GetDisplayName(display_name, name)
              )
            ),
            "</li>\n"
          )
          products_removed_by_solver = Ops.add(products_removed_by_solver, 1)
        end
      end

      # Products that are going to be installed (new ones) or upgraded
      Builtins.foreach(products) do |product|
        next if Ops.get_symbol(product, "status", :unknown) != :selected
        product = MinimizeProductMap(product)
        display_name = Ops.get_locale(
          product,
          "display_name",
          Ops.get_locale(
            product,
            "short_name",
            Ops.get_locale(product, "name", _("No name defined."))
          )
        )
        name = Ops.get_locale(product, "name", _("No short name defined."))
        # Hack: SLES-for-VMware migration changes the product from "SUSE_SLES" to "SLES-for-VMware", check this upgrade
        sles_for_vmware_upgrade = name == "SLES-for-VMware" &&
          Builtins.contains(products_to_be_upgraded, "SUSE_SLES") &&
          Builtins.contains(
            @migration_products,
            "SLES-for-VMware-SP2-migration"
          )
        # Product is going to be upgraded (removed + installed new version)
        if Builtins.contains(products_to_be_upgraded, name) || sles_for_vmware_upgrade
          old_product = Builtins.find(products) do |p|
            Ops.get_string(p, "name", "") ==
              (sles_for_vmware_upgrade ? "SUSE_SLES" : name) &&
              Ops.get_symbol(p, "status", :unknown) == :removed
          end
          old_product_name = Ops.get_locale(
            old_product,
            "name",
            _("No name defined.")
          )
          old_display_name = Ops.get_locale(
            old_product,
            "display_name",
            Ops.get_locale(
              old_product,
              "short_name",
              Ops.get_locale(old_product, "name", _("No name defined."))
            )
          )

          Builtins.y2milestone(
            "Detected product upgrade from: '%1' to: '%2'",
            old_display_name,
            display_name
          )
          Builtins.y2milestone(
            "Product will be upgraded to: %1 (this is the new one)",
            product
          )

          if old_display_name == display_name
            ret = Ops.add(
              Ops.add(
                Ops.add(ret, "<li>"),
                Builtins.sformat(
                  _("Product <b>%1</b> will be upgraded"),
                  GetDisplayName(old_display_name, old_product_name)
                )
              ),
              "</li>\n"
            )
          else
            ret = Ops.add(
              Ops.add(
                Ops.add(ret, "<li>"),
                Builtins.sformat(
                  _("Product <b>%1</b> will be upgraded to <b>%2</b>"),
                  GetDisplayName(old_display_name, old_product_name),
                  GetDisplayName(display_name, name)
                )
              ),
              "</li>\n"
            )
          end 
          # Newly installed product
        else
          Builtins.y2milestone("New product will be installed: %1", product)
          ret = Ops.add(
            Ops.add(
              Ops.add(ret, "<li>"),
              Builtins.sformat(
                _("New product <b>%1</b> will be installed"),
                GetDisplayName(display_name, name)
              )
            ),
            "</li>\n"
          )
        end
      end

      # Products that will keep installed (unchanged)
      Builtins.foreach(products) do |product|
        next if Ops.get_symbol(product, "status", :unknown) != :installed
        product = MinimizeProductMap(product)
        display_name = Ops.get_locale(
          product,
          "display_name",
          Ops.get_locale(
            product,
            "short_name",
            Ops.get_locale(product, "name", _("No name defined."))
          )
        )
        name = Ops.get_locale(product, "name", _("No short name defined."))
        Builtins.y2milestone("Product will keep: %1", product)
        ret = Ops.add(
          Ops.add(
            Ops.add(ret, "<li>"),
            Builtins.sformat(
              _("Product <b>%1</b> will stay installed"),
              GetDisplayName(display_name, name)
            )
          ),
          "</li>\n"
        )
      end

      ret = Ops.add(Ops.add("<ul>\n", ret), "</ul>\n")

      ret = Ops.add(
        Ops.add(
          Ops.add(
            Ops.add(ret, "<ul><li>\n"),
            _("Download all packages before upgrade: ")
          ),
          Builtins.sformat(
            "<a href=\"%1\">%2</a>",
            @download_mode_link,
            PackageInstallation.DownloadInAdvance ? _("Enabled") : _("Disabled")
          )
        ),
        "</li></ul>\n"
      )

      summary = {
        "preformatted_proposal" => ret,
        "links"                 => [@download_mode_link],
        # help text
        "help"                  => _(
          "<p>To change the update settings, go to <b>Packages Proposal</b> section.</p>"
        )
      }

      # Product removal MUST be confirmed by user, otherwise migration will not continue.
      if Ops.greater_than(products_removed_by_solver, 0)
        Ops.set(summary, "warning_level", :blocker)
        Ops.set(
          summary,
          "warning",
          Ops.add(
            Ops.add(
              "<ul>",
              Ops.greater_than(products_removed_by_solver, 1) ?
                Builtins.sformat(
                  _(
                    "<li><b>%1 products will be removed.\n" +
                      "Go to the packages proposal and resolve the issue manually.<br>\n" +
                      "It is safe to abort the migration now.</b></li>\n"
                  ),
                  products_removed_by_solver
                ) :
                _(
                  "<li><b>One product will be removed.\n" +
                    "Go to the packages proposal and solve the issue manually.<br>\n" +
                    "It is safe to abort the migration now.</b></li>\n"
                )
            ),
            "</ul>"
          )
        )
      end

      deep_copy(summary)
    end

    def ReadProductsBeforeMigration
      products = Pkg.ResolvableProperties("", :product, "")
      Builtins.y2milestone("All known products: %1", products)

      Builtins.foreach(products) do |p|
        next if Ops.get_symbol(p, "status", :unknown) != :installed
        # Remember the 'old' product just for the case of reverting
        @products_before_migration = Builtins.add(
          @products_before_migration,
          {
            "name"    => Ops.get_string(p, "name", ""),
            "version" => Ops.get_string(p, "version", "")
          }
        )
      end

      deep_copy(@products_before_migration)
    end

    def StoreProductsBeforeMigration
      SCR.Write(
        path(".target.ycp"),
        @migration_products_store_file,
        @products_before_migration
      )
    end

    def RestoreProductsBeforeMigration
      @products_before_migration = Convert.convert(
        SCR.Read(path(".target.ycp"), @migration_products_store_file),
        :from => "any",
        :to   => "list <map <string, string>>"
      )

      if @products_before_migration == nil
        @products_before_migration = []
        Report.Error(
          _("Error restoring the list of previously installed products.")
        )
        return false
      end

      true
    end

    def GetFileOwner(file)
      if file == nil || file == ""
        Builtins.y2error("File not provided")
        return nil
      end

      if !FileUtils.Exists(file)
        Builtins.y2error("File %1 doesn't exist", file)
        return nil
      end

      command = Ops.add(
        Builtins.sformat("rpm -qf '%1'", String.Quote(file)),
        " --queryformat \"%{NAME}\""
      )
      cmd = Convert.convert(
        SCR.Execute(path(".target.bash_output"), command),
        :from => "any",
        :to   => "map <string, any>"
      )
      if Ops.get_integer(cmd, "exit", -1) != 0
        Builtins.y2error("Cannot get file owner %1: %2", command, cmd)
        return nil
      end

      Ops.get(Builtins.splitstring(Ops.get_string(cmd, "stdout", ""), "\n"), 0)
    end

    def LogAllRepos
      # We assume all repositories are already loaded
      Builtins.y2milestone("------ All repositories ------")
      Builtins.foreach(
        Pkg.SourceGetCurrent(
          false # not only enabled ones
        )
      ) do |one_repo|
        Builtins.y2milestone(
          "REPO %1: GeneralData: %2 ProductData: %3",
          one_repo,
          Pkg.SourceGeneralData(one_repo),
          MinimizeProductMap(Pkg.SourceProductData(one_repo))
        )
      end
      Builtins.y2milestone("------ All repositories ------")

      nil
    end

    def RunHook(script_name)
      if script_name == nil || script_name == ""
        Builtins.y2error("Script name '%1' is not supported", script_name)
      end

      script_name = Builtins.sformat(
        "/usr/lib/YaST2/bin/wagon_hook_%1",
        script_name
      )

      if !FileUtils.Exists(script_name)
        Builtins.y2milestone(
          "Hook script %1 doesn't exist, nothing to run",
          script_name
        )
        return false
      end

      Builtins.y2milestone("Running hook %1", script_name)
      cmd = Convert.to_map(
        WFM.Execute(path(".local.bash_output"), String.Quote(script_name))
      )

      if Ops.get_integer(cmd, "exit", -1) != 0
        Builtins.y2error("Hook script returned: %1", cmd)
        Report.Error(
          Builtins.sformat(_("Error running hook script %1."), script_name)
        )
        return false
      end

      Builtins.y2milestone("Hook script returned: %1", cmd)

      true
    end

    # find hook scripts for the step
    # the result is sorted in the execution order
    def HookScripts(step)
      # get all hooks
      all_scripts = Convert.convert(
        SCR.Read(path(".target.dir"), @hook_dir),
        :from => "any",
        :to   => "list <string>"
      )

      if all_scripts == nil || all_scripts == []
        Builtins.y2milestone("No hook scripts found")
        return []
      end

      # get the list of scripts for this step/stage
      scripts = Builtins.filter(all_scripts) do |script|
        Builtins.regexpmatch(script, Ops.add(Ops.add("^", step), "_[0-9]+_"))
      end

      if Ops.greater_than(Builtins.size(scripts), 0)
        # sort the scripts to ensure the order
        scripts = Builtins.sort(scripts)

        Builtins.y2milestone("Found scripts for step '%1': %2", step, scripts)
      end

      deep_copy(scripts)
    end

    # Run a hook script for the current step
    # The scripts are loaded from /var/lib/YaST2/wagon/hooks/ directory.
    #
    # The expected script name is:  <step>_<seq>_<prefix>_<name>
    #
    # step - migration step name, e.g. before_package_migration
    # seq - sequence number 00..99 (it's important to keep the beginning zeros for correct sorting!)
    # prefix - should be unique to avoid conflicts, use package name (if it is part of a package)
    #      or your (vendor) name, internet domain name, etc... basicaly anything which can be considered
    #      enough unique
    # name - any name (just to differ the scripts), some descriptive name is recommended
    #
    # The script should return exit value 0, if it fails (non-zero exit value) an error message is displayed
    # and is possible to start the script again.
    #
    # The scripts can be potentionally run more times (when going back and forth in the wagon dialogs),
    # the scripts have to cope with that fact (they can check whether they need to do something or they for example
    # can create a simple temporary stamp file).
    #
    # Example script name (with full path): /var/lib/YaST2/wagon/hooks/before_package_migration_00_postgresql_backup
    #
    # See doc/Migration_Hooks.md file for details (list of the supported hooks)
    #
    #
    def RunHooks(step)
      Builtins.y2milestone("Running hooks for step: %1", step)

      scripts = HookScripts(step)
      canceled = false

      # run the scripts
      Builtins.foreach(scripts) do |script|
        run_again = false
        begin
          run_again = false
          Builtins.y2milestone("Executing hook script: %1", script)

          # %1 is a file name
          UI.OpenDialog(
            Label(Builtins.sformat(_("Executing script %1 ..."), script))
          )
          ret = Convert.to_integer(
            SCR.Execute(
              path(".target.bash"),
              Ops.add(Ops.add(@hook_dir, "/"), script)
            )
          )
          UI.CloseDialog

          Builtins.y2milestone("Script returned: %1", ret)

          if ret != 0
            ui = Popup.AnyQuestion3(
              Label.ErrorMsg,
              # TRANSLATORS: Error message displayed in a popup dialog with [Continue], [Cancel] and [Retry] buttons
              # Continue = ignore the failure and run the other scripts for this step (if present)
              # Cancel = quit, don't run anything
              # Retry = run it again, retry it
              Builtins.sformat(
                _(
                  "Hook script '%1' failed\n" +
                    "\n" +
                    "Continue with other scripts, cancel scripts or try it again?"
                ),
                script
              ),
              _("Continue"),
              _("Cancel"),
              _("Retry"),
              :focus_yes
            )

            Builtins.y2milestone("User input: %1", ui)

            if ui == :retry
              run_again = true
            elsif ui == :no
              Builtins.y2milestone("Canceling the hook scripts")
              canceled = true
            end
          end
        end while run_again
        raise Break if canceled
      end

      nil
    end

    # Check whether NCC or SMT is used for registration
    def NCCUsed
      # check /etc/suseRegister.conf content
      conf = Convert.to_string(
        SCR.Read(path(".target.string"), "/etc/suseRegister.conf")
      )

      if conf == nil
        Builtins.y2error("Cannot read /etc/suseRegister.conf")
        return nil
      end

      lines = Builtins.splitstring(conf, "\n")

      found_url = false
      found_ncc = false

      Builtins.foreach(lines) do |line|
        if Builtins.regexpmatch(line, "^[ \t]*url[ \t]*=[ \t]*")
          found_url = true
          Builtins.y2milestone("Found registration URL option: %1", line)

          if Builtins.regexpmatch(
              line,
              "^[ \t]*url[ \t]*=[ \t]*https://secure-www.novell.com/center/regsvc/*[ \t]*(#*.*)*"
            )
            found_ncc = true
            Builtins.y2milestone("NCC URL found")
          end
        end
      end

      if !found_url
        Builtins.y2error("No url option found in /etc/suseRegister.conf")
        return nil
      end

      Builtins.y2milestone("Found NCC registration server: %1", found_ncc)

      found_ncc
    end

    # * Read registration status and sort products according their status
    # * @param file Read this registration status file
    # * @return map<string,any> result: $[
    # *
    # 	    "registered_system" : (boolean) - true registration was run, false registration has never run or there is no product to register (e.g. openSUSE installation) or the registration completely failed
    # 	    "timestamp"		: (integer) - time when the status was saved (unix time), -1 in an unregistered system
    # 	    "registered"	: (list<string>) - registered products
    # 	    "provisional"	: (list<string>) - products with provisional subscription (registered, but no updates available)
    # 	    "rma"		: (list<string>) - refunded subscriptions, not active anymore
    # 	    "expired"		: (list<string>) - expired subscriptions
    # 	    "no_subscription"	: (list<string>) - products which do not need a subscription (e.g. SLES-SDK)
    # 	    "failed"		: (list<string>) - registration failed (e.g. invalid registration code)
    # * ]
    def RegistrationStatusFromFile(file)
      registered_system = true
      timestamp = -1

      failed = []
      no_subscription = []
      expired = []
      rma = []
      provisional = []
      registered = []

      # 0 = empty file, -1 = missing
      if Ops.less_or_equal(FileUtils.GetSize(file), 0)
        Builtins.y2milestone("File %1 does not exist", file)
        registered_system = false
      else
        # read the registration status
        # see https://wiki.innerweb.novell.com/index.php/Registration#Add_Registration_Status_to_zmdconfig
        # for more datils about the file format
        status = RegistrationStatus.ReadFile(file)

        timestamp = Builtins.tointeger(
          Ops.get_string(status, "generated", "-1")
        )

        read_products = Ops.get(status, "productstatus")
        products = Ops.is_map?(read_products) ?
          [Convert.to_map(read_products)] :
          Convert.convert(read_products, :from => "any", :to => "list <map>")

        # check each product
        Builtins.foreach(products) do |product|
          product_name = Ops.get_string(product, "product", "")
          # not registered (error present, but not "expired")
          if Ops.get_string(product, "result", "") == "error" &&
              Ops.get_string(product, "errorcode", "") != "ERR_SUB_EXP"
            failed = Builtins.add(failed, product_name)
          else
            # registered, but subscription is not needed (e.g. SLES-SDK)
            if Ops.get_map(product, "subscription", {}) == {}
              no_subscription = Builtins.add(no_subscription, product_name)
            else
              status2 = Ops.get_string(product, ["subscription", "status"], "")
              expiration = Ops.get_string(
                product,
                ["subscription", "expiration"],
                ""
              )

              # expired subscription (status == EXPIRED or the timestamp is in the past)
              if status2 == "EXPIRED" ||
                  expiration != "" &&
                    Ops.less_than(Builtins.tointeger(expiration), Builtins.time)
                expired = Builtins.add(expired, product_name)
              elsif status2 == "RMA"
                rma = Builtins.add(rma, product_name)
              else
                type = Ops.get_string(product, ["subscription", "type"], "")

                # provisional subscription
                if type == "PROVISIONAL"
                  provisional = Builtins.add(provisional, product_name)
                else
                  registered = Builtins.add(registered, product_name)
                end
              end
            end
          end
        end
      end

      {
        "registered_system" => registered_system,
        "timestamp"         => timestamp,
        "registered"        => registered,
        "provisional"       => provisional,
        "rma"               => rma,
        "expired"           => expired,
        "no_subscription"   => no_subscription,
        "failed"            => failed
      }
    end

    # * Read registration status from /var/lib/suseRegister/registration-status.xml and sort products according their status
    # * @return map<string,any> result: $[
    # *
    # 	    "registered_system" : (boolean) - true registration was run, false registration has never run or there is no product to register (e.g. openSUSE installation) or the registration completely failed
    # 	    "ncc"		: (boolean) - true - NCC is used for registration, false - a SMT server is configured, nil - not configured or other error
    # 	    "timestamp"		: (integer) - time when the status was saved (unix time), -1 in an unregistered system
    # 	    "registered"	: (list<string>) - registered products
    # 	    "provisional"	: (list<string>) - products with provisional subscription (registered, but no updates available)
    # 	    "rma"		: (list<string>) - refunded subscriptions, not active anymore
    # 	    "expired"		: (list<string>) - expired subscriptions
    # 	    "no_subscription"	: (list<string>) - products which do not need a subscription (e.g. SLES-SDK)
    # 	    "failed"		: (list<string>) - registration failed (e.g. invalid registration code)
    # * ]
    def RegistrationStatus
      ret = RegistrationStatusFromFile(RegistrationStatus.RegFile)
      Ops.set(ret, "ncc", NCCUsed())

      deep_copy(ret)
    end

    publish :variable => :migration_products, :type => "list <string>"
    publish :variable => :products_before_migration, :type => "list <map <string, string>>"
    publish :variable => :disabled_repositories, :type => "list <string>"
    publish :variable => :repositories_to_disable, :type => "list <string>"
    publish :variable => :abort_can_revert_products, :type => "boolean"
    publish :variable => :repos_already_registered, :type => "boolean"
    publish :variable => :check_repositories_manually, :type => "boolean"
    publish :function => :SetUpdateWorkflow, :type => "void (string)"
    publish :function => :GetUpdateWorkflow, :type => "string ()"
    publish :function => :GetDownloadModeLink, :type => "string ()"
    publish :variable => :migration_method_file, :type => "string"
    publish :function => :SetMigrationMethod, :type => "boolean (string)"
    publish :function => :GetMigrationMethod, :type => "string ()"
    publish :function => :DupRepos, :type => "list <integer> ()"
    publish :function => :SetDupRepos, :type => "void (list <integer>)"
    publish :function => :ManualRepoSelection, :type => "boolean ()"
    publish :function => :SetManualRepoSelection, :type => "void (boolean)"
    publish :function => :RegistrationRepos, :type => "list <string> ()"
    publish :function => :SetRegistrationRepos, :type => "void (list <string>)"
    publish :function => :MigrationType, :type => "symbol ()"
    publish :function => :SetMigrationType, :type => "boolean (symbol)"
    publish :function => :SetWizardSteps, :type => "boolean ()"
    publish :function => :AdjustVariableSteps, :type => "void ()"
    publish :function => :RedrawWizardSteps, :type => "void ()"
    publish :function => :AdjustWizardSteps, :type => "boolean ()"
    publish :function => :Init, :type => "void (map <string, any>)"
    publish :function => :InitPkg, :type => "boolean ()"
    publish :function => :ProcessCommandLine, :type => "void (map <string, any>)"
    publish :function => :AcceptLicenses, :type => "boolean ()"
    publish :function => :ResetDUPProposal, :type => "void ()"
    publish :function => :ProposeDUP, :type => "boolean ()"
    publish :function => :ProposeDownloadMode, :type => "void ()"
    publish :function => :MinimizeProductMap, :type => "map <string, any> (map <string, any>)"
    publish :function => :ProposalSummary, :type => "map <string, any> ()"
    publish :function => :ReadProductsBeforeMigration, :type => "list <map <string, string>> ()"
    publish :function => :StoreProductsBeforeMigration, :type => "boolean ()"
    publish :function => :RestoreProductsBeforeMigration, :type => "boolean ()"
    publish :function => :GetFileOwner, :type => "string (string)"
    publish :function => :LogAllRepos, :type => "void ()"
    publish :function => :RunHook, :type => "boolean (string)"
    publish :function => :RunHooks, :type => "void (string)"
    publish :function => :RegistrationStatusFromFile, :type => "map <string, any> (string)"
    publish :function => :RegistrationStatus, :type => "map <string, any> ()"
  end

  Wagon = WagonClass.new
  Wagon.main
end
