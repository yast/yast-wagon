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
  class WagonCustomUrlClient < Client
    def main
      Yast.import "Pkg"
      textdomain "wagon"

      Yast.import "GetInstArgs"
      Yast.import "Wagon"
      Yast.import "Sequencer"

      Yast.include self, "packager/repositories_include.rb"

      if GetInstArgs.going_back
        Builtins.y2milestone("Going back...")
        return :back
      end

      Wagon.RunHooks("before_custom_url")

      Wagon.InitPkg
      Pkg.SourceReleaseAll

      @aliases = {
        # Included from inst_source_dialogs.ycp
        "type"  => lambda do
          TypeDialog()
        end,
        "edit"  => lambda { EditDialog() },
        "store" => lambda { StoreSource() }
      }

      @sources_before = Pkg.SourceGetCurrent(false)
      Builtins.y2milestone("Sources before adding new one: %1", @sources_before)

      @sequence = {
        "ws_start" => "type",
        "type"     => {
          :next   => "edit",
          # bnc #392083
          :finish => "store",
          :abort  => :abort
        },
        "edit"     => {
          :next   => "store",
          # bnc #392083
          :finish => "store",
          :abort  => :abort
        },
        "store"    => {
          :next   => :next,
          # bnc #392083
          :finish => :next,
          :abort  => :abort
        }
      }

      Builtins.y2milestone("Starting repository sequence")
      @ret = Sequencer.Run(@aliases, @sequence)

      Builtins.y2milestone("Ret: %1", @ret)

      Wagon.RunHooks("after_custom_url") if @ret == :next

      @ret
    end
  end
end

Yast::WagonCustomUrlClient.new.main
