#
# Makefile.am for wagon/src/config
#

controldir = $(yast2dir)/control

control_DATA = $(wildcard *.xml)

EXTRA_DIST = $(control_DATA)

check-local:
	xmllint --relaxng $(controldir)/control.rng --noout $(control_DATA)
