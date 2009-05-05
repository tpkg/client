#!/bin/sh

# Etch uses 0.9.8
#VER=0.9.8
# 1.1.3 is the latest (as of 24-April-2009)
VER=1.1.3
PKGVER=1

rpm --quiet -q libxml2 libxml2-devel || sudo yum -y install libxml2 libxml2-devel
sudo gem2tpkg libxml-ruby --version=$VER --package-version=$PKGVER --native-deps=libxml2

