#!/bin/sh

PKG=scons
VER=1.2.0
PKGVER=1
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER || exit 1
tar zxvf $PKG-$VER.tar.gz || exit 1
cd $PKG-$VER || exit 1
pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1
# FIXME: python dep
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	grep -v operatingsystem | grep -v architecture | \
	sed '/<files>/i\
<dependencies><dependency><name>python</name><minimum_version>1.5.2</minimum_version></dependency></dependencies>' \
	> $pkgdir/tpkg.xml
mkdir -p $pkgdir/root/home/t || exit 1
# Install
python setup.py install --prefix=$pkgdir/root/home/t || exit 1
# Make package
tpkg --make $pkgdir || exit 1
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

