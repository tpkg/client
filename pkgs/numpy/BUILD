#!/sbin/sh

PKG=numpy
VER="1.3.0"
PKGVER=1
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`


rm -rf $PKG-$VER || exit 1
tar zxvf $PKG-$VER.tar.gz || exit 1
cd $PKG-$VER
pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1

cat ../../tpkg.xml | \
        sed "s/NAME/$PKG/" | \
        sed "s/VERSION/$VER/" | \
        sed "s/PKGVER/$PKGVER/" | \
        sed "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" | \
        sed "s/ARCH/$ARCH/" | \
        sed '/<files>/i\
<dependencies>\
<dependency><name>python</name><minimum_version>2.6.2</minimum_version><maximum_version>2.6.2</maximum_version></dependency></dependencies>' | \
        sed '/<files>/a\
<file_defaults><posix><owner>root</owner><group>root</group></posix></file_defaults>' > $pkgdir/tpkg.xml

# Install
mkdir $pkgdir/reloc
/home/t/bin/python2.6 setup.py install --prefix $pkgdir/reloc

# Make package
tpkg --make $pkgdir || exit 1

# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

