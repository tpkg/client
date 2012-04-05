#!/sbin/sh

set -e

PKG=python
PKGVER=2
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'
then
        # Save folks from having to build separate packages for Red Hat and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR, CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

for tpkg in bzip2 gdbm; do
	tpkg --quiet -q $tpkg || tpkg -i $tpkg
done

for ver in 2.7.2 3.2.2
do
	rm -rf Python-$ver
	tar jxvf Python-$ver.tar.bz2
	cd Python-$ver
	LDFLAGS="-Wl,-rpath,/opt/tpkg/lib" ./configure --prefix=/opt/tpkg --mandir=/opt/tpkg/man --enable-shared
	make
	pkgdir=`mktemp -d -t tpkg.XXXXXX`
	cat ../../tpkg.yml | \
		sed "s/NAME/$PKG/" | \
		sed "s/VERSION/$ver/" | \
		sed "s/PKGVER/$PKGVER/" | \
		sed "s/OS/$OS/" | \
		sed "s/ARCH/$ARCH/" \
		> $pkgdir/tpkg.yml
	cat <<EOF >> $pkgdir/tpkg.yml
dependencies:
- name: bzip2
- name: gdbm
EOF
	# Install
	mkdir $pkgdir/root
	make altinstall DESTDIR=$pkgdir/root
	# Make package
	tpkg --make $pkgdir
	# Cleanup
	rm -rf $pkgdir
	cd ..
	rm -rf Python-$ver
done

