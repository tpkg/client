#!/bin/sh

PKG=monit
VER=5.0.3
PKGVER=2
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'
then
        # Save folks from having to build separate packages for Red Hat and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR,CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

if echo $OS | egrep 'RedHat|CentOS'
then
        rpm --quiet -q openssl-devel || yum -y install openssl-devel
fi

rm -rf $PKG-$VER || exit 1
tar zxvf $PKG-$VER.tar.gz || exit 1
cd $PKG-$VER || exit 1
# The directory where monit writes its pid file is not configurable
sed 's,/var/run,/opt/tpkg/var/run,' configure > configure.new || exit 1
chmod 755 configure.new
mv configure.new configure || exit 1
./configure --prefix=/opt/tpkg || exit 1
make || exit 1
pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" | \
	sed '/<files>/i\
<dependencies><dependency><name>logrotate</name></dependency></dependencies>' | \
	sed '/<files>/a\
<file><path>etc/init.d/monit</path><init/></file>' > $pkgdir/tpkg.xml
cp ../postinstall $pkgdir/postinstall || exit 1
chmod 755 $pkgdir/postinstall || exit 1
mkdir $pkgdir/reloc || exit 1
# PID file directory
mkdir -p $pkgdir/reloc/var/run || exit 1
# Log file directory
mkdir -p $pkgdir/reloc/var/log || exit 1
# State file directory
mkdir -p $pkgdir/reloc/var/lib/monit || exit 1
# Add init script
mkdir -p $pkgdir/reloc/etc/init.d || exit 1
cp ../$PKG.init $pkgdir/reloc/etc/init.d/$PKG || exit 1
chmod 755 $pkgdir/reloc/etc/init.d/$PKG || exit 1
# Logrotate
mkdir -p $pkgdir/reloc/etc/logrotate.d || exit 1
cp ../$PKG.logrotate $pkgdir/reloc/etc/logrotate.d/$PKG || exit 1
chmod 444 $pkgdir/reloc/etc/logrotate.d/$PKG || exit 1
# Config files
cp -p ../monitrc $pkgdir/reloc/etc/monitrc || exit 1
chmod 444 $pkgdir/reloc/etc/monitrc || exit 1
mkdir -p $pkgdir/reloc/etc/monit || exit 1
cp -p monitrc $pkgdir/reloc/etc/monit/sample || exit 1
chmod 444 $pkgdir/reloc/etc/monit/sample || exit 1
# Install
#make install DESTDIR=$pkgdir/reloc || exit 1
make install prefix=$pkgdir/reloc exec_prefix=$pkgdir/reloc || exit 1
# Make package
tpkg --make $pkgdir || exit 1
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

