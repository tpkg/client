#!/bin/bash
# bashisms in full effect here

set -eu
set -o pipefail # bash v3 dependency

PKG=haproxy
VER=1.3.17
PKGVER=1
eval `facter |sed 's/ => /=/' | \
  egrep '(hardwaremodel|lsbmajdistrelease|kernelversion|kernel)'`
OSMAJOR=$lsbmajdistrelease
ARCH=$hardwaremodel

target=generic
case $kernel-$kernelversion in
Linux-2.6*) target=linux26 ;;
# not going to bother customizing support for inferior kernels for now
esac
# rpm --quiet -q pcre-devel || sudo yum install pcre-devel # pcre is optional

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
make -j4 TARGET=$target
pkgdir=`mktemp -d -t tpkg.XXXXXX`
sed -e "s/NAME/$PKG/" \
	-e "s/VERSION/$VER/" \
	-e "s/PKGVER/$PKGVER/" \
	-e "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" \
	-e "s/ARCH/$ARCH/" \
	-e "/file/d" \
	-e "/path/d" \
	-e "/init/d" \
	< ../../tpkg.xml > $pkgdir/tpkg.xml

mkdir -p $pkgdir/reloc/sbin
cp -p haproxy $pkgdir/reloc/sbin
# Fix perms
sudo chown -R 0:0 $pkgdir/reloc

# Make package
sudo tpkg --make $pkgdir

# Rename the package to reflect OS and arch
sudo mv /tmp/$PKG-$VER-$PKGVER.tpkg \
  /tmp/$PKG-$VER-$PKGVER-redhat$OSMAJOR-$ARCH.tpkg

# Cleanup
sudo rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER
