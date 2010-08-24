#!/bin/bash
# TODO when we package postgres in tpkg, add support for pgsql linkage, too
set -e
set -u
set -o pipefail

PKG=sphinx
VER=0.9.8.1
PKGVER=1
prefix=/opt/tpkg
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER
tar zxf $PKG-$VER.tar.gz
cd $PKG-$VER

export LDFLAGS=-Wl,-rpath=$prefix/lib/mysql
./configure --prefix=$prefix
make -j4
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat > $pkgdir/tpkg.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE tpkg SYSTEM "http://tpkg.sourceforge.net/tpkg-1.0.dtd">
<tpkg>
  <name>$PKG</name>
  <version>$VER</version>
  <package_version>$PKGVER</package_version>
  <maintainer>tpkg-users@lists.sourceforge.net</maintainer>
  <operatingsystem>RedHat-$OSMAJOR,CentOS-$OSMAJOR</operatingsystem>
  <architecture>$ARCH</architecture>
  <dependencies>
    <dependency>
      <name>mysql</name>
      <minimum_version>5.1.33</minimum_version>
    </dependency>
  </dependencies>
</tpkg>
EOF

mkdir -p $pkgdir/root$prefix
make install DESTDIR=$pkgdir/root

# Make package
tpkg --make $pkgdir || exit 1
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER
