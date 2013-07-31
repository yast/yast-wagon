# encoding: utf-8

# File:
#	clients/wagon_congratulate.ycp
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
  class WagonCongratulateClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      Yast.import "ProductControl"
      Yast.import "Wizard"
      Yast.import "Popup"
      Yast.import "GetInstArgs"
      Yast.import "Label"
      Yast.import "Wagon"

      textdomain "wagon"

      Wagon.RunHooks("before_congratulate")

      @ret = :auto

      @display = UI.GetDisplayInfo
      @space = Ops.get_boolean(@display, "TextMode", true) ? 1 : 3

      @caption = _("Migration Completed")

      @text = ProductControl.GetTranslatedText("migration_congratulate")

      if @text == nil || @text == ""
        Builtins.y2warning("Using fallback migration_congratulate text")
        # translators: %1 is a URL, e.g. http://www.suse.com
        @text = Builtins.sformat(
          _(
            "<p><b>Congratulations!</b><br>\n" +
              "You have successfully finished the on-line migration.</p>\n" +
              "<p>The whole system has been upgraded. It should be rebooted\n" +
              "as soon as possible.</p>\n" +
              "<p>Please visit us at %1.</p>\n" +
              "<p>Have a nice day!<br>\n" +
              "Your SUSE Linux Team</p>\n"
          ),
          "http://www.suse.com"
        )
      end

      @contents = VBox(
        VSpacing(@space),
        HBox(
          HSpacing(Ops.multiply(2, @space)),
          VBox(RichText(Id(:text), @text)),
          HSpacing(Ops.multiply(2, @space))
        ),
        VSpacing(@space),
        VSpacing(2)
      )

      @help = _(
        "<p><b>Finish</b> will close the migration.\nRestart the system as soon as possible.</p>\n"
      )

      Wizard.SetContents(
        @caption,
        @contents,
        @help,
        GetInstArgs.enable_back,
        GetInstArgs.enable_next
      )
      Wizard.SetTitleIcon("yast-license")

      Wizard.SetNextButton(:next, Label.FinishButton)
      Wizard.RestoreAbortButton
      Wizard.SetFocusToNextButton
      begin
        @ret = Convert.to_symbol(Wizard.UserInput)

        break if Popup.ConfirmAbort(:incomplete) if @ret == :abort
      end until @ret == :next || @ret == :back

      if @ret == :back
        Wizard.RestoreNextButton
      elsif @ret == :next
        Wizard.SetContents(
          @caption,
          Label(_("Finishing the migration...")),
          @help,
          GetInstArgs.enable_back,
          GetInstArgs.enable_next
        )

        Pkg.SourceSaveAll
        Pkg.TargetFinish

        Wagon.RunHooks("after_congratulate")
      end

      @ret
    end
  end
end

Yast::WagonCongratulateClient.new.main
