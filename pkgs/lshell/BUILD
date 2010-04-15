#!/bin/sh

set -e

PKG=lshell
VER=0.9.10
PKGVER=1

tpkg -q python=2.6.2 || tpkg -i python=2.6.2

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	grep -v 'OS' | \
	grep -v 'ARCH' | \
	sed '/<files>/i\
<dependencies><dependency><name>python</name><minimum_version>2.6</minimum_version><maximum_version>2.6.9999</maximum_version></dependency><dependency><name>logrotate</name></dependency></dependencies>' | \
	sed '/<files>/a\
<file><path>/home/t/var/log/lshell</path><posix><perms>1733</perms></posix></file>' \
	> $pkgdir/tpkg.xml
mkdir $pkgdir/root
# Install
/home/t/bin/python2.6 setup.py install --no-compile --prefix=/home/t --root=$pkgdir/root
# Fix up some shortcomings in the install process
mv $pkgdir/root/etc $pkgdir/root/home/t
sed '/^logpath/s,/var,/home/t/var,' $pkgdir/root/home/t/etc/lshell.conf > $pkgdir/root/home/t/etc/lshell.conf.new
mv $pkgdir/root/home/t/etc/lshell.conf.new $pkgdir/root/home/t/etc/lshell.conf
sed 's,^/var,/home/t/var,' $pkgdir/root/home/t/etc/logrotate.d/lshell > $pkgdir/root/home/t/etc/logrotate.d/lshell.new
mv $pkgdir/root/home/t/etc/logrotate.d/lshell.new $pkgdir/root/home/t/etc/logrotate.d/lshell
# Make log directory
mkdir -p $pkgdir/root/home/t/var/log/lshell
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

