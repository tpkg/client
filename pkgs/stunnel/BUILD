#!/sbin/sh

PKG=stunnel
VER=4.26
PKGVER=2
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER || exit 1
tar zxvf $PKG-$VER.tar.gz || exit 1
cd $PKG-$VER || exit 1
./configure --prefix=/home/t || exit 1
make || exit 1
pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" | \
	sed "s/ARCH/$ARCH/" | \
	sed '/<files>/a\
<file><path>etc/init.d/stunnel</path><init/></file>' | \
	sed '/<files>/a\
<file><path>var/lib/stunnel</path><posix><group>nobody</group><perms>1775</perms></posix></file>' > $pkgdir/tpkg.xml
cp ../postinstall $pkgdir/postinstall || exit 1
chmod 755 $pkgdir/postinstall || exit 1
mkdir $pkgdir/reloc || exit 1
# Add init script
mkdir -p $pkgdir/reloc/etc/init.d || exit 1
cp ../$PKG.init $pkgdir/reloc/etc/init.d/$PKG || exit 1
chmod 755 $pkgdir/reloc/etc/init.d/$PKG || exit 1
# Fake out make install to not build a sample key/cert
mkdir -p $pkgdir/reloc/etc/stunnel || exit 1
touch $pkgdir/reloc/etc/stunnel/stunnel.pem || exit 1
# Make the /var/lib directory, otherwise make install creates it with
# wacky perms when trying to make /var/lib/stunnel
mkdir -p $pkgdir/reloc/var/lib || exit 1
# Install
make install prefix=$pkgdir/reloc || exit 1
# Clean up our fake
rm $pkgdir/reloc/etc/stunnel/stunnel.pem || exit 1
# Make package
tpkg --make $pkgdir || exit 1
# Rename the package to reflect OS and arch
mv /tmp/$PKG-$VER-$PKGVER.tpkg /tmp/$PKG-$VER-$PKGVER-redhat$OSMAJOR-$ARCH.tpkg
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

