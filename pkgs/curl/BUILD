#!/bin/sh

set -e

PKG=curl
VER=7.21.1
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

if echo $OS | egrep 'RedHat|CentOS'
then
	rpm --quiet -q openssl-devel || sudo yum install openssl-devel
fi

# This package doesn't work perfectly well as a relocatable package, as
# libcurl is compiled as a dynamic library and the curl executable linked to
# it.  If the package is relocated out of the standard dynamic linker search
# space the curl executable may not work.  That doesn't seem like a big enough
# issue to compel me to make the package non-relocatable, but it would be nice
# to improve that user experience somehow.

rm -rf $PKG-$VER
tar jxvf $PKG-$VER.tar.bz2
cd $PKG-$VER
./configure --prefix=/opt/tpkg
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" > $pkgdir/tpkg.xml
mkdir $pkgdir/reloc
# Install
make install prefix=$pkgdir/reloc
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

