#!/bin/sh

set -e

PKG=apache-couchdb
VER=1.0.2
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
	# http://wiki.apache.org/couchdb/Installing_on_RHEL5
	for rpm in libicu-devel openssl-devel make gcc libtool which
	do
		rpm --quiet -q $rpm || sudo yum install $rpm
	done
fi
for tpkg in curl erlang-otp js
do
	tpkg --quiet -q $tpkg || tpkg -i $tpkg
done

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
./configure \
	--prefix=/opt/tpkg \
	--mandir=/opt/tpkg/man \
	--with-erlang=/opt/tpkg/lib/erlang/usr/include \
	--with-js-include=/opt/tpkg/include \
	--with-js-lib=/opt/tpkg/lib64
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
- name: curl
- name: erlang-otp
- name: js
- name: logrotate
- name: libicu
  native: true
- name: openssl
  native: true
externals:
  - name: user
    data: couchdb
files:
  files:
  - path: /opt/tpkg/etc/init.d/couchdb
    init: {}
    posix:
      perms: 0555
  - path: /opt/tpkg/etc/couchdb/local.ini
    config: true
  - path: /opt/tpkg/var/lib/couchdb
    posix:
      owner: couchdb
      perms: 0770
  - path: /opt/tpkg/var/log/couchdb
    posix:
      owner: couchdb
      perms: 0770
  - path: /opt/tpkg/var/run/couchdb
    posix:
      owner: couchdb
      perms: 0770
EOF
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
# The destination for the init script does not appear to be
# configurable, so just move it to the correct place.
mkdir -p $pkgdir/root/opt/tpkg/etc/init.d
mv $pkgdir/root/opt/tpkg/etc/rc.d/couchdb $pkgdir/root/opt/tpkg/etc/init.d
rmdir $pkgdir/root/opt/tpkg/etc/rc.d
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

