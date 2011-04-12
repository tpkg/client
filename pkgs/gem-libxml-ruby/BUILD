#!/bin/sh

VER=1.1.4
PKGVER=1

rpm --quiet -q libxml2 libxml2-devel || sudo yum -y install libxml2 libxml2-devel
gem2tpkg libxml-ruby --version=$VER --package-version=$PKGVER --native-deps=libxml2

