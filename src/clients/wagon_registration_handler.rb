# encoding: utf-8

# File:
#	clients/wagon_registration_handler.ycp
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
# $Id:$
#
module Yast
  class WagonRegistrationHandlerClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      # This is a handler scipt for registration that checks whether registration
      # did its job and whether or not has user skipped it.
      # See more in BNC #575102.

      Yast.import "Wagon"
      Yast.import "Popup"
      Yast.import "Mode"

      textdomain "wagon"

      Yast.include self, "wagon/common_func.rb"

      Wagon.RunHooks("before_registration")

      # all repository aliases
      @all_repos = GetCurrentlyEnabledReposByAlias()
      Builtins.y2milestone("Currently registered repositories: %1", @all_repos)

      # BNC #576553: Adjusts suse_config sysconfig values according the control file
      AdjustSuseRegisterDefaults()

      @ret = :auto

      AdjustRegistrationHandlerScreen()

      while true
        # Only in mode=="normal" suse_register reads settings from sysconfig
        Mode.SetMode("normal")
        Builtins.y2milestone("Running inst_suse_register...")
        @ret = Convert.to_symbol(
          WFM.CallFunction("inst_suse_register", WFM.Args)
        )
        Builtins.y2milestone("Script inst_suse_register returned: %1", @ret)
        Mode.SetMode("update")

        AdjustRegistrationHandlerScreen()

        # `abort, `cancel, `back ...
        # Just return the symbol
        if @ret != :next
          Builtins.y2milestone("Registration returned %1", @ret)
          break
        end
        # --> `next

        # Registration must have done something with repositories
        # e.g., register new ones, disable old ones - that's wanted
        @current_repos = GetCurrentlyEnabledReposByAlias()
        if @all_repos != @current_repos
          Wagon.repos_already_registered = true

          # remember the added repositories
          @added = AddedRepos(@all_repos, @current_repos)
          Wagon.SetRegistrationRepos(@added)

          Builtins.y2milestone(
            "List of repositories has changed: %1",
            @current_repos
          )
          Builtins.y2milestone("Added repositories: %1", @added)
          break
        end

        # Registration was called again
        if Wagon.repos_already_registered == true
          Builtins.y2milestone("Repos already registered")
          break
        end

        Builtins.y2warning("Repos were not changed: %1", @current_repos)

        # Never called before, nothing changed
        if Popup.AnyQuestion(
            # dialog caption
            _("Warning"),
            # pop-up question
            _(
              "No changes were made to the list of registered repositories.\n" +
                "This means that you either skipped the registration, there has been an \n" +
                "error in the configuration, or the repositories have been added before.\n" +
                "\n" +
                "Do you want to rerun the registration?\n"
            ),
            _("&Yes"),
            _("&No, Skip it"),
            :focus_yes
          ) == false
          Builtins.y2warning("User does not want to rerun the registration")
          break
        end
      end

      Wagon.RunHooks("after_registration") if @ret == :next

      @ret
    end

    def AdjustRegistrationHandlerScreen
      Wizard.SetContents(
        _("Novell Customer Center Configuration"),
        Label(_("Checking the current repositories...")),
        " ",
        GetInstArgs.enable_back,
        GetInstArgs.enable_next
      )

      nil
    end

    def GetCurrentlyEnabledReposByAlias
      ret = []
      repo_data = {}

      Wagon.InitPkg
      Builtins.foreach(
        Pkg.SourceGetCurrent(
          true # enabled only
        )
      ) do |repo_id|
        repo_data = Pkg.SourceGeneralData(repo_id)
        if repo_data == nil || repo_data == {}
          Builtins.y2error(
            "Erroneous repo ID: %1 - no repo data: %2",
            repo_id,
            repo_data
          )
          next
        end
        ret = Builtins.add(ret, Ops.get_string(repo_data, "alias", ""))
      end

      Builtins.sort(ret)
    end

    def AddedRepos(prev, curr)
      prev = deep_copy(prev)
      curr = deep_copy(curr)
      ret = []

      # added repos = all current which were not in the previous state
      ret = Builtins.filter(curr) do |curr_repo|
        !Builtins.contains(prev, curr_repo)
      end

      deep_copy(ret)
    end
  end
end

Yast::WagonRegistrationHandlerClient.new.main
