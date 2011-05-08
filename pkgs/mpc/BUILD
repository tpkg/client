#!/bin/sh

set -e

PKG=mpc
VER=0.9
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

for tpkg in gmp mpfr
do
	tpkg --quiet -q $tpkg || tpkg -i $tpkg
done

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
./configure \
	--prefix=/opt/tpkg \
	--mandir=/opt/tpkg/man \
	--with-gmp=/opt/tpkg \
	--with-mpfr=/opt/tpkg
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.yml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" > $pkgdir/tpkg.yml
cat <<EOF >> $pkgdir/tpkg.yml
dependencies:
- name: gmp
- name: mpfr
EOF
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
rm $pkgdir/root/opt/tpkg/share/info/dir
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

