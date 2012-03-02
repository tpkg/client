#!/bin/sh

set -e

PKG="krb5"
VER="1.10"
PKGVER="1"
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'
then
        # Save folks from having to build separate packages for Red Hat and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR, CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

if echo $OS | egrep 'RedHat|CentOS'
then
	for rpm in openssl-devel readline-devel bison
	do
		rpm --quiet -q $rpm || sudo yum install $rpm
	done
fi

for tpkg in tcl
do
	tpkg --quiet -q $tpkg || tpkg -i $tpkg
done

rm -rf $PKG-$VER
tar xf $PKG-$VER-signed.tar
gpg --verify $PKG-$VER.tar.gz.asc
tar zxf $PKG-$VER.tar.gz
#cd $PKG-$VER
cd $PKG-$VER/src
./configure --prefix=/opt/tpkg --mandir=/opt/tpkg/man \
	--with-tcl=/opt/tpkg --with-readline
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../../tpkg.yml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" > $pkgdir/tpkg.yml
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
#cd ..
cd ../..
rm -rf $PKG-$VER $PKG-$VER.tar.gz $PKG-$VER.tar.gz.asc

