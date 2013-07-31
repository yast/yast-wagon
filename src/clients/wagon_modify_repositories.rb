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
  class WagonModifyRepositoriesClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      # Modify repositories as needed.

      textdomain "wagon"

      Yast.import "Wagon"
      Yast.import "GetInstArgs"
      Yast.import "Report"

      Yast.include self, "wagon/common_func.rb"

      if GetInstArgs.going_back
        Builtins.y2milestone("Going back...")
        return :back
      end

      @ret = :auto

      Wagon.InitPkg

      @repo_id = nil

      Builtins.foreach(Wagon.repositories_to_disable) do |repo_alias|
        @repo_id = FindRepoIdByAlias(repo_alias)
        if @repo_id == nil
          Builtins.y2error(
            "Cannot disable repository %1, alias not found",
            repo_alias
          )
          next
        end
        Builtins.y2milestone(
          "Disabling repository (alias)%1 (id)%2 returned: %3",
          repo_alias,
          @repo_id,
          Pkg.SourceSetEnabled(@repo_id, false)
        )
        Wagon.disabled_repositories = Builtins.add(
          Wagon.disabled_repositories,
          repo_alias
        )
      end

      if Ops.greater_than(Builtins.size(Wagon.disabled_repositories), 0)
        Pkg.SourceSaveAll
      end

      ResetPackager()

      Builtins.y2milestone("Returning: %1", @ret)

      @ret
    end
  end
end

Yast::WagonModifyRepositoriesClient.new.main
