#!/bin/sh

set -e

PKG=apache-ant
VER=1.8.2
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
#tar jxvf $PKG-$VER.tar.bz2
tar jxvf $PKG-$VER-bin.tar.bz2
cd $PKG-$VER
#./configure --prefix=/opt/tpkg
#make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	grep -v OS | \
	grep -v ARCH |
	sed '/<files>/i\
<dependencies><dependency><name>jdk</name></dependency></dependencies>' \
	> $pkgdir/tpkg.xml
mkdir $pkgdir/root
# Install
#make install prefix=$pkgdir/reloc
mkdir -p $pkgdir/root/opt/tpkg/share/$PKG-$VER
find . | cpio -pdum $pkgdir/root/opt/tpkg/share/$PKG-$VER
mkdir -p $pkgdir/root/opt/tpkg/etc/profile.d
cat ../apache-ant.sh | sed "s/PKG/$PKG/" | sed "s/VER/$VER/" \
	> $pkgdir/root/opt/tpkg/etc/profile.d/apache-ant.sh
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

