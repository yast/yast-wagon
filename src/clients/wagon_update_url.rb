# encoding: utf-8

# File:
#	clients/wagon_update_url
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
  class WagonUpdateUrlClient < Client
    def main
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "GetInstArgs"
      Yast.import "Popup"
      Yast.import "Icon"
      Yast.import "Wagon"

      textdomain "wagon"

      Wagon.RunHooks("before_selecting_migration_source")

      @frame_label = _("Select from Where to Get the Update URL")
      @frame_width = Ops.multiply(
        UI.TextMode ? Ops.multiply(2, Builtins.size(@frame_label)) : 2.2,
        Builtins.size(@frame_label)
      )

      @current_workflow = Wagon.GetUpdateWorkflow

      # Default workflow
      if @current_workflow != "manual_suse_register" &&
          @current_workflow != "manual_custom_url"
        @current_workflow = "manual_suse_register"
        Builtins.y2milestone("Default workflow is: %1", @current_workflow)
      end

      @contents = HSquash(
        MinWidth(
          @frame_width,
          Frame(
            @frame_label,
            MarginBox(
              1,
              1,
              RadioButtonGroup(
                Id(:update_url),
                VBox(
                  HBox(
                    HBox(Image(Icon.IconPath("yast-update"), ""), HSpacing(2)),
                    VBox(
                      Left(
                        RadioButton(
                          Id(:suse_register),
                          _("&Customer Center"),
                          @current_workflow == "manual_suse_register"
                        )
                      ),
                      HBox(
                        HSpacing(2),
                        Left(
                          CheckBox(
                            Id(:manual_check),
                            _("Check Automatic &Repository Changes"),
                            Wagon.check_repositories_manually
                          )
                        )
                      )
                    ),
                    HStretch()
                  ),
                  VSpacing(1),
                  HBox(
                    HBox(
                      Image(Icon.IconPath("yast-cd_update"), ""),
                      HSpacing(2)
                    ),
                    RadioButton(
                      Id(:custom_url),
                      _("Custom &URL"),
                      @current_workflow == "manual_custom_url"
                    ),
                    HStretch()
                  )
                )
              )
            )
          )
        )
      )

      @heading_text = _("Update Method")

      # help text 1
      @help_text = _(
        "<p>Choose whether to use the <b>Customer Center</b>\n" +
          "to handle the installation repositories during migration or use \n" +
          "<b>Custom &URL</b> to set them manually.</p>\n"
      ) +
        # help text 2
        _(
          "<p>Select <b>Check Automatic Repository Changes</b> to ensure\n" +
            "that Customer Center has modified the repositories correctly. \n" +
            "You can also modify them there.</p>\n"
        )

      Wizard.SetContents(
        @heading_text,
        @contents,
        @help_text,
        GetInstArgs.enable_back,
        GetInstArgs.enable_next
      )
      Wizard.EnableAbortButton

      @ui_ret = nil
      @ret = nil

      while true
        @ui_ret = UI.UserInput

        if @ui_ret == :back
          @ret = :back
          break
        elsif @ui_ret == :next
          @selected = UI.QueryWidget(Id(:update_url), :CurrentButton)
          Builtins.y2milestone("Selected workflow: %1", @selected)

          if @selected == :suse_register
            Wagon.check_repositories_manually = Convert.to_boolean(
              UI.QueryWidget(Id(:manual_check), :Value)
            ) == true
            Builtins.y2milestone(
              "Checking repos manually: %1",
              Wagon.check_repositories_manually
            )
            Wagon.SetMigrationMethod("suse_register")
          elsif @selected == :custom_url
            # custom URL uses the same dialog in a different context
            Wagon.check_repositories_manually = false
            Builtins.y2milestone(
              "Checking repos manually: %1",
              Wagon.check_repositories_manually
            )
            Wagon.SetMigrationMethod("custom")
          end

          Wagon.AdjustVariableSteps
          # Check whether we have a useful workflow
          if Wagon.SetWizardSteps
            Wagon.AdjustVariableSteps
            Wagon.RedrawWizardSteps
            @ret = :next
            break
          end
        elsif @ui_ret == :abort
          if Popup.ConfirmAbort(:painless)
            @ret = :abort
            break
          end
        end
      end

      Wagon.RunHooks("after_selecting_migration_source") if @ret == :next

      @ret
    end
  end
end

Yast::WagonUpdateUrlClient.new.main
