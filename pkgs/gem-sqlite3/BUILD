#!/bin/sh

VER=1.3.3
PKGVER=1

tpkg -q sqlite || tpkg -i sqlite
gem2tpkg sqlite3 --version=$VER --package-version=$PKGVER --extra-deps=sqlite --build-options '--with-sqlite3-dir=/opt/tpkg --with-dldflags="-Wl,-rpath,/opt/tpkg/lib"'

