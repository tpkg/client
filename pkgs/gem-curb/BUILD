#!/bin/sh

VER=0.7.1
PKGVER=1

rpm --quiet -q openssl openssl-devel || sudo yum -y install openssl openssl-devel
gem2tpkg curb --version=$VER --package-version=$PKGVER --native-deps=openssl

