#!/sbin/sh

PKG=pylot
VER=1.24
PKGVER=1
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG\_$VER || exit 1

unzip $PKG\_$VER.zip || exit 1
pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1

cat ../tpkg.xml | \
        sed "s/NAME/$PKG/" | \
        sed "s/VERSION/$VER/" | \
        sed "s/PKGVER/$PKGVER/" | \
        sed "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" | \
        sed "s/ARCH/$ARCH/" | \
        sed '/<files>/i\
<dependencies>\
<dependency><name>numpy</name><minimum_version>1.3.0</minimum_version></dependency>\
<dependency><name>matplotlib</name><minimum_version>0.98.5.3</minimum_version></dependency>\
<dependency><name>python</name><minimum_version>2.6.2</minimum_version><maximum_version>2.6.2</maximum_version></dependency></dependencies>' | \
        sed '/<files>/a\
<file_defaults><posix><owner>root</owner><group>root</group></posix></file_defaults>' > $pkgdir/tpkg.xml

# Install
mkdir $pkgdir/reloc
cp -r $PKG\_$VER $pkgdir/reloc

# Make package
tpkg --make $pkgdir || exit 1

# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG\_$VER

