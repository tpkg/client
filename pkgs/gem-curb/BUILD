#!/bin/sh

VER=0.7.1
PKGVER=2

rpm --quiet -q openssl openssl-devel || sudo yum -y install openssl openssl-devel
tpkg --quiet -q curl || tpkg -i curl
gem2tpkg curb --version=$VER --package-version=$PKGVER --extra-deps=curl --native-deps=openssl

