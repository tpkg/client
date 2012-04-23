#!/bin/sh

set -e

PKG=ncurses
VER=5.9
PKGVER=1
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'; then
        # Save folks from having to build separate packages for Red Hat and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR, CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

#for tpkg in ; do
#	tpkg --quiet -q $tpkg || tpkg -i $tpkg
#done
#if echo $OS | egrep 'RedHat|CentOS'; then
#	for rpm in ; do
#		rpm --quiet -q $rpm || sudo yum install $rpm
#	done
#fi

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
#./configure --prefix=/opt/tpkg --mandir=/opt/tpkg/man
./configure --prefix=/opt/tpkg --mandir=/opt/tpkg/man --with-shared
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

