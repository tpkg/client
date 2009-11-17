#!/sbin/sh

PKG=rrdtool
VER=1.3.8
PKGVER=2
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER || exit 1
tar zxvf $PKG-$VER.tar.gz || exit 1
cd $PKG-$VER || exit 1

for i in dejavu-lgc-fonts intltool cairo-devel libxml2-devel pango-devel pango libpng-devel freetype freetype-devel libart_lgpl-devel
do
echo $i
        rpm --quiet -q $i || sudo yum install -y $i.$ARCH || sudo yum install -y $i
done
export PKG_CONFIG_PATH=/usr/lib/pkgconfig/
./configure --prefix=/home/t  || exit 1
make || exit 1
pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1

cat ../../tpkg.xml | \
        sed "s/NAME/$PKG/" | \
        sed "s/VERSION/$VER/" | \
        sed "s/PKGVER/$PKGVER/" | \
        sed "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" | \
        sed "s/ARCH/$ARCH/"  > $pkgdir/tpkg.xml

mkdir -p $pkgdir/root/home/t || exit 1
# Install
make install prefix=$pkgdir/root/home/t || exit 1

# Make package
tpkg --make $pkgdir || exit 1
# Rename the package to reflect OS and arch
mv /tmp/$PKG-$VER-$PKGVER.tpkg /tmp/$PKG-$VER-$PKGVER-redhat$OSMAJOR-$ARCH.tpkg
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER
