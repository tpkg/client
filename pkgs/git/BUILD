#!/sbin/sh

set -e

PKG=git
VER=1.6.4.1
PKGVER=2
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER
#tar zxvf $PKG-$VER.tar.gz
tar jxvf $PKG-$VER.tar.bz2
cd $PKG-$VER
rpm --quiet -q zlib-devel || sudo yum install zlib-devel
rpm --quiet -q openssl-devel || sudo yum install openssl-devel
rpm --quiet -q curl-devel || sudo yum install curl-devel
rpm --quiet -q expat-devel || sudo yum install expat-devel
# Build
make prefix=/home/t
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" | \
	sed "s/ARCH/$ARCH/" > $pkgdir/tpkg.xml
mkdir -p $pkgdir/root/home/t
# Install
make DESTDIR=$pkgdir/root prefix=/home/t install
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

