#!/bin/bash
# a parallel implementation of gzip from the author of zlib, this uses a
# modern, faster version of zlib than the one gzip bundles, so it's
# noticeably faster than gzip (v1.3.12) even on a single core
# http://zlib.net/pigz/

set -e
set -u
set -o pipefail

PKG=pigz
VER=2.1.5
PKGVER=1
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER
tar zxf $PKG-$VER.tar.gz
cd $PKG-$VER

for i in zlib-devel
do
	rpm --quiet -q $i || sudo yum install -y $i
done

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
      <name>zlib</name>
      <native />
      <minimum_version>1.2.3</minimum_version>
    </dependency>
  </dependencies>
</tpkg>
EOF

mkdir -p $pkgdir/reloc/bin
install pigz $pkgdir/reloc/bin

# Make package
tpkg --make $pkgdir
# Rename the package to reflect OS and arch
mv /tmp/$PKG-$VER-$PKGVER.tpkg \
	/tmp/$PKG-$VER-$PKGVER-redhat$OSMAJOR-$ARCH.tpkg
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER
