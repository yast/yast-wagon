# encoding: utf-8

# File:
#	clients/wagon_repositories_handler.ycp
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
  class WagonRepositoriesHandlerClient < Client
    def main
      # This is a handler scipt for YaST repositories.
      # See more in BNC #579905

      Yast.import "Wagon"
      Yast.import "Mode"
      Yast.import "GetInstArgs"
      Yast.import "Popup"

      textdomain "wagon"

      # YaST Repositories does not provide [Back][Next] buttons, only [OK][Cancel]
      # It's needed to skip it if going_back in the workflow
      if GetInstArgs.going_back
        Builtins.y2milestone(
          "'going back', skipping this dialog, going to the previous one"
        )
        return :auto
      end

      Wagon.RunHooks("before_repo_selection")

      @ret = :auto

      while true
        #	Mode::SetMode ("normal");
        Builtins.y2milestone("Running repositories...")
        @ret = Convert.to_symbol(WFM.call("repositories"))
        Builtins.y2milestone("Script repositories returned: %1", @ret)
        #	Mode::SetMode ("update");

        if @ret == :cancel || @ret == :abort
          if Popup.ConfirmAbort(:painless)
            @ret = :abort
            break
          end
          next
        else
          @ret = :next
          break
        end
      end

      # YaST Repositories stores all repos to disk, it's needed to reload them
      Wagon.InitPkg

      Wagon.RunHooks("after_repo_selection") if @ret == :next

      @ret
    end
  end
end

Yast::WagonRepositoriesHandlerClient.new.main
