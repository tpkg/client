#!/bin/bash

# Where to get the source?
#  MOG_DOMAIN=pkg.upstream mogwai get FreeImage3131.zip

PKG=freeimage
VER=3.13.1
PKGVER=1
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1

metadata=$(cat<<EOF
name: $PKG
version: $VER
package_version: $PKGVER
maintainer: system.architecture@yplist.flight.yellowpages.com
operatingsystem:
- RedHat-$OSMAJOR
- CentOS-$OSMAJOR
architecture: [$ARCH]
EOF
)

echo "$metadata" > $pkgdir/tpkg.yml
mkdir -p $pkgdir/root/opt/tpkg || exit 1

rm -rf FreeImage
unzip FreeImage3131.zip
cd FreeImage

make -j4 || exit 1
sudo make install DESTDIR=$pkgdir/root/opt/tpkg  INCDIR=$pkgdir/root/opt/tpkg/include INSTALLDIR=$pkgdir/root/opt/tpkg/lib || exit 1

# Make package
tpkg --make $pkgdir || exit 1
# Cleanup
sudo rm -rf $pkgdir
