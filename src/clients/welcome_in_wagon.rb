# encoding: utf-8

# File:
#	clients/welcome_in_wagon.ycp
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
  class WelcomeInWagonClient < Client
    def main
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "GetInstArgs"
      Yast.import "Popup"
      Yast.import "Wagon"
      Yast.import "Report"
      Yast.import "FileUtils"

      textdomain "wagon"

      Wagon.RunHooks("before_welcome")

      # heading text
      @heading_text = _("Welcome")

      @contents = VBox(
        Label(
          _(
            "This tool will help to update the\n" +
              "running system to a service pack.\n" +
              "\n" +
              "Click 'Next' to start the update."
          )
        )
      )

      # help text
      @help_text = _(
        "<p>This tool updates the running system to a service pack.</p>"
      )

      Wizard.SetContents(
        @heading_text,
        @contents,
        @help_text,
        GetInstArgs.enable_back,
        GetInstArgs.enable_next
      )
      Wizard.EnableAbortButton

      # file /etc/sysconfig/rhn/systemid means the system is managed by SUSE Manager
      if FileUtils.Exists("/etc/sysconfig/rhn/systemid")
        Builtins.y2milestone(
          "File /etc/sysconfig/rhn/systemid found, aborting wagon"
        )

        # warning message, system managed by SUSE Manager cannot be migrated by wagon
        # display this message and exit
        Popup.Message(
          _(
            "This system is managed by SUSE Manager,\n" +
              "YaST wagon module cannot migrate systems managed by SUSE Manager.\n" +
              "\n" +
              "Press OK to exit."
          )
        )

        return :back
      end

      @ret = nil

      while true
        @ret = UI.UserInput

        if @ret == :back
          break
        elsif (@ret == :abort || @ret == :cancel) &&
            Popup.ConfirmAbort(:painless)
          @ret = :abort
          break
        elsif @ret == :next
          if Wagon.InitPkg != true
            # Report error but let user go further
            # Might help us in the future
            Report.Error(_("Cannot initialize software manager."))
          end
          break
        else
          Builtins.y2error("Unknown ret: %1", @ret)
        end
      end

      # Clear the dialog
      Wizard.SetContents("", Empty(), "", true, true)

      Wagon.RunHooks("after_welcome") if @ret == :next

      deep_copy(@ret)
    end
  end
end

Yast::WelcomeInWagonClient.new.main
