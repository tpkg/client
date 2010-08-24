#!/sbin/sh

PKG=confuse
VER=2.6
PKGVER=1
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER || exit 1
tar zxvf $PKG-$VER.tar.gz || exit 1
cd $PKG-$VER || exit 1
./configure --prefix=/opt/tpkg CFLAGS=-fPIC --disable-nls || exit 1
make || exit 1
pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1

cat ../../tpkg.xml | \
        sed "s/NAME/$PKG/" | \
        sed "s/VERSION/$VER/" | \
        sed "s/PKGVER/$PKGVER/" | \
        sed "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" | \
        sed "s/ARCH/$ARCH/"  > $pkgdir/tpkg.xml

mkdir -p $pkgdir/root/opt/tpkg || exit 1
# Install
make install prefix=$pkgdir/root/opt/tpkg || exit 1

# Make package
tpkg --make $pkgdir || exit 1
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER
