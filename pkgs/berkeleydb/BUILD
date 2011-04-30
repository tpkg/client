#!/bin/bash

# Where to get berkeley db?
# http://www.oracle.com/technology/software/products/berkeley-db/index.html

PKG=db
OUR_PKG_NAME=berkeleydb
VER=5.0.21
PKGVER=1

prefix=/opt/tpkg/$OUR_PKG_NAME

OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1
metadata=$(cat<<EOF
name: $OUR_PKG_NAME
version: $VER
package_version: $PKGVER
maintainer: tpkg-users@lists.sourceforge.net
operatingsystem: [RedHat-$OSMAJOR, CentOS-$OSMAJOR]
architecture: [$ARCH]
EOF
)

echo "$metadata" > $pkgdir/tpkg.yml

pushd .
tar zxf $PKG-$VER.tar.gz
cd $PKG-$VER/build_unix
../dist/configure --enable-sql  --prefix=$prefix
make prefix=$prefix
make install DESTDIR=$pkgdir/root prefix=$prefix

# Make package
tpkg --make $pkgdir || exit 1

popd

# Cleanup
rm -rf $pkgdir
rm -rf $PKG-$VER

