#!/bin/bash
set -e
set -u
set -o pipefail

PKG=tokyotyrant
VER=1.1.33
PKGVER=1
prefix=/opt/tpkg
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER
tar zxf $PKG-$VER.tar.gz
cd $PKG-$VER

for i in zlib-devel bzip2-devel
do
	rpm --quiet -q $i || sudo yum install -y $i
done

tpkg -q tokyocabinet || tpkg -i tokyocabinet

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
      <name>tokyocabinet</name>
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
