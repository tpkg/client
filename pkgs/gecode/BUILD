#!/bin/sh

set -e

PKG=gecode
VER=3.5.0
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

# gecode requires gcc 4.2 or newer.  tpkg doesn't currently have a way
# to express that on the command line, so we specify the latest version.
for tpkg in gcc=4.6.0
do
	tpkg --quiet -q $tpkg || tpkg -i $tpkg
done

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
#LDFLAGS="-L/opt/tpkg/lib -Wl,-rpath=/opt/tpkg/lib"
#export LDFLAGS
#CFLAGS="-L/opt/tpkg/lib -Wl,-rpath=/opt/tpkg/lib"
#export CFLAGS
CXXFLAGS="-L/opt/tpkg/lib -L/opt/tpkg/lib64 -Wl,-rpath=/opt/tpkg/lib -Wl,-rpath=/opt/tpkg/lib64"
export CXXFLAGS
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
- name: libgcc
EOF
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

