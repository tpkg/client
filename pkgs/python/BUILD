#!/sbin/sh

set -e

PKG=python
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
	rpm --quiet -q gcc bzip2-devel || sudo yum install gcc bzip2-devel
fi

for ver in 2.7.1 3.2
do
	rm -rf Python-$ver
	tar jxvf Python-$ver.tar.bz2
	cd Python-$ver
	./configure --prefix=/opt/tpkg --mandir=/opt/tpkg/man
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
  native: true
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

