Name: tpkg
Summary: tpkg client
Version: VER
Release: 1
Group: Applications/System
License: MIT
buildarch: noarch
Requires: ruby, facter, redhat-lsb, crontabs
BuildRoot: %{_builddir}/%{name}-buildroot
%description
tpkg client

%files
%defattr(-,root,root)
/usr/bin/tpkg
/usr/bin/gem2tpkg
/usr/lib/ruby/site_ruby/1.8/tpkg
/usr/lib/ruby/site_ruby/1.8/tpkg.rb
/etc/profile.d/tpkg_profile.sh
/etc/cron.d/tpkg
%config /etc/tpkg.conf

