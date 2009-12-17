#!/bin/bash
set -e
set -u
set -o pipefail

PKG=memcached
VER=1.2.8
PKGVER=1
prefix=/home/t
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

for i in libevent-devel
do
	rpm --quiet -q $i || sudo yum install -y $i
done

rm -rf $PKG-$VER
tar zxf $PKG-$VER.tar.gz
cd $PKG-$VER

./configure --enable-threads
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
      <name>libevent</name>
      <native />
    </dependency>
  </dependencies>
</tpkg>
EOF

mkdir -p $pkgdir/reloc/bin
install -s -m 755 memcached $pkgdir/reloc/bin

# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER
