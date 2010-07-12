#!/bin/sh

VER=2.36
PKGVER=1

rpm --quiet -q expat expat-devel || sudo yum -y install expat expat-devel
cpan2tpkg XML::Parser --version=$VER --package-version=$PKGVER \
	--native-deps=expat

