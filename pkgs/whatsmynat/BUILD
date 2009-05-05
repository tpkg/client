#!/sbin/sh

PKG=whatsmynat
VER=1.0

pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1
cat ../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	grep -v PKGVER | \
	grep -v OS | \
	grep -v ARCH | \
	sed '/<files>/i\
<dependencies><dependency><name>wget</name><native/></dependency></dependencies>' | \
	grep -v files > $pkgdir/tpkg.xml
mkdir -p $pkgdir/reloc/bin || exit 1
cp whatsmynat $pkgdir/reloc/bin || exit 1
# Fix perms
sudo chown -R 0:0 $pkgdir/reloc || exit 1
# Make package
sudo tpkg --make $pkgdir || exit 1
# Cleanup
sudo rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

