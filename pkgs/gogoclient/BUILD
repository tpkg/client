#!/bin/sh

set -e

PKG=gogoclient
VER=1.2
UNDERVER="1_2"
PKGVER=1
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
	rpm --quiet -q gcc-c++ openssl-devel || sudo yum install gcc-c++ openssl-devel
fi

#rm -rf $PKG-$VER
rm -rf gogoc-$UNDERVER-RELEASE
#tar zxvf $PKG-$VER.tar.gz
tar zxvf gogoc-$UNDERVER-RELEASE.tar.gz
#cd $PKG-$VER
cd gogoc-$UNDERVER-RELEASE
make all
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" | \
	sed '/<files>/a\
<file><path>/opt/tpkg/etc/init.d/gogoclient</path><init/></file>' \
	> $pkgdir/tpkg.xml
mkdir $pkgdir/root
# Install
make installdir=$pkgdir/root/opt/tpkg install
# Move the config file to etc
mkdir -p $pkgdir/root/opt/tpkg/etc
mv $pkgdir/root/opt/tpkg/bin/gogoc.conf* $pkgdir/root/opt/tpkg/etc
# Fix the config file
sed '/^gogoc_dir/s,=.*,=/opt/tpkg,' $pkgdir/root/opt/tpkg/etc/gogoc.conf > $pkgdir/root/opt/tpkg/etc/gogoc.conf.new
mv $pkgdir/root/opt/tpkg/etc/gogoc.conf.new $pkgdir/root/opt/tpkg/etc/gogoc.conf
sed '/^log_filename/s,=,=/opt/tpkg/var/log/,' $pkgdir/root/opt/tpkg/etc/gogoc.conf > $pkgdir/root/opt/tpkg/etc/gogoc.conf.new
mv $pkgdir/root/opt/tpkg/etc/gogoc.conf.new $pkgdir/root/opt/tpkg/etc/gogoc.conf
# The default configuration is to log to stderr.  Log to a file instead.
sed 's/^#\(log_console=\)/\10/' $pkgdir/root/opt/tpkg/etc/gogoc.conf > $pkgdir/root/opt/tpkg/etc/gogoc.conf.new
mv $pkgdir/root/opt/tpkg/etc/gogoc.conf.new $pkgdir/root/opt/tpkg/etc/gogoc.conf
sed 's/^#\(log_stderr=\)/\10/' $pkgdir/root/opt/tpkg/etc/gogoc.conf > $pkgdir/root/opt/tpkg/etc/gogoc.conf.new
mv $pkgdir/root/opt/tpkg/etc/gogoc.conf.new $pkgdir/root/opt/tpkg/etc/gogoc.conf
sed 's/^#\(log_file=\)/\11/' $pkgdir/root/opt/tpkg/etc/gogoc.conf > $pkgdir/root/opt/tpkg/etc/gogoc.conf.new
mv $pkgdir/root/opt/tpkg/etc/gogoc.conf.new $pkgdir/root/opt/tpkg/etc/gogoc.conf
sed 's/^#\(log_syslog=\)/\10/' $pkgdir/root/opt/tpkg/etc/gogoc.conf > $pkgdir/root/opt/tpkg/etc/gogoc.conf.new
mv $pkgdir/root/opt/tpkg/etc/gogoc.conf.new $pkgdir/root/opt/tpkg/etc/gogoc.conf
chmod 600 $pkgdir/root/opt/tpkg/etc/gogoc.conf*
# Make directories we referenced in the config file
mkdir -p $pkgdir/root/opt/tpkg/var/lib/gogoclient
mkdir -p $pkgdir/root/opt/tpkg/var/log
# Insert init script
mkdir -p $pkgdir/root/opt/tpkg/etc/init.d
cp ../$PKG.init $pkgdir/root/opt/tpkg/etc/init.d/$PKG
chmod 555 $pkgdir/root/opt/tpkg/etc/init.d/$PKG
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
#rm -rf $PKG-$VER
rm -rf gogoc-$UNDERVER-RELEASE

