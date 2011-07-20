#
# Makefile.am for wagon/src/modules
#

module_DATA = Wagon.ycp RegistrationStatus.pm

EXTRA_DIST = $(module_DATA)

YCPCFLAGS = -I .

ycpchook = wagon

wagon:
	ln -s ../include wagon


include $(top_srcdir)/Makefile.am.common
