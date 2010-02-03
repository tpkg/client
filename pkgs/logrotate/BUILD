#!/sbin/sh

set -e

# Note, since it isn't completely obvious from Google the home of
# logrotate is https://fedorahosted.org/logrotate/

PKG=logrotate
VER=3.7.8
PKGVER=4
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'
then
        # Save folks from having to build separate packages for Red Hat and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR,CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
STATEFILE="/home/t/var/lib/logrotate.status" make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" | \
	sed '/<files>/i\
<dependencies><dependency><name>popt</name><native/></dependency></dependencies>' | \
	sed '/<files>/a\
<file><path>etc/cron.d/logrotate</path><crontab/></file>' > $pkgdir/tpkg.xml
cp ../postinstall $pkgdir/postinstall
chmod 755 $pkgdir/postinstall
mkdir -p $pkgdir/reloc
# Add config file
mkdir -p $pkgdir/reloc/etc
cp ../logrotate.conf $pkgdir/reloc/etc/logrotate.conf
# Add cronjob
mkdir -p $pkgdir/reloc/etc/cron.d
cp ../logrotate.cron $pkgdir/reloc/etc/cron.d/logrotate
# Add directory for the log file used in the cronjob
mkdir -p $pkgdir/reloc/var/log
# Add directory for the state file
mkdir -p $pkgdir/reloc/var/lib
# Install
make install PREFIX=$pkgdir/reloc BASEDIR=
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

