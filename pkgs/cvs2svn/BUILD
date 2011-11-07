#!/sbin/sh

set -e

PKG=cvs2svn
VER=2.3.0
PKGVER=1

for tpkg in "python-defaults=2.7"
do
	tpkg --quiet -q $tpkg || tpkg -i $tpkg
done

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
#./configure --prefix=/opt/tpkg
#make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.yml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	grep -v "OS" | \
	grep -v "ARCH" \
	> $pkgdir/tpkg.yml
cat <<EOF >> $pkgdir/tpkg.yml
dependencies:
- name: python-defaults
  allowed_versions: 2.*
EOF
# Install
mkdir $pkgdir/root
make install DESTDIR=$pkgdir/root
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

