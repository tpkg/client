#!/bin/sh

set -e

PKG=erlang-otp
VER=14B02
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
	# Per http://www.erlang.org/doc/installation_guide/INSTALL.html
	# TODO: perl, jdk?, X libraries, flex?
	for rpm in make gcc m4 ncurses-devel openssl-devel
	do
		rpm --quiet -q $rpm || sudo yum install $rpm
	done
fi

#rm -rf $PKG-$VER
#tar jxvf $PKG-$VER.tar.bz2
#cd $PKG-$VER
rm -rf otp_src_R$VER
tar zxvf otp_src_R$VER.tar.gz
cd otp_src_R$VER
./configure --prefix=/opt/tpkg
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.yml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" > $pkgdir/tpkg.yml
#cat <<EOF >> $pkgdir/tpkg.yml
#dependencies:
#- name: zlib
#  native: true
#EOF
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
#rm -rf $PKG-$VER
rm -rf otp_src_R$VER

