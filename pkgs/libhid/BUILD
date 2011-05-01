#!/bin/sh

set -e

PKG=libhid
VER=0.2.16
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
	for rpm in libusb-devel swig doxygen
	do
		rpm --quiet -q $rpm || sudo yum install $rpm
	done
fi
# NOTE: I put way too much time into trying to get the python bindings
# to compile on CentOS 5 with no luck.  I've left some commented out
# lines to reflect what I was trying in case someone wants to pick up
# that effort again in the future.  In the meantime the --disable-swig
# option to configure turns that functionality off.
# Seems to be incompatible with python 3 (I got a lot of syntax errors)
#MAJOR_PYTHON_VERSION=2.7
#PYTHON_VERSION=2.7.1
#export PYTHON_VERSION
#tpkg --quiet -q python-defaults=$MAJOR_PYTHON_VERSION || tpkg -i python-defaults=$MAJOR_PYTHON_VERSION

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
#./configure --prefix=/opt/tpkg --mandir=/opt/tpkg/man LDFLAGS="`/opt/tpkg/bin/python-config --ldflags`"
./configure --prefix=/opt/tpkg --mandir=/opt/tpkg/man --disable-swig
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
- name: libusb
  native: true
#- name: python
#  minimum_version: $PYTHON_VERSION
#  maximum_version: $PYTHON_VERSION
EOF
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

