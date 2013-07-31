# encoding: utf-8

# File:
#	clients/wagon_dup_repositories.ycp
#
# Module:
#	Wagon
#
# Authors:
#	Ladislav Slezak <lslezak@suse.cz>
#
# Summary:
#	Display dialog for selecting distribution upgrade repositories.
#
#
module Yast
  class WagonDupRepositoriesClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"
      textdomain "wagon"

      Yast.import "Wagon"
      Yast.import "GetInstArgs"
      Yast.import "Wizard"
      Yast.import "Popup"

      Yast.include self, "wagon/common_func.rb"

      Wagon.RunHooks("before_set_migration_repo")

      # for custom migration repo we cannot select full/core migration type,
      # and also when there is no new registration repo we cannot detect full/core migrations
      # => go directly to the repository selection (advanced option)
      @ret = Wagon.GetMigrationMethod == "suse_register" &&
        Ops.greater_than(Builtins.size(Wagon.RegistrationRepos), 0) ?
        MinimalMigration() :
        DupSelectionDialog()

      Builtins.y2milestone("Result: %1", @ret)

      Wagon.RunHooks("after_set_migration_repo") if @ret == :next

      @ret
    end

    def TableContent
      # current enabled repositories
      repos = Pkg.SourceGetCurrent(true)
      dup_repos = Wagon.DupRepos
      ret = []

      Builtins.y2internal("Current repositories: %1", repos)
      Builtins.y2internal("DUP repositories: %1", dup_repos)

      Builtins.foreach(repos) do |repo|
        info = Pkg.SourceGeneralData(repo)
        # if nothing selected yet propose all repositories
        selected = dup_repos == [] || Builtins.contains(dup_repos, repo) ?
          UI.Glyph(:CheckMark) :
          ""
        ret = Builtins.add(
          ret,
          Item(
            Id(repo),
            selected,
            Ops.get_string(info, "name", ""),
            Ops.get_string(info, "url", "")
          )
        )
      end

      Builtins.y2internal("Table content: %1", ret)

      deep_copy(ret)
    end

    # display the repository selection dialog
    def SetContent
      # heading text
      heading_text = _("Migration Repositories")

      contents = VBox(
        Left(
          Label(
            _(
              "The packages will be switched to versions in the selected repositories."
            )
          )
        ),
        Table(
          Id(:table),
          Opt(:notify, :immediate, :keepSorting),
          Header(Center(_("Selected")), _("Name"), _("URL")),
          TableContent()
        ),
        HBox(
          PushButton(Id(:select), _("Select")),
          PushButton(Id(:deselect), _("Deselect"))
        )
      )

      # help text
      help_text = "<p>" +
        _("Here select the repositories which will be used for migration.") + "</p><p>" +
        _(
          "The installed packages will be switched to the versions available in the selected migration repositories."
        ) + "</p>"

      Wizard.SetContents(
        heading_text,
        contents,
        help_text,
        GetInstArgs.enable_back,
        GetInstArgs.enable_next
      )

      nil
    end

    # run the repository selection dialog
    def DupSelectionDialog
      SetContent()

      ret = nil

      while true
        event = UI.WaitForEvent
        ret = Ops.get_symbol(event, "ID", :nothing)

        if ret == :table &&
            Ops.get_string(event, "EventReason", "") == "Activated"
          ret = :toggle
        end

        if ret == :back
          break
        elsif ret == :next
          Builtins.y2milestone(
            "Table content: %1",
            UI.QueryWidget(Id(:table), :Items)
          )

          table_lines = Convert.convert(
            UI.QueryWidget(Id(:table), :Items),
            :from => "any",
            :to   => "list <term>"
          )
          selected = []

          Builtins.foreach(table_lines) do |table_line|
            if Ops.get_string(table_line, 1, "") != ""
              selected = Builtins.add(
                selected,
                Ops.get_integer(table_line, [0, 0], -1)
              )
            end
          end

          if Builtins.size(selected) == 0
            # error message, no migration repository selected in the table
            Popup.Error("Select at least one migration repository.")
            next
          end

          Builtins.y2milestone(
            "Selected repositories for distribution upgrade: %1",
            selected
          )

          Wagon.SetDupRepos(selected)

          break
        elsif (ret == :abort || ret == :cancel || ret == :close) &&
            Popup.ConfirmAbort(:painless)
          ret = :abort
          break
        elsif ret == :select || ret == :deselect || ret == :toggle
          current = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))
          selected = ""

          if ret == :toggle
            # toggle the flag
            current_value = Convert.to_string(
              UI.QueryWidget(Id(:table), Cell(current, 0))
            )
            selected = current_value == "" ? UI.Glyph(:CheckMark) : ""
          else
            selected = ret == :select ? UI.Glyph(:CheckMark) : ""
          end

          UI.ChangeWidget(Id(:table), Cell(current, 0), selected)
        else
          Builtins.y2error("Unknown user input: %1", ret)
        end
      end

      ret
    end


    def MinimalMigration
      prev_dup_repos = Wagon.DupRepos
      prev_migration_type = Wagon.MigrationType

      Builtins.y2milestone(
        "Using minimal migration, using these repositories: %1",
        Wagon.RegistrationRepos
      )

      alias_to_id = {}
      Builtins.foreach(Pkg.SourceGetCurrent(true)) do |repo|
        Ops.set(
          alias_to_id,
          Ops.get_string(Pkg.SourceGeneralData(repo), "alias", ""),
          repo
        )
      end 


      added_repos = Builtins.maplist(Wagon.RegistrationRepos) do |_alias|
        Ops.get(alias_to_id, _alias, -1)
      end

      Builtins.y2milestone("Converted aliases to ids: %1", added_repos)

      Wagon.SetDupRepos(added_repos)
      Wagon.SetManualRepoSelection(false)
      Wagon.SetMigrationType(:minimal)

      if prev_dup_repos != Wagon.DupRepos ||
          prev_migration_type != Wagon.MigrationType
        Builtins.y2milestone(
          "DUP repository config has been changed, repropose package selection"
        )
        Wagon.ResetDUPProposal

        # reset current package selection
        ResetPackager()
      end

      :next
    end
  end
end

Yast::WagonDupRepositoriesClient.new.main
