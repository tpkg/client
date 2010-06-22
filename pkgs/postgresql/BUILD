#!/bin/sh

set -e

PKG=postgresql
VER=8.3.9
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
	rpm --quiet -q readline-devel || sudo yum install readline-devel
	rpm --quiet -q zlib-devel || sudo yum install zlib-devel
fi

rm -rf $PKG-$VER
tar jxvf $PKG-$VER.tar.bz2
cd $PKG-$VER
./configure \
	--prefix=/home/t \
	|| exit 1
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" | \
	sed '/<files>/i\
<externals><external><name>user</name><data>postgres</data></external><external><name>group</name><data>postgres</data></external></externals>' | \
	sed '/<files>/a\
<file><path>/home/t/etc/init.d/postgresql</path><init/></file>' \
	> $pkgdir/tpkg.xml
mkdir -p $pkgdir/root/home/t
# Add config file
#mkdir -p $pkgdir/root/home/t/etc
#cp ../my.cnf $pkgdir/root/home/t/etc/my.cnf
# Add init script
mkdir -p $pkgdir/root/home/t/etc/init.d
cp ../$PKG.init $pkgdir/root/home/t/etc/init.d/$PKG
chmod 755 $pkgdir/root/home/t/etc/init.d/$PKG
# Directory for log file
mkdir -p $pkgdir/root/home/t/var/log
# Install
make install DESTDIR=$pkgdir/root
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

