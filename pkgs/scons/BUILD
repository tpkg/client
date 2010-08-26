#!/bin/sh

set -e

PKG=scons
VER=2.0.1
PKGVER=1

tpkg -q python || tpkg -i python
# Ensure the proper python is found
PATH=/opt/tpkg/bin:$PATH
export PATH

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	grep -v operatingsystem | grep -v architecture | \
	sed '/<files>/i\
<dependencies><dependency><name>python-defaults</name><minimum_version>2.4</minimum_version><maximum_version>2.6</maximum_version></dependency></dependencies>' \
	> $pkgdir/tpkg.xml
mkdir -p $pkgdir/root/opt/tpkg
# Install
python setup.py install --prefix=$pkgdir/root/opt/tpkg
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

