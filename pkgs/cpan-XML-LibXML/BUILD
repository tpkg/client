#!/bin/sh

VER=1.70
PKGVER=1

rpm --quiet -q libxml2 libxml2-devel || sudo yum -y install libxml2 libxml2-devel
/opt/tpkg/perl-5.10/bin/perl /usr/bin/cpan2tpkg XML::LibXML --package-version=$PKGVER --native-deps=libxml2

