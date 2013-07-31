# encoding: utf-8

# File:
#	clients/wagon_update_proposal.ycp
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
  class WagonUpdateProposalClient < Client
    def main
      textdomain "wagon"

      Yast.import "Wagon"
      Yast.import "Report"
      Yast.import "PackageInstallation"

      @func = Convert.to_string(WFM.Args(0))
      @param = Convert.to_map(WFM.Args(1))
      @ret = {}

      if @func == "MakeProposal"
        # Make sure the packager is initialized
        Wagon.InitPkg
        # BNC #585095: All repositories (enabled/disabled) repositories
        # logged with their state.
        Wagon.LogAllRepos

        @force_reset = Ops.get_boolean(@param, "force_reset", false)
        @language_changed = Ops.get_boolean(@param, "language_changed", false)

        Wagon.ResetDUPProposal if @force_reset

        Wagon.ProposeDUP
        Wagon.ProposeDownloadMode

        @ret = Wagon.ProposalSummary
      elsif @func == "AskUser"
        @chosen_id = Ops.get_string(@param, "chosen_id", "")

        # toggle the download mode status
        if @chosen_id == Wagon.GetDownloadModeLink
          PackageInstallation.SetDownloadInAdvance(
            !PackageInstallation.DownloadInAdvance
          )
        else
          Report.Message(_("There is nothing to set."))
        end

        @ret = { "workflow_sequence" => :next }
      elsif @func == "Description"
        @ret = {
          "rich_text_title" => _("Update Options"),
          "menu_title"      => _("&Update Options"),
          "id"              => "wagon_update_proposal"
        }
      end

      deep_copy(@ret)
    end
  end
end

Yast::WagonUpdateProposalClient.new.main
