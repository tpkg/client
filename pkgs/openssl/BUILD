#!/bin/sh

set -e

PKG="openssl"
VER="1.0.0g"
PKGVER="1"
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'; then
        # Save folks from having to build separate packages for Red Hat and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR, CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

# INSTALL file says perl is needed
for tpkg in perl; do
	tpkg --quiet -q $tpkg || tpkg -i $tpkg
done
#if echo $OS | egrep 'RedHat|CentOS'; then
#	for rpm in ; do
#		rpm --quiet -q $rpm || sudo yum install $rpm
#	done
#fi

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
#./configure --prefix=/opt/tpkg --mandir=/opt/tpkg/man
./config --prefix=/opt/tpkg --openssldir=/opt/tpkg/share/openssl shared
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
make install INSTALL_PREFIX=$pkgdir/root
rm -f $pkgdir/root/opt/tpkg/share/info/dir
mv $pkgdir/root/opt/tpkg/share/openssl/man $pkgdir/root/opt/tpkg
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

