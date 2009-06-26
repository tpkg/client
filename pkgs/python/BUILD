#!/sbin/sh

PKG=python
PKGVER=1
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

for ver in 2.5.4 2.6.2 3.0.1
do
	rm -rf Python-$ver || exit 1
	tar jxvf Python-$ver.tar.bz2 || exit 1
	cd Python-$ver || exit 1
	./configure --prefix=/home/t || exit 1
	make || exit 1
	pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1
	cat ../../tpkg.xml | \
		sed "s/NAME/$PKG/" | \
		sed "s/VERSION/$ver/" | \
		sed "s/PKGVER/$PKGVER/" | \
		sed "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" | \
		sed "s/ARCH/$ARCH/" | \
		grep -v files > $pkgdir/tpkg.xml
	# Install
	mkdir $pkgdir/root
	make altinstall DESTDIR=$pkgdir/root || exit 1
	# Make package
	tpkg --make $pkgdir || exit 1
	# Rename the package to reflect OS and arch
	mv /tmp/$PKG-$ver-$PKGVER.tpkg /tmp/$PKG-$ver-$PKGVER-redhat$OSMAJOR-$ARCH.tpkg
	# Cleanup
	rm -rf $pkgdir
	cd ..
	rm -rf Python-$ver
done

