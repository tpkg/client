#!/bin/bash
set -e
set -u
set -o pipefail

PKG=google-perftools
VER=1.4
PKGVER=1
prefix=/home/t
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER
tar zxf $PKG-$VER.tar.gz
cd $PKG-$VER

./configure --prefix=$prefix --enable-minimal
make -j4
# existing LD_PRELOADs can cause problems
unset LD_PRELOAD
make -j4 check
pkgdir=`mktemp -d -t tpkg.XXXXXX`
sed -e "s/NAME/$PKG/" \
	-e "s/VERSION/$VER/" \
	-e "s/PKGVER/$PKGVER/" \
	-e "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" \
	-e "s/ARCH/$ARCH/" < ../../tpkg.xml > $pkgdir/tpkg.xml

mkdir -p $pkgdir/root$prefix
make install DESTDIR=$pkgdir/root

# Make package
tpkg --make $pkgdir || exit 1
# Rename the package to reflect OS and arch
mv /tmp/$PKG-$VER-$PKGVER.tpkg \
	/tmp/$PKG-$VER-$PKGVER-redhat$OSMAJOR-$ARCH.tpkg
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER
