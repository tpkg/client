#!/bin/bash
set -e
set -u
set -o pipefail

PKG=google-perftools
VER=1.5
PKGVER=1
prefix=/opt/tpkg
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'
then
        # Save folks from having to build separate packages for Red Hat
        # and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR,CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

rm -rf $PKG-$VER
tar zxf $PKG-$VER.tar.gz

(
	cd $PKG-$VER
	unset LD_PRELOAD

	./configure --prefix=$prefix --enable-minimal
	make -j4
	# existing LD_PRELOADs can cause problems
	make -j4 check
)

pkgdir=`mktemp -d -t tpkg.XXXXXX`
sed -e "s/NAME/$PKG/" \
	-e "s/VERSION/$VER/" \
	-e "s/PKGVER/$PKGVER/" \
	-e "s/OS/$OS/" \
	-e "s/ARCH/$ARCH/" < ../tpkg.xml > $pkgdir/tpkg.xml

mkdir -p $pkgdir/root$prefix

make -C $PKG-$VER install DESTDIR=$pkgdir/root

# Make package
tpkg --make $pkgdir || exit 1
# Cleanup
rm -rf $pkgdir
rm -rf $PKG-$VER
