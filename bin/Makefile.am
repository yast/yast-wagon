#
# Makefile.am for wagon/src/clients
#

sbin_SCRIPTS = wagon

client_DATA = $(wildcard *.ycp)

YCPCFLAGS = -M ../modules

EXTRA_DIST = $(sbin_SCRIPTS) $(client_DATA)

include $(top_srcdir)/Makefile.am.common
