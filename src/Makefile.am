# Sources for wagon

module_DATA = \
  modules/Wagon.rb

client_DATA = \
  clients/wagon_update_proposal.rb \
  clients/wagon_registration_handler.rb \
  clients/welcome_in_wagon.rb \
  clients/wagon_dup_repositories.rb \
  clients/wagon_repositories_handler.rb \
  clients/wagon_selfupdate.rb \
  clients/wagon_registration_check.rb \
  clients/wagon_point_of_no_return.rb \
  clients/wagon_migration_products.rb \
  clients/wagon.rb \
  clients/wagon_congratulate.rb \
  clients/wagon_restart_yast.rb \
  clients/wagon_update_url.rb \
  clients/wagon_custom_url.rb \
  clients/wagon_modify_repositories.rb

yncludedir = @yncludedir@/wagon
ynclude_DATA = \
  include/wagon/common_func.rb \
  include/wagon/wagon_helpers.rb

desktop_DATA = \
  desktop/cd_update.desktop

EXTRA_DIST = $(module_DATA) $(client_DATA) $(ynclude_DATA) $(desktop_DATA)

include $(top_srcdir)/Makefile.am.common
