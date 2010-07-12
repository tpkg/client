#!/bin/sh

set -e

PKG=xmlrpc-c
VER=1.06.38
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

tpkg --quiet -q curl || tpkg -i curl

# Make sure configure finds the tpkg curl-config instead of others
PATH=/home/t/bin:$PATH
export PATH

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tgz
cd $PKG-$VER
./configure --prefix=/home/t
# CADD setting per doc/INSTALL
make CADD=-fPIC
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" | \
        sed '/<files>/i\
<dependencies><dependency><name>curl</name></dependency></dependencies>' \
	> $pkgdir/tpkg.xml
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

