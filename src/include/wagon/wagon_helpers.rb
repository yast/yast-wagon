# encoding: utf-8

#
# Copyright (c) 2011 Novell, Inc.
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail,
# you may find current contact information at www.novell.com
#
# File:
#	include/wagon/wagon_helpers.rb
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
  module WagonWagonHelpersInclude
    # * Read registration status and sort products according their status
    # * @param file Read this registration status file
    # * @return map<string,any> result: $[
    # *
    # 	    "registered_system" : (boolean) - true registration was run, false registration has never run or there is no product to register (e.g. openSUSE installation) or the registration completely failed
    # 	    "timestamp"		: (integer) - time when the status was saved (unix time), -1 in an unregistered system
    # 	    "registered"	: (list<string>) - registered products
    # 	    "provisional"	: (list<string>) - products with provisional subscription (registered, but no updates available)
    # 	    "rma"		: (list<string>) - refunded subscriptions, not active anymore
    # 	    "expired"		: (list<string>) - expired subscriptions
    # 	    "no_subscription"	: (list<string>) - products which do not need a subscription (e.g. SLES-SDK)
    # 	    "failed"		: (list<string>) - registration failed (e.g. invalid registration code)
    # * ]
    def RegistrationStatusFromFile(file)
      registered_system = true
      timestamp = -1

      failed = []
      no_subscription = []
      expired = []
      rma = []
      provisional = []
      registered = []

      # 0 = empty file, -1 = missing
      if Ops.less_or_equal(FileUtils.GetSize(file), 0)
        Builtins.y2milestone("File %1 does not exist", file)
        registered_system = false
      else
        # read the registration status
        # see https://wiki.innerweb.novell.com/index.php/Registration#Add_Registration_Status_to_zmdconfig
        # for more datils about the file format
        status = RegistrationStatus.ReadFile(file)

        timestamp = Builtins.tointeger(
          Ops.get_string(status, "generated", "-1")
        )

        read_products = Ops.get(status, "productstatus")
        products = Ops.is_map?(read_products) ?
          [Convert.to_map(read_products)] :
          Convert.convert(read_products, :from => "any", :to => "list <map>")

        # check each product
        Builtins.foreach(products) do |product|
          product_name = Ops.get_string(product, "product", "")
          # not registered (error present, but not "expired")
          if Ops.get_string(product, "result", "") == "error" &&
              Ops.get_string(product, "errorcode", "") != "ERR_SUB_EXP"
            failed = Builtins.add(failed, product_name)
          else
            # registered, but subscription is not needed (e.g. SLES-SDK)
            if Ops.get_map(product, "subscription", {}) == {}
              no_subscription = Builtins.add(no_subscription, product_name)
            else
              status2 = Ops.get_string(product, ["subscription", "status"], "")
              expiration = Ops.get_string(
                product,
                ["subscription", "expiration"],
                ""
              )

              # expired subscription (status == EXPIRED or the timestamp is in the past)
              if status2 == "EXPIRED" ||
                  expiration != "" &&
                    Ops.less_than(Builtins.tointeger(expiration), Builtins.time)
                expired = Builtins.add(expired, product_name)
              elsif status2 == "RMA"
                rma = Builtins.add(rma, product_name)
              else
                type = Ops.get_string(product, ["subscription", "type"], "")

                # provisional subscription
                if type == "PROVISIONAL"
                  provisional = Builtins.add(provisional, product_name)
                else
                  registered = Builtins.add(registered, product_name)
                end
              end
            end
          end
        end
      end

      {
        "registered_system" => registered_system,
        "timestamp"         => timestamp,
        "registered"        => registered,
        "provisional"       => provisional,
        "rma"               => rma,
        "expired"           => expired,
        "no_subscription"   => no_subscription,
        "failed"            => failed
      }
    end

  end
end
