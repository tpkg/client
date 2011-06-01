#!/bin/sh

set -e

PKG=expect
VER=5.45
TCLVER=8.5.9
PKGVER=1
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'
then
        # Save folks from having to build separate packages for Red Hat and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR, CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

# expect requires tcl 8.2 or newer.  tpkg doesn't currently have a way
# to express that on the command line, so we specify the latest version.
for tpkg in tcl=$TCLVER
do
	tpkg --quiet -q $tpkg || tpkg -i $tpkg
done

rm -rf $PKG$VER
tar zxvf $PKG$VER.tar.gz
(cd ../tcl && rm -rf tcl$TCLVER)
(cd ../tcl && tar zxvf tcl$TCLVER-src.tar.gz)
cd $PKG$VER
./configure --prefix=/opt/tpkg
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.yml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" > $pkgdir/tpkg.yml
cat <<EOF >> $pkgdir/tpkg.yml
dependencies:
- name: tcl
  minimum_version: 8.2
EOF
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG$VER
(cd ../tcl && rm -rf tcl$TCLVER)

