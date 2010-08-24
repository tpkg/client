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
<file><path>/opt/tpkg/var/log/lshell</path><posix><perms>1733</perms></posix></file>' \
	> $pkgdir/tpkg.xml
mkdir $pkgdir/root
# Install
/opt/tpkg/bin/python2.6 setup.py install --no-compile --prefix=/opt/tpkg --root=$pkgdir/root
# Fix up some shortcomings in the install process
mv $pkgdir/root/etc $pkgdir/root/opt/tpkg
sed '/^logpath/s,/var,/opt/tpkg/var,' $pkgdir/root/opt/tpkg/etc/lshell.conf > $pkgdir/root/opt/tpkg/etc/lshell.conf.new
mv $pkgdir/root/opt/tpkg/etc/lshell.conf.new $pkgdir/root/opt/tpkg/etc/lshell.conf
sed 's,^/var,/opt/tpkg/var,' $pkgdir/root/opt/tpkg/etc/logrotate.d/lshell > $pkgdir/root/opt/tpkg/etc/logrotate.d/lshell.new
mv $pkgdir/root/opt/tpkg/etc/logrotate.d/lshell.new $pkgdir/root/opt/tpkg/etc/logrotate.d/lshell
# Make log directory
mkdir -p $pkgdir/root/opt/tpkg/var/log/lshell
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

