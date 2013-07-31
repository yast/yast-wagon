# encoding: utf-8

# File:
#	clients/wagon_restart_yast.ycp
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
  class WagonRestartYastClient < Client
    def main
      textdomain "wagon"

      Yast.import "GetInstArgs"
      Yast.import "Wagon"

      if GetInstArgs.going_back
        Builtins.y2milestone("Going back...")
        return :back
      end

      Builtins.y2milestone("YaST will be restarted")
      :restart_same_step
    end
  end
end

Yast::WagonRestartYastClient.new.main
