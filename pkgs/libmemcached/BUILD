#!/bin/bash
set -e
set -u
set -o pipefail

PKG=libmemcached

# gem-memcached currently depends on this upstream version.  Note that
# the libmemcached authors have a horrible track record when it comes
# to compatibility between releases.
VER=0.25.14

PKGVER=1
prefix=/opt/tpkg
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER
tar zxf $PKG-$VER.tar.gz
cd $PKG-$VER

# avoid build-dependency on memcached
./configure --prefix=$prefix --with-memcached=/bin/true
make -j4
pkgdir=`mktemp -d -t tpkg.XXXXXX`
sed -e "s/NAME/$PKG/" \
	-e "s/VERSION/$VER/" \
	-e "s/PKGVER/$PKGVER/" \
	-e "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" \
	-e "s/ARCH/$ARCH/" < ../../tpkg.xml > $pkgdir/tpkg.xml

mkdir -p $pkgdir/root$prefix
make install DESTDIR=$pkgdir/root

# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER
