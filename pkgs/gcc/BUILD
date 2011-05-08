#!/bin/sh

set -e

PKG=gcc
VER=4.6.0
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

# http://gcc.gnu.org/install/prerequisites.html
if echo $OS | egrep 'RedHat|CentOS'
then
	for rpm in gcc glibc-devel gawk make
	do
		rpm --quiet -q $rpm || sudo yum install $rpm
	done
fi
for tpkg in gmp mpfr mpc
do
	tpkg --quiet -q $tpkg || tpkg -i $tpkg
done

rm -rf $PKG-$VER
tar jxvf $PKG-$VER.tar.bz2
cd $PKG-$VER
# There seems to be a bug in their build process that makes the
# LD_LIBRARY_PATH necessary to find the libraries, even though the
# --with-* options are supposed to take care of things.
# Some other users reporting the same issue:
# http://samritmaity.wordpress.com/2010/06/20/cannot-compute-suffix-of-object-files-gcc-4-4-3-installation-problem-solved/
LD_LIBRARY_PATH="/opt/tpkg/lib"
export LD_LIBRARY_PATH
# Without the --with-local-prefix option configure will search
# /usr/local for include files.  It seems like a bad idea to let
# configure do that as there's no telling what might be in that
# directory on the build host.
# Getting gcc to build with an rpath setting for the libraries took a
# bit of experimenting.  I tried various combinations of CFLAGS,
# LDFLAGS, STAGE1_CFLAGS and BOOT_CFLAGS all to no avail.  The build
# would fail in stage 1 unless LD_LIBRARY_PATH was set, and the
# resulting final binaries didn't have rpath set.  However, the
# --with-boot-ldflags option to configure seems to do the trick for
# getting the final binaries to have rpath.  There's also a
# --with-stage1-ldflags, but it didn't seem to do anything in practice.
# The build still failed in stage 1 unless LD_LIBRARY_PATH was set.
./configure \
	--prefix=/opt/tpkg \
	--mandir=/opt/tpkg/man \
	--with-local-prefix=/opt/tpkg \
	--with-gmp=/opt/tpkg \
	--with-mpfr=/opt/tpkg \
	--with-mpc=/opt/tpkg \
	--with-boot-ldflags="-L/opt/tpkg/lib -Wl,-rpath=/opt/tpkg/lib"
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
- name: gmp
- name: mpfr
- name: mpc
EOF
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
rm $pkgdir/root/opt/tpkg/share/info/dir
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

