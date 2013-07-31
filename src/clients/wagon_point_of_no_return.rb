# encoding: utf-8

# File:
#	clients/wagon_custom_url.ycp
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
  class WagonPointOfNoReturnClient < Client
    def main
      textdomain "wagon"

      Yast.import "GetInstArgs"
      Yast.import "Wagon"

      if GetInstArgs.going_back
        Builtins.y2milestone("Going back...")
        return :back
      end

      # Point of no return. After this call, YaST will start removing
      # and installing packages. In other words, the real migration
      # will start.

      Builtins.y2warning(
        "From this point, wagon cannot revert products anymore!"
      )
      Wagon.abort_can_revert_products = false

      # @see BNC 575102
      Builtins.y2milestone("Resetting repos_already_registered flag")
      Wagon.repos_already_registered = false

      Wagon.RunHooks("before_package_migration")

      :auto
    end
  end
end

Yast::WagonPointOfNoReturnClient.new.main
