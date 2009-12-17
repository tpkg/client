#!/sbin/sh

# Note, since it isn't completely obvious from Google the home of
# logrotate is https://fedorahosted.org/logrotate/

PKG=logrotate
VER=3.7.8
PKGVER=3
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER || exit 1
tar zxvf $PKG-$VER.tar.gz || exit 1
cd $PKG-$VER || exit 1
make || exit 1
pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" | \
	sed "s/ARCH/$ARCH/" | \
	sed '/<files>/i\
<dependencies><dependency><name>popt</name><native/></dependency></dependencies>' | \
	sed '/<files>/a\
<file><path>etc/cron.d/logrotate</path><crontab/></file>' > $pkgdir/tpkg.xml
cp ../postinstall $pkgdir/postinstall || exit 1
chmod 755 $pkgdir/postinstall || exit 1
mkdir -p $pkgdir/reloc || exit 1
# Add config file
mkdir -p $pkgdir/reloc/etc || exit 1
cp ../logrotate.conf $pkgdir/reloc/etc/logrotate.conf || exit 1
# Add cronjob
mkdir -p $pkgdir/reloc/etc/cron.d || exit 1
cp ../logrotate.cron $pkgdir/reloc/etc/cron.d/logrotate || exit 1
# Add directory for the log file used in the cronjob
mkdir -p $pkgdir/reloc/var/log || exit 1
# Install
make install PREFIX=$pkgdir/reloc BASEDIR= || exit 1
# Make package
tpkg --make $pkgdir || exit 1
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

