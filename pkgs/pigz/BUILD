#!/bin/bash
# a parallel implementation of gzip from the author of zlib, this uses a
# modern, faster version of zlib than the one gzip bundles, so it's
# noticeably faster than gzip (v1.3.12) even on a single core
# http://zlib.net/pigz/

set -e
set -u
set -o pipefail

PKG=pigz
VER=2.1.6
PKGVER=1
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'
then
        # Save folks from having to build separate packages for Red Hat and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR,CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

rm -rf $PKG-$VER
tar zxf $PKG-$VER.tar.gz
cd $PKG-$VER

if echo $OS | egrep 'RedHat|CentOS'
then
        for i in zlib-devel
        do
        	rpm --quiet -q $i || sudo yum install -y $i
        done
	zlibdep="<dependency><name>zlib</name><native/><minimum_version>1.2.3</minimum_version></dependency>"
fi
if echo $OS | egrep 'Debian|Ubuntu'
then
        for i in zlib1g-dev
        do
        	dpkg -l $i || sudo apt-get -y install $i
        done
	zlibdep="<dependency><name>zlib1g</name><native/><minimum_version>1.2.3</minimum_version></dependency>"
fi

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
  <operatingsystem>$OS</operatingsystem>
  <architecture>$ARCH</architecture>
  <dependencies>
    $zlibdep
  </dependencies>
</tpkg>
EOF

mkdir -p $pkgdir/reloc/bin
install pigz $pkgdir/reloc/bin

# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER
