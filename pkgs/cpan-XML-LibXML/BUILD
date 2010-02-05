#!/bin/sh

VER=1.70
PKGVER=1

rpm --quiet -q libxml2 libxml2-devel || sudo yum -y install libxml2 libxml2-devel
cpan2tpkg XML::LibXML --version=$VER --package-version=$PKGVER \
	--native-deps=libxml2

