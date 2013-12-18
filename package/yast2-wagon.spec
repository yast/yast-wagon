#
# spec file for package yast2-wagon
#
# Copyright (c) 2013 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:           yast2-wagon
Version:        3.1.1
Release:        0

BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Source0:        %{name}-%{version}.tar.bz2

Group:	        System/YaST
License:        GPL-2.0+
# PackagesUI::RunPackageSelector yast2 >= 2.17.40
# RegistrationStatus: yast2 >= 2.23.13
Requires:	yast2 >= 2.23.13
Requires:	yast2-online-update-frontend >= 2.17.9
# Pkg::AddUpgradeRepo()
Requires:	yast2-pkg-bindings >= 2.21.2

# Called in proposal and in code
Requires:	yast2-packager >= 2.21.2
Requires:	yast2-add-on

# Counting packages directly in packages proposal (BNC #573482)
Requires:	yast2-update >= 2.18.7

BuildRequires:	perl-XML-Writer update-desktop-files yast2-devtools yast2-testsuite yast2-update
BuildRequires:	yast2 >= 2.23.13

# xmllint
BuildRequires:	libxml2-tools

# control.rng
BuildRequires:	yast2-installation-control

Provides:	yast2-online-update-frontend:%{_datadir}/applications/YaST2/cd_update.desktop

# See BNC #613820, Comment #22
Conflicts:	yast2-perl-bindings < 2.19.0
Conflicts:	yast2-storage < 2.19.0

# Requires a control file
Requires:	wagon-control-file

BuildArchitectures:	noarch

Requires:       yast2-ruby-bindings >= 1.0.0

Summary: YaST2 - Migration Tool for Service Packs

%description
Wagon is a convenience tool to guide the user through the migration. It
does not contain any extra functionality beyond what's available
through command line tools.

%prep
%setup -n %{name}-%{version}

%build
%yast_build
mkdir -p "$RPM_BUILD_ROOT"/var/lib/YaST2/wagon/hooks/

%install
%yast_install

xmllint --noout --relaxng %{yast_controldir}/control.rng %{buildroot}%{yast_controldir}/*.xml
# ghost file
touch %{buildroot}%{yast_controldir}/online_migration.xml


%files
%defattr(-,root,root)
%{_prefix}/sbin/wagon
%{yast_clientdir}/*.rb
%{yast_moduledir}/*.rb
%dir %{yast_yncludedir}/wagon
%{yast_yncludedir}/wagon/*.rb
%{yast_desktopdir}/*.desktop
%doc %{yast_docdir}
%dir /var/lib/YaST2/wagon/
%dir /var/lib/YaST2/wagon/hooks/
%exclude %{yast_controldir}
%exclude %{yast_controldir}/*.xml

#
# yast2-wagon-control-SLE
#

%package control-SLE

# Generic 'provides'
Provides: wagon-control-file

Group:	System/YaST
License: GPL-2.0+

# Prevent from crashes (BNC #551613)
Requires:	yast2-registration >= 2.18.0

Conflicts:	otherproviders(wagon-control-file)
Supplements: packageand(yast2-wagon:branding-SLE)

Summary: YaST Wagon control file for SLE

%description control-SLE
YaST Wagon control file for SLE

%post control-SLE
ln -sf online_migration-SLE.xml %{yast_controldir}/online_migration.xml

%files control-SLE
%defattr(-,root,root)
%dir %{yast_controldir}
%{yast_controldir}/online_migration-SLE.xml
%ghost %{yast_controldir}/online_migration.xml
