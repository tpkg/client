#!/bin/sh

VER=1.2.5
PKGVER=1

rpm --quiet -q sqlite || sudo yum -y install sqlite
gem2tpkg sqlite3-ruby --version=$VER --package-version=$PKGVER --native-deps=sqlite

