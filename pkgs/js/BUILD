#!/bin/sh

# Package for Mozilla Spider Monkey:  http://www.mozilla.org/js/spidermonkey/

PKG=js
VER=1.7.0
PKGVER=1
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER || exit 1
tar zxvf $PKG-$VER.tar.gz || exit 1
mv $PKG $PKG-$VER || exit 1
cd $PKG-$VER/src || exit 1
# Per http://www.mongodb.org/display/DOCS/Building+Spider+Monkey
CFLAGS="-DJS_C_STRINGS_ARE_UTF8" make -f Makefile.ref
pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1
cat ../../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" | \
	sed "s/ARCH/$ARCH/" \
	> $pkgdir/tpkg.xml
mkdir -p $pkgdir/root/home/t || exit 1
# Install
JS_DIST=$pkgdir/root/home/t make -f Makefile.ref export
# Make package
tpkg --make $pkgdir || exit 1
# Cleanup
rm -rf $pkgdir
cd ../..
rm -rf $PKG-$VER

