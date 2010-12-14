#!/bin/sh

set -e

PKG=collectd
VER=4.9.4
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
	for rpm in rrdtool-devel libdbi-devel
	do
		rpm --quiet -q $rpm || sudo yum install $rpm
	done
fi

rm -rf $PKG-$VER
tar jxvf $PKG-$VER.tar.bz2
cd $PKG-$VER
./configure --prefix=/opt/tpkg --datarootdir=/opt/tpkg
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" |
	sed '/<files>/a\
<file><path>/opt/tpkg/etc/init.d/collectd</path><posix><perms>0755</perms></posix><init/></file>' > $pkgdir/tpkg.xml
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
# Init script
mkdir -p $pkgdir/root/opt/tpkg/etc/init.d
cp ../collectd.init $pkgdir/root/opt/tpkg/etc/init.d/collectd
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

