#!/bin/sh

set -e

PKG=imapfilter
VER=2.2.2
PKGVER=1
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'
then
        # Save folks from having to build separate packages for Red Hat and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR,CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

tpkg -q lua,pcre || tpkg -i lua,pcre

rm -rf $PKG-$VER
tar jxvf $PKG-$VER.tar.bz2
cd $PKG-$VER
#./configure --prefix=/home/t
./configure -p /home/t
sed '/^INCDIRS/s,$, -I/home/t/include,' Makefile > Makefile.new
mv Makefile.new Makefile
sed '/^LIBDIRS/s,$, -L/home/t/lib,' Makefile > Makefile.new
mv Makefile.new Makefile
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" | \
	sed '/<files>/i\
<dependencies><dependency><name>lua</name></dependency><dependency><name>pcre</name></dependency></dependencies>' \
	> $pkgdir/tpkg.xml
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

