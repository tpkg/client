#!/bin/sh

set -e

PKG=wmr100
GITVER=511ecd6
# In case the project ever matures enough to have numbered releases try
# to ensure our packages have a low enough version that the hypothetical
# numbered releases will be considered an upgrade by tpkg.
VER="0.0.$GITVER"
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

if echo $OS | egrep 'RedHat|CentOS'
then
	for rpm in pkgconfig
	do
		rpm --quiet -q $rpm || sudo yum install $rpm
	done
fi
for tpkg in libhid
do
	tpkg --quiet -q libhid || tpkg -i libhid
done

#rm -rf $PKG-$VER
#tar jxvf $PKG-$VER.tar.bz2
#cd $PKG-$VER
rm -rf barnybug-$PKG-$GITVER
tar zxvf barnybug-$PKG-$GITVER.tar.gz
cd barnybug-$PKG-$GITVER
#./configure --prefix=/opt/tpkg
PKG_CONFIG_PATH=/opt/tpkg/lib/pkgconfig
export PKG_CONFIG_PATH
LDFLAGS="-Wl,-rpath=/opt/tpkg/lib" make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.yml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" > $pkgdir/tpkg.yml
cat <<EOF >> $pkgdir/tpkg.yml
dependencies:
- name: libhid
EOF
mkdir $pkgdir/root
# Install
#make install DESTDIR=$pkgdir/root
mkdir -p $pkgdir/root/opt/tpkg/bin
cp -p wmr100 $pkgdir/root/opt/tpkg/bin
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
#rm -rf $PKG-$VER
rm -rf barnybug-$PKG-$GITVER

