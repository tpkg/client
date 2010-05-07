#!/sbin/sh

PKG=randomizer
VER=1.0

pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1
cat ../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	grep -v PKGVER | \
	grep -v OS | \
	grep -v ARCH | \
	sed '/<files>/i\
<dependencies><dependency><name>ruby</name><native/></dependency></dependencies>' | \
	grep -v files > $pkgdir/tpkg.xml
mkdir -p $pkgdir/reloc/bin || exit 1
cp randomizer $pkgdir/reloc/bin || exit 1
# Make package
tpkg --make $pkgdir || exit 1
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

