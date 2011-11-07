#!/bin/sh

set -e

PKG=libxml2
VER=2.7.8
PKGVER=1
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'
then
        # Save folks from having to build separate packages for Red Hat and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR, CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

for tpkg in python-defaults=2.7
do
	tpkg --quiet -q $tpkg || tpkg -i $tpkg
done

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
# The build process sets rpath based on where it finds python, but does
# not set -L.  Odd.
LDFLAGS="-L/opt/tpkg/lib" ./configure --prefix=/opt/tpkg --mandir=/opt/tpkg/man
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.yml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" > $pkgdir/tpkg.yml
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
rm -f $pkgdir/root/opt/tpkg/share/info/dir
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

