#!/bin/sh
set -e
set -u

PKG=ragel
VER=6.4
PKGVER=1
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

for i in flex bison-devel gperf
do
	pkg=$i-devel
	rpm --quiet -q $pkg || sudo yum install $pkg
done

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz

cd $PKG-$VER
o="--prefix=/"
o="$o --disable-rpath"
./configure $o
make -j8

pkgdir=`mktemp -d -t tpkg.XXXXXX`
sed -e "s/NAME/$PKG/" \
	-e "s/VERSION/$VER/" \
	-e "s/PKGVER/$PKGVER/" \
	-e "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" \
	-e "s/ARCH/$ARCH/" \
	-e "/file/d" \
	-e "/path/d" \
	-e "/init/d" \
	< ../../tpkg.xml > $pkgdir/tpkg.xml

# Install
make install DESTDIR=$pkgdir/reloc
# Fix perms
sudo chown -R 0:0 $pkgdir/reloc
# Make package
sudo tpkg --make $pkgdir
# Rename the package to reflect OS and arch
sudo mv /tmp/$PKG-$VER-$PKGVER.tpkg \
  /tmp/$PKG-$VER-$PKGVER-redhat$OSMAJOR-$ARCH.tpkg
# Cleanup
sudo rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER
