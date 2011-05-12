#!/bin/sh

VER=0.0.8
PKGVER=1

for tpkg in gecode
do
	tpkg -q $tpkg || tpkg -i $tpkg
done

# The extra --with-opt-lib for the lib64 directory is needed to get the
# library built with an rpath for the location of the libstdc++ and
# libgcc_s libraries (since gecode requires a newer version of gcc and
# is thus built with the tpkg gcc)
gem2tpkg --gem /opt/tpkg/ruby-1.8/bin/gem dep_selector --version=$VER --package-version=$PKGVER --extra-deps=gecode,,, --build-options '--with-opt-dir=/opt/tpkg --with-opt-lib=/opt/tpkg/lib64'

