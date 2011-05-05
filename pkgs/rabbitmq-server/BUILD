#!/bin/sh

set -e

PKG=rabbitmq-server
VER=2.4.1
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
	for rpm in libxslt xmlto
	do
		rpm --quiet -q $rpm || sudo yum install $rpm
	done
fi
# Build fails with python 3
for tpkg in erlang-otp python-defaults=2.7
do
	tpkg --quiet -q $tpkg || tpkg -i $tpkg
done

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
#./configure  --prefix=/opt/tpkg
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
- name: erlang-otp
externals:
  - name: user
    data: rabbitmq
files:
  files:
  - path: /opt/tpkg/etc/init.d/rabbitmq
    init: {}
    posix:
      perms: 0555
  - path: /opt/tpkg/var/lib/rabbitmq
    posix:
      owner: rabbitmq
  - path: /opt/tpkg/var/log/rabbitmq
    posix:
      owner: rabbitmq
  - path: /opt/tpkg/var/run/rabbitmq
    posix:
      owner: rabbitmq
EOF
mkdir $pkgdir/root
# Install
#make install DESTDIR=$pkgdir/root
make install \
	TARGET_DIR=$pkgdir/root/opt/tpkg \
	SBIN_DIR=$pkgdir/root/opt/tpkg/sbin \
	MAN_DIR=$pkgdir/root/opt/tpkg/man
# Clean up some files that get dumped in the base target directory
mkdir -p $pkgdir/root/opt/tpkg/share/doc/$PKG
mv $pkgdir/root/opt/tpkg/INSTALL $pkgdir/root/opt/tpkg/share/doc/$PKG
mv $pkgdir/root/opt/tpkg/LICENSE* $pkgdir/root/opt/tpkg/share/doc/$PKG
mkdir -p $pkgdir/root/opt/tpkg/lib/rabbitmq
mv $pkgdir/root/opt/tpkg/plugins $pkgdir/root/opt/tpkg/lib/rabbitmq
# Fix up paths in the scripts
for i in $pkgdir/root/opt/tpkg/sbin/*
do
	cat $i | \
		sed 's,/etc/rabbitmq,/opt/tpkg/etc/rabbitmq,g' | \
		sed 's,/var/log,/opt/tpkg/var/log,g' | \
		sed 's,/var/lib,/opt/tpkg/var/lib,g' | \
		sed 's,/plugins,/lib/rabbitmq/plugins,g' \
		> $i.new
	chmod 755 $i.new
	mv $i.new $i
done
# Working directories for the server
mkdir -p $pkgdir/root/opt/tpkg/var/lib/rabbitmq
mkdir -p $pkgdir/root/opt/tpkg/var/log/rabbitmq
mkdir -p $pkgdir/root/opt/tpkg/var/run/rabbitmq
# Copy over init script
mkdir -p $pkgdir/root/opt/tpkg/etc/init.d
cp ../rabbitmq.init $pkgdir/root/opt/tpkg/etc/init.d/rabbitmq
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

