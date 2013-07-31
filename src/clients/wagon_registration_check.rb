# encoding: utf-8

# File:
#	clients/wagon_registration_check.ycp
#
# Module:
#	Wagon
#
# Authors:
#	Ladislav Slezak <lslezak@suse.cz>
#
# Summary:
#	Online Migration Tool
#
#
module Yast
  class WagonRegistrationCheckClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"
      textdomain "wagon"

      Yast.import "GetInstArgs"
      Yast.import "Wagon"
      Yast.import "Wizard"
      Yast.import "Popup"

      Wagon.RunHooks("before_registration_check")

      # max age for the registration status (in days)
      @max_age_days = 90
      # max age for the registration status (in seconds)
      @max_age = Ops.multiply(
        Ops.multiply(Ops.multiply(@max_age_days, 24), 60),
        60
      )

      Wagon.InitPkg
      # read the registration XML file
      @reg_status = Wagon.RegistrationStatus

      Builtins.y2milestone("Read registration status: %1", @reg_status)

      # if no user interation needed then go on
      if !Interactive(@reg_status)
        if GetInstArgs.going_back
          Builtins.y2milestone("Going back...")
          return :back
        else
          Wagon.RunHooks("after_registration_check")
          return :next
        end
      end

      @ret = RegistrationSummaryDialog(@reg_status)

      Builtins.y2milestone("Result: %1", @ret)

      Wagon.RunHooks("after_registration_check") if @ret == :next

      @ret
    end

    # is the registration status file outdated?
    def OutdatedStatus(status)
      status = deep_copy(status)
      # missing data, we cannot tell if it's outdated, suppose not
      if !Builtins.haskey(status, "timestamp") ||
          Ops.less_or_equal(Ops.get_integer(status, "timestamp", 0), 0)
        return false
      end

      ret = Ops.less_than(
        Ops.add(Ops.get_integer(status, "timestamp", Builtins.time), @max_age),
        Builtins.time
      )
      Builtins.y2milestone("Registration status is outdated: %1", ret)

      ret
    end

    # get deatils about an installed product
    def InstalledProduct(name)
      products = Pkg.ResolvableProperties(name, :product, "")
      products = Builtins.filter(products) do |prod|
        Ops.get(prod, "status") == :installed
      end

      if Ops.greater_than(Builtins.size(products), 1)
        Builtins.y2warning(
          "Found %1 products: %2",
          Builtins.size(products),
          products
        )
      end

      Ops.get(products, 0, {})
    end

    # return list of installed but unregistered products
    def UnknownProducts(status)
      status = deep_copy(status)
      known_products = Convert.convert(
        Ops.add(
          Ops.add(
            Ops.add(
              Ops.add(
                Ops.add(
                  Ops.get_list(status, "registered", []),
                  Ops.get_list(status, "provisional", [])
                ),
                Ops.get_list(status, "rma", [])
              ),
              Ops.get_list(status, "expired", [])
            ),
            Ops.get_list(status, "no_subscription", [])
          ),
          Ops.get_list(status, "failed", [])
        ),
        :from => "list",
        :to   => "list <string>"
      )

      unknown_products = Pkg.ResolvableProperties("", :product, "")
      unknown_products = Builtins.filter(unknown_products) do |prod|
        Ops.get(prod, "status") == :installed &&
          !Builtins.contains(known_products, Ops.get_string(prod, "name", ""))
      end

      Builtins.y2milestone(
        "Found unregistered installed products: %1",
        unknown_products
      )

      deep_copy(unknown_products)
    end

    # convert registration status map into a rich text summary
    def RegistrationSummary(status)
      status = deep_copy(status)
      msg = "<h3>" + _("Registration Summary") + "</h3>"

      if !Ops.get_boolean(status, "registered_system", false)
        msg = Ops.add(
          Ops.add(Ops.add(msg, "<p>"), _("The system is not registered.")),
          "</p>"
        )
      else
        msg = Ops.add(msg, "<ul>")

        Builtins.foreach(Ops.get_list(status, "registered", [])) do |prod|
          msg = Ops.add(
            Ops.add(
              Ops.add(msg, "<li>"),
              Builtins.sformat(
                _("Product <b>%1</b> has a valid registration."),
                Ops.get_string(InstalledProduct(prod), "display_name", prod)
              )
            ),
            "</li>"
          )
        end 


        Builtins.foreach(Ops.get_list(status, "no_subscription", [])) do |prod|
          msg = Ops.add(
            Ops.add(
              Ops.add(msg, "<li>"),
              Builtins.sformat(
                _("Product <b>%1</b> does not need a subscription."),
                Ops.get_string(InstalledProduct(prod), "display_name", prod)
              )
            ),
            "</li>"
          )
        end 


        Builtins.foreach(UnknownProducts(status)) do |prod|
          msg = Ops.add(
            Ops.add(
              Ops.add(msg, "<li>"),
              Builtins.sformat(
                _("Registration status of product <b>%1</b> is unknown."),
                Ops.get_string(prod, "display_name", "")
              )
            ),
            "</li>"
          )
        end 


        Builtins.foreach(Ops.get_list(status, "failed", [])) do |prod|
          msg = Ops.add(
            Ops.add(
              Ops.add(msg, "<li><font color=\"red\">"),
              Builtins.sformat(
                _("Product <b>%1</b> is not registered, registration failed."),
                Ops.get_string(InstalledProduct(prod), "display_name", prod)
              )
            ),
            "</font></li>"
          )
        end 


        Builtins.foreach(Ops.get_list(status, "rma", [])) do |prod|
          msg = Ops.add(
            Ops.add(
              Ops.add(msg, "<li><font color=\"red\">"),
              Builtins.sformat(
                _(
                  "Registration for product <b>%1</b> has been refunded, the product is not registered."
                ),
                Ops.get_string(InstalledProduct(prod), "display_name", prod)
              )
            ),
            "</font></li>"
          )
        end 


        Builtins.foreach(Ops.get_list(status, "expired", [])) do |prod|
          msg = Ops.add(
            Ops.add(
              Ops.add(msg, "<li><font color=\"red\">"),
              Builtins.sformat(
                _(
                  "Registration for product <b>%1</b> has expired, the registration is not valid anymore."
                ),
                Ops.get_string(InstalledProduct(prod), "display_name", prod)
              )
            ),
            "</font></li>"
          )
        end 


        Builtins.foreach(Ops.get_list(status, "provisional", [])) do |prod|
          msg = Ops.add(
            Ops.add(
              Ops.add(msg, "<li><font color=\"red\">"),
              Builtins.sformat(
                _(
                  "Registration for product <b>%1</b> is provisional only, no updates available"
                ),
                Ops.get_string(InstalledProduct(prod), "display_name", prod)
              )
            ),
            "</font></li>"
          )
        end 


        msg = Ops.add(msg, "</ul>")
      end

      msg = Ops.add(msg, "<br>")

      if OutdatedStatus(status)
        days_outdated = Ops.divide(
          Ops.divide(
            Ops.divide(
              Ops.subtract(
                Builtins.time,
                Ops.get_integer(status, "timestamp", 0)
              ),
              60
            ),
            60
          ),
          24
        )
        msg = Ops.add(
          Ops.add(
            Ops.add(msg, "<p>"),
            Builtins.sformat(
              _(
                "The registration status is %1 days old. The summary above might not be correct, run registration to update the status."
              ),
              days_outdated
            )
          ),
          "</p>"
        )
      end

      # display a critical warning
      if Ops.greater_than(
          Builtins.size(Ops.get_list(status, "provisional", [])),
          0
        ) ||
          Ops.greater_than(Builtins.size(Ops.get_list(status, "rma", [])), 0) ||
          Ops.greater_than(
            Builtins.size(Ops.get_list(status, "expired", [])),
            0
          ) ||
          Ops.greater_than(Builtins.size(Ops.get_list(status, "failed", [])), 0) ||
          Ops.greater_than(Builtins.size(UnknownProducts(status)), 0) ||
          !Ops.get_boolean(status, "registered_system", false)
        msg = Ops.add(
          Ops.add(
            Ops.add(
              Ops.add(
                Ops.add(Ops.add(Ops.add(msg, "<p><b>"), _("Warning:")), " </b>"),
                _(
                  "We strongly recommend to register unregistered or expired products before starting migration."
                )
              ),
              "<br>"
            ),
            _(
              "Migrating an unregistered or partly registered system might result in a broken system."
            )
          ),
          "</p>"
        )
      end

      Builtins.y2milestone("Registration summary: %1", msg)

      msg
    end

    # set registration summary dialog content
    def SetContent(status)
      status = deep_copy(status)
      # heading text
      heading_text = _("Registration Check")

      contents = VBox(
        RichText(RegistrationSummary(status)),
        PushButton(Id(:registration), _("Run Registration..."))
      )

      # help text
      help_text = "<p>" +
        _("YaST checks whether the installed products are registered.") + "</p><p>" +
        _(
          "Migrating an unregistered or partly registered system might result in a broken system."
        ) + "</p>"

      Wizard.SetContents(
        heading_text,
        contents,
        help_text,
        GetInstArgs.enable_back,
        GetInstArgs.enable_next
      )

      Wizard.EnableAbortButton

      nil
    end

    # run registration summary dialog
    def RegistrationSummaryDialog(status)
      status = deep_copy(status)
      SetContent(status)

      ret = nil

      while true
        ret = Convert.to_symbol(UI.UserInput)

        if ret == :back || ret == :next
          break
        elsif (ret == :abort || ret == :cancel || ret == :close) &&
            Popup.ConfirmAbort(:painless)
          ret = :abort
          break
        elsif ret == :registration
          # start registration
          WFM.CallFunction("inst_suse_register")

          # refresh the registration status
          new_status = Wagon.RegistrationStatus
          SetContent(new_status)
        end
      end

      ret
    end

    # check whether the parsed registration status contains unregistered or
    # some other problem and user has to be informed about it
    def Interactive(status)
      status = deep_copy(status)
      # SMT doesn't write /var/lib/suseRegister/registration-status.xml file
      # so we cannot get any registration details, assume the system is fully registered
      if Ops.get(status, "ncc") == false
        Builtins.y2milestone(
          "SMT server is used, assuming fully registered system"
        )
        return false
      end

      # the system is not registered at all
      if Ops.get_boolean(status, "registered_system", false)
        Builtins.y2milestone(
          "Registration status is missing, interaction needed"
        )
        return true
      end

      # the registration status is too old
      if OutdatedStatus(status)
        Builtins.y2milestone(
          "Registration status is too old, interaction needed"
        )
        return true
      end

      # a product in unregistered state
      if Ops.greater_than(
          Builtins.size(Ops.get_list(status, "provisional", [])),
          0
        ) ||
          Ops.greater_than(Builtins.size(Ops.get_list(status, "rma", [])), 0) ||
          Ops.greater_than(
            Builtins.size(Ops.get_list(status, "expired", [])),
            0
          ) ||
          Ops.greater_than(Builtins.size(Ops.get_list(status, "failed", [])), 0)
        Builtins.y2milestone("Unregistered product found, interaction needed")
        return true
      end

      # an unknown product
      if Ops.greater_than(Builtins.size(UnknownProducts(status)), 0)
        Builtins.y2milestone("Unknown product found, interaction needed")
        return true
      end

      Builtins.y2milestone("Registration OK, skipping registration dialog")
      false
    end
  end
end

Yast::WagonRegistrationCheckClient.new.main
