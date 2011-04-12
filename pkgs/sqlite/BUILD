#!/bin/sh

set -e

PKG=sqlite
VER=3.7.5
TARVER=3070500
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
#tar zxvf $PKG-$VER.tar.gz
tar zxvf $PKG-autoconf-$TARVER.tar.gz
#cd $PKG-$VER
cd $PKG-autoconf-$TARVER
./configure --prefix=/opt/tpkg
#./configure --prefix=/opt/tpkg --mandir=/opt/tpkg/man
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" > $pkgdir/tpkg.xml
mkdir -p $pkgdir/root/opt/tpkg
# Install
make install prefix=$pkgdir/root/opt/tpkg
mkdir $pkgdir/root/opt/tpkg/man
mv $pkgdir/root/opt/tpkg/share/man $pkgdir/root/opt/tpkg/man
rmdir $pkgdir/root/opt/tpkg/share
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
#rm -rf $PKG-$VER
rm -rf $PKG-autoconf-$TARVER

