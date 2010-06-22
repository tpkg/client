#!/bin/sh

VER=1.2.5
PKGVER=1

tpkg -q sqlite || tpkg -i sqlite
gem2tpkg sqlite3-ruby --version=$VER --package-version=$PKGVER --extra-deps=sqli
te --build-options '--with-sqlite3-dir=/home/t --with-dldflags="-Wl,-rpath,/home/t/lib"'

