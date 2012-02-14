#!/bin/bash

set -e

PKG=mysql
VER=5.5.20
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
	for rpm in cmake gcc-c++ ncurses-devel openssl-devel; do
		rpm --quiet -q $rpm || sudo yum install $rpm
	done
fi

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
cmake \
	-DCMAKE_INSTALL_PREFIX=/opt/tpkg/$PKG-$VER \
	-DMYSQL_DATADIR=/opt/tpkg/$PKG-$VER/var/mysql \
	-DMYSQL_UNIX_ADDR=/opt/tpkg/$PKG-$VER/var/mysql/mysql.sock \
	-DWITH_INNOBASE_STORAGE_ENGINE=1 \
	-DWITH_SSL=system \
	-DWITH_READLINE=1
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.yml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" \
	> $pkgdir/tpkg.yml
cat <<EOF >> $pkgdir/tpkg.yml
externals:
- name: user
  data: mysql
- name: group
  data: mysql
files:
  files:
  - path: /opt/tpkg/etc/init.d/mysql
    init: {}
  - path: /opt/tpkg/$PKG-$VER/var/run/mysqld
    posix:
      owner: mysql
      group: mysql
EOF
# Add config file
mkdir -p $pkgdir/root/opt/tpkg/$PKG-$VER/etc
cp ../my.cnf $pkgdir/root/opt/tpkg/$PKG-$VER/etc/my.cnf
# Add init script
mkdir -p $pkgdir/root/opt/tpkg/etc/init.d
cp ../$PKG.init $pkgdir/root/opt/tpkg/etc/init.d/$PKG
chmod 755 $pkgdir/root/opt/tpkg/etc/init.d/$PKG
# Directories for log and pid file
mkdir -p $pkgdir/root/opt/tpkg/$PKG-$VER/var/log
mkdir -p $pkgdir/root/opt/tpkg/$PKG-$VER/var/run/mysqld
# Create generic non-versioned directory link
ln -s -f /opt/tpkg/$PKG-$VER $pkgdir/root/opt/tpkg/$PKG
# Install
make install DESTDIR=$pkgdir/root
# Clean out stuff we don't want
rm -rf $pkgdir/root/opt/tpkg/$PKG-$VER/data
rm -rf $pkgdir/root/opt/tpkg/$PKG-$VER/mysql-test
rm -rf $pkgdir/root/opt/tpkg/$PKG-$VER/sql-bench
# Clean up doc files
(cd $pkgdir/root/opt/tpkg/$PKG-$VER && mv README INSTALL-BINARY COPYING docs)
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

