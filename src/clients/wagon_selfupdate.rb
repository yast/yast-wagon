# encoding: utf-8

# File:
#	clients/wagon_selfupdate.ycp
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
  class WagonSelfupdateClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "wagon"

      Yast.import "GetInstArgs"
      Yast.import "Wagon"
      Yast.import "FileUtils"
      Yast.import "ProductControl"
      Yast.import "ProductFeatures"
      Yast.import "Internet"
      Yast.import "OnlineUpdateCallbacks"
      Yast.import "Popup"
      Yast.import "Label"
      Yast.import "PackagesUI"
      Yast.import "Report"

      Yast.include self, "wagon/common_func.rb"

      if GetInstArgs.going_back
        Builtins.y2milestone("Going back...")
        return :back
      end

      Wagon.RunHooks("before_self_update")

      Wagon.InitPkg

      @ret = :auto

      # Patches need solver run
      Pkg.PkgSolve(true)

      # Here the update stack updates itself
      @selected = Pkg.ResolvablePreselectPatches(:affects_pkg_manager)

      # No patches selected
      if Ops.less_than(@selected, 1)
        Builtins.y2milestone(
          "There are no patches that would affect the package manager, trying packages..."
        )

        @pkgs = ProductFeatures.GetFeature(
          "software",
          "packages_affecting_pkg_manager"
        )

        if @pkgs == nil || @pkgs == "" || @pkgs == []
          Builtins.y2warning("No packages_affecting_pkg_manager provided")
        else
          @packages = Convert.convert(
            @pkgs,
            :from => "any",
            :to   => "list <string>"
          )
          Builtins.y2milestone("Packages to upgrade: %1", @packages)
          @selected = (
            packages_ref = arg_ref(@packages);
            _UpgradePackages_result = UpgradePackages(packages_ref);
            @packages = packages_ref.value;
            _UpgradePackages_result
          )
        end
      end

      Builtins.y2milestone("Selected resolvables: %1", @selected)
      if Ops.less_than(@selected, 1)
        Builtins.y2milestone(
          "Neither patches nor packages for self-update have been selected"
        )

        Wagon.RunHooks("after_self_update")

        return @ret
      end

      @ret = SolveDependencies()

      if @ret != :abort
        # Solver ends with some resolvables changed
        if Pkg.IsAnyResolvable(:any, :to_install) == true ||
            Pkg.IsAnyResolvable(:any, :to_remove) == true
          Builtins.y2milestone("Calling update...")
          OnlineUpdateCallbacks.RegisterOnlineUpdateCallbacks
          @oui_ret = WFM.call("online_update_install")
          Builtins.y2milestone("Update returned: %1", @oui_ret)
          @ret = :restart_same_step
        else
          Builtins.y2milestone("Nothing to install/remove")
          @ret = :auto
        end

        Wagon.RunHooks("after_self_update")
      end

      Builtins.y2milestone("Returning: %1", @ret)

      @ret
    end

    # Tries to upgrade packages got as parameter.
    #
    # @param list <string> of packages
    def UpgradePackages(packages)
      # Check the input
      packages.value = Builtins.filter(packages.value) do |one_package|
        one_package != nil && one_package != ""
      end

      pkgs_affected = 0

      installed_versions = {}

      some_packages_selected = false

      Builtins.foreach(packages.value) do |one_package|
        # All packages of the given name
        respros = Pkg.ResolvableProperties(one_package, :package, "")
        # All installed packages of the given name
        installed = Builtins.filter(respros) do |one_respro|
          Ops.get_symbol(one_respro, "status", :unknown) == :installed
        end
        # All available packages of the given name
        available = Builtins.filter(respros) do |one_respro|
          Ops.get_symbol(one_respro, "status", :unknown) == :available
        end
        # Such package is not installed
        if Ops.less_than(Builtins.size(installed), 1)
          Builtins.y2milestone("Package %1 is not installed", one_package)
          next
        end
        # Er, installed but not available
        if Ops.less_than(Builtins.size(available), 1)
          Builtins.y2warning(
            "Package %1 is installed but not available",
            one_package
          )
          next
        end
        # Remember the installed version(s)
        Ops.set(installed_versions, one_package, Builtins.maplist(installed) do |one_installed|
          Ops.get_string(one_installed, "version", "unknown")
        end)
        # Force upgrade/install
        Builtins.y2milestone(
          "Selecting package %1 for installation",
          one_package
        )
        if Pkg.ResolvableInstall(one_package, :package) == true
          some_packages_selected = true
        else
          Builtins.y2error("Cannot install package %1", one_package)
        end
      end

      if some_packages_selected != true
        Builtins.y2milestone("No packages have been selected for upgrade")
        return pkgs_affected
      end

      # Calling solver to select the best version
      SolverRunWithFeedback()

      Builtins.y2milestone("Some packages have been selected, checking...")

      # Check whether the selected version is different to the already installed one
      Builtins.foreach(installed_versions) do |one_package, previously_installed_versions|
        respros = Pkg.ResolvableProperties(one_package, :package, "")
        # All selected packages of the given name
        selected = Builtins.filter(respros) do |one_respro|
          Ops.get_symbol(one_respro, "status", :unknown) == :selected
        end
        # The package of a given name is selected
        if Ops.greater_than(Builtins.size(selected), 0)
          selection_differs = false

          Builtins.foreach(selected) do |one_selected|
            if !Builtins.contains(
                previously_installed_versions,
                Ops.get_string(one_selected, "version", "some-version")
              )
              pkgs_affected = Ops.add(pkgs_affected, 1)
              selection_differs = true
              raise Break
            end
          end

          if selection_differs != true
            Builtins.y2milestone(
              "Selection of packages doesn't differ, neutralizing package: %1",
              one_package
            )
            Pkg.ResolvableNeutral(one_package, :package, false)
          end
        end
      end

      pkgs_affected
    end
  end
end

Yast::WagonSelfupdateClient.new.main
