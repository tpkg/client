#!/bin/sh

set -e

PKG=rubygems
VER=1.3.7
PKGVER=1

tpkg -q ruby-defaults || tpkg -i ruby-defaults

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tgz
cd $PKG-$VER
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	grep -v "OS" | \
	grep -v "ARCH" > $pkgdir/tpkg.xml
mkdir $pkgdir/root
# Install
/home/t/bin/ruby setup.rb --destdir=$pkgdir/root
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

