# encoding: utf-8

# File:
#	clients/wagon_migration_products.ycp
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
  class WagonMigrationProductsClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      # Selects and installs all migration products.

      textdomain "wagon"

      Yast.import "Wagon"
      Yast.import "PackagesUI"
      Yast.import "GetInstArgs"
      Yast.import "Report"
      Yast.import "Popup"
      Yast.import "Label"

      Yast.include self, "wagon/common_func.rb"

      if GetInstArgs.going_back
        Builtins.y2milestone("Going back...")
        return :back
      end

      Wagon.RunHooks("before_installing_migration_products")

      Wagon.InitPkg

      Wagon.ReadProductsBeforeMigration
      Wagon.StoreProductsBeforeMigration

      # BNC #573084: New code (upgrading products) can be added after
      # wagon self-upgrade and restart
      @products_for_upgrade = UpdateInstalledProducts()

      if Ops.greater_than(@products_for_upgrade, 0)
        @ret2 = SolveDependencies()

        if @ret2 != :abort && @ret2 != :cancel
          Builtins.y2milestone(
            "Upgrading %1 product packages...",
            @products_for_upgrade
          )
          @inst_ret = WFM.call("inst_rpmcopy")
          Builtins.y2milestone(
            "Product package upgrade returned: %1",
            @inst_ret
          )
          @ret2 = :auto
        else
          return :abort
        end

        ResetPackager()
      else
        Builtins.y2warning("No products selected for upgrade")
      end

      if FindAndSelectMigrationProducts() != true
        Wagon.RunHooks("after_installing_migration_products")
        return :auto
      end

      @ret = SolveDependencies()

      if @ret != :abort && @ret != :cancel
        # Solver ends with some resolvables changed
        if Pkg.IsAnyResolvable(:any, :to_install) == true ||
            Pkg.IsAnyResolvable(:any, :to_remove) == true
          Builtins.y2milestone("Installing packages...")
          # Everybody hold your breath 'cause we're gonna be sinkin' soon
          @inst_ret = WFM.call("inst_rpmcopy")
          Builtins.y2milestone("Package installation returned: %1", @inst_ret)
          @ret = :auto
        else
          Builtins.y2milestone("Nothing to install/remove")
          @ret = :auto
        end
      end

      ResetPackager()

      Wagon.RunHooks("after_installing_migration_products") if @ret == :auto

      Builtins.y2milestone("Returning: %1", @ret)

      @ret
    end

    def UpdateInstalledProducts
      affected_products = 0

      products = Pkg.ResolvableProperties("", :product, "")

      Builtins.foreach(products) do |p|
        # Product is not installed
        next if Ops.get_symbol(p, "status", :unknown) != :installed
        # Make the logs readable
        Ops.set(p, "license", "...")
        Ops.set(p, "description", "...")
        product_name = Ops.get_string(p, "name", "")
        product_version = Ops.get_string(p, "version", "")
        if product_name == nil || product_name == ""
          Builtins.y2error("Cannot distinguish product name: %1", product_name)
          next
        end
        # Product version is the same but release can be different
        # product map doesn't contain the release string. To be sure, product will be reinstalled
        Builtins.y2milestone(
          "Upgrading product %1 version %2",
          product_name,
          product_version
        )
        # The version is the same, release can be different
        if Pkg.ResolvableInstall(product_name, :product) != true
          Report.Error(
            Builtins.sformat(
              _("Cannot update installed product %1."),
              product_name
            )
          )
          next
        end
        affected_products = Ops.add(affected_products, 1)
      end

      affected_products
    end

    def FindAndSelectMigrationProducts
      if Wagon.InitPkg != true
        Report.Error(_("Unable to initialize the software manager."))
        return false
      end

      products = Pkg.ResolvableProperties("", :product, "")

      Builtins.foreach(products) do |p|
        if Ops.get_symbol(p, "status", :unknown) != :installed
          Builtins.y2milestone(
            "Product %1 (%2) is not installed, skipping...",
            Ops.get_string(p, "name", "not-defined"),
            Ops.get_string(
              p,
              "short_name",
              Ops.get_string(p, "display_name", "not-defined")
            )
          )
          next
        end
        if !Builtins.haskey(p, "upgrades") ||
            Ops.get_list(p, "upgrades", []) == []
          Builtins.y2warning(
            "Product %1 (%2) does not contain 'upgrades' section...",
            Ops.get_string(p, "name", "not-defined"),
            Ops.get_string(
              p,
              "short_name",
              Ops.get_string(p, "display_name", "not-defined")
            )
          )
          next
        end
        Builtins.y2milestone(
          "Going to upgrade product %1 (%2)",
          Ops.get_string(p, "name", "not-defined"),
          Ops.get_string(
            p,
            "short_name",
            Ops.get_string(p, "display_name", "not-defined")
          )
        )
        if Ops.get_string(p, "name", "") == nil ||
            Ops.get_string(p, "name", "") == ""
          Builtins.y2error(
            "Product %1 doesn't have a name, reverting will be impossible",
            p
          )
          Report.Error(
            Builtins.sformat(
              _(
                "Product %1 does not have a machine-readable 'name'.\nAutomatic reverting of the product state will be impossible."
              ),
              Ops.get_string(
                p,
                "short_name",
                Ops.get_string(p, "display_name", "not-defined")
              )
            )
          )
        end
        Builtins.foreach(Ops.get_list(p, "upgrades", [])) do |supported_upgrade|
          if !Builtins.haskey(supported_upgrade, "product") ||
              Ops.get_string(supported_upgrade, "product", "") == ""
            Builtins.y2error(
              "Erroneous product upgrades: %1 (%2)",
              p,
              supported_upgrade
            )
            Report.Error(
              Builtins.sformat(
                _(
                  "Cannot upgrade product %1 (%2).\nMigration path is erroneous."
                ),
                Ops.get_locale(
                  p,
                  "display_name",
                  Ops.get_locale(p, "short_name", _("Unknown"))
                ),
                Ops.get_locale(p, "name", _("undefined"))
              )
            )
            next
          end
          old_product = Ops.get_string(p, "name", "")
          migration_product = Ops.get_string(supported_upgrade, "product", "")
          # Install the migration product
          if Builtins.size(
              Pkg.ResolvableProperties(migration_product, :product, "")
            ) == 0 ||
              Pkg.ResolvableInstall(migration_product, :product) != true
            Builtins.y2error(
              "Cannot select migration product for installation: %1",
              Pkg.ResolvableProperties(migration_product, :product, "")
            )
            Report.Error(
              Builtins.sformat(
                _("Cannot select product\n%1 (%2) for installation."),
                Ops.get_string(supported_upgrade, "name", ""),
                migration_product
              )
            )
            next
          else
            Wagon.migration_products = Builtins.add(
              Wagon.migration_products,
              migration_product
            )
          end # Old products are removed automatically during the upgrade
          #		// Remove the old product
          #		if ((Pkg::ResolvableInstalled (old_product, `product) != true) || (Pkg::ResolvableRemove (migration_product, `product) == true)) {
          #		    Report::Error (sformat (_("Cannot select product %1 for deinstallation."), migration_product));
          #		    return;
          #		}
        end
      end

      true
    end

    # Finds all products that contain information about their migration product
    # finds which repositories provide these products and disables the
    # repositories.
    #
    # @see BNC #573092
    def FindOldRepositoriesToBeDisabled
      if Wagon.InitPkg != true
        Report.Error(_("Unable to initialize the software manager."))
        return false
      end

      products = Pkg.ResolvableProperties("", :product, "")

      # all known products
      products = Builtins.filter(products) do |p|
        # skip those not installed ones
        if Ops.get_symbol(p, "status", :unknown) != :installed
          Builtins.y2milestone(
            "Product %1 (%2) is not installed, skipping...",
            Ops.get_string(p, "name", "not-defined"),
            Ops.get_string(
              p,
              "short_name",
              Ops.get_string(p, "display_name", "not-defined")
            )
          )
          next false
        end
        # skip those that do not provide 'upgrades' section
        if !Builtins.haskey(p, "upgrades") ||
            Ops.get_list(p, "upgrades", []) == []
          Builtins.y2warning(
            "Product %1 (%2) does not contain 'upgrades' section...",
            Ops.get_string(p, "name", "not-defined"),
            Ops.get_string(
              p,
              "short_name",
              Ops.get_string(p, "display_name", "not-defined")
            )
          )
          next false
        end
        Builtins.y2milestone(
          "Going to disable repositories providing product %1 (%2)",
          Ops.get_string(p, "name", "not-defined"),
          Ops.get_string(
            p,
            "short_name",
            Ops.get_string(p, "display_name", "not-defined")
          )
        )
        if Ops.get_string(p, "name", "") == nil ||
            Ops.get_string(p, "name", "") == ""
          Builtins.y2error(
            "Product %1 doesn't have a name, reverting will be impossible",
            p
          )
          Report.Error(
            Builtins.sformat(
              _(
                "Product %1 does not have a machine-readable 'name'.\nIt cannot be disabled."
              ),
              Ops.get_string(
                p,
                "short_name",
                Ops.get_string(p, "display_name", "not-defined")
              )
            )
          )
          next false
        end
        true
      end

      # all installed, those that provide 'upgrades' section, and have a name
      Builtins.foreach(products) do |p|
        # Find all available matching products
        matching_products = Pkg.ResolvableProperties(
          Ops.get_string(p, "name", ""),
          :product,
          ""
        )
        matching_products = Builtins.filter(matching_products) do |one_product|
          Ops.get_symbol(one_product, "status", :unknown) == :available
        end
        product_repos = []
        repo_id = nil
        repo_details = nil
        # installed product is not available anymore
        if matching_products == nil || Builtins.size(matching_products) == 0
          matching_products = []
          Builtins.y2warning(
            "Nothing provides `available product: '%1'",
            Ops.get_string(p, "name", "")
          )
        else
          Builtins.foreach(matching_products) do |one_product|
            repo_id = Ops.get_integer(one_product, "source", -1)
            if repo_id == nil || Ops.less_than(repo_id, 0)
              Builtins.y2error(
                "Available product with wrong source id: %1",
                Wagon.MinimizeProductMap(one_product)
              )
            else
              Builtins.y2milestone(
                "Repo %1 will be disabled, provides product %2",
                repo_id,
                Ops.get_string(p, "name", "")
              )
              product_repos = Builtins.add(product_repos, repo_id)
            end
          end
        end
        # BNC #579905: Some repositories provide packages with products but these products
        # are not mentioned in metadata. We have to disable also these repositories.
        inst_product_package_name = GetProductPackageName(p)
        matching_packages = Pkg.ResolvableProperties(
          inst_product_package_name,
          :package,
          ""
        )
        Builtins.foreach(matching_packages) do |one_package|
          # operate with available packages only
          next if Ops.get_symbol(one_package, "status", :unknown) != :available
          repo_id = Ops.get_integer(one_package, "source", -1)
          if repo_id == nil || Ops.less_than(repo_id, 0)
            Builtins.y2error(
              "Available package with wrong source id: %1",
              Wagon.MinimizeProductMap(one_package)
            )
          else
            Builtins.y2milestone(
              "Repo %1 will be disabled, provides product package %2",
              repo_id,
              inst_product_package_name
            )
            product_repos = Builtins.add(product_repos, repo_id)
          end
        end
        # Check all
        Builtins.foreach(product_repos) do |repo_id2|
          repo_details = Pkg.SourceGeneralData(repo_id2)
          Wagon.repositories_to_disable = Builtins.add(
            Wagon.repositories_to_disable,
            Ops.get_string(repo_details, "alias", "")
          )
        end
        Wagon.repositories_to_disable = Builtins.toset(
          Wagon.repositories_to_disable
        )
      end

      Builtins.y2milestone(
        "Repositories to be disabled later: %1",
        Wagon.repositories_to_disable
      )

      true
    end
  end
end

Yast::WagonMigrationProductsClient.new.main
