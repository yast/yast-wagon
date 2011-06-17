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

package RegistrationStatus;

use strict;
use Data::Dumper;
use XML::Simple;

use YaST::YCP qw(:DATA :LOGGING);

our %TYPEINFO;

my $reg_file = "/var/lib/suseRegister/registration-status.xml";

BEGIN{ $TYPEINFO{Read} = ["function", ["map","any","any"]]; }
sub Read {
    my ($self) = @_;
    return ReadFile($reg_file);
}

BEGIN{ $TYPEINFO{ReadFile} = ["function", ["map","any","any"], "string"]; }
sub ReadFile {
    my $self = shift;
    my $file = shift;

    # create XML parser
    my $parser = new XML::Simple;

    # parse the file
    my $data = $parser->XMLin($file);

    my $dump = Dumper($data);
    y2milestone("Parsed file $file: $dump");

    return $data;
}

1

