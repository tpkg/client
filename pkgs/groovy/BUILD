#!/bin/sh

set -e

PKG=groovy
VER=1.8.3
PKGVER=1

for tpkg in jdk apache-ant
do
	tpkg --quiet -q $tpkg || tpkg -i $tpkg
done

rm -rf $PKG-$VER
#tar zxvf $PKG-$VER.tar.gz
unzip $PKG-src-$VER.zip
cd $PKG-$VER
#./configure \
#	--prefix=/opt/tpkg \
#	--mandir=/opt/tpkg/man
#make
# http://groovy.codehaus.org/Building+Groovy+from+Source
ant install -Djava.awt.headless=true
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.yml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	grep -v "OS" | \
	grep -v "ARCH" \
	> $pkgdir/tpkg.yml
cat <<EOF >> $pkgdir/tpkg.yml
dependencies:
- name: jdk
EOF
mkdir $pkgdir/root
mkdir -p $pkgdir/root/opt/tpkg/share/$PKG-$VER
# Install
#make install DESTDIR=$pkgdir/root
(cd target/install && find . | cpio -pdum $pkgdir/root/opt/tpkg/share/$PKG-$VER)
mkdir -p $pkgdir/root/opt/tpkg/etc/profile.d
cat ../groovy.sh | sed "s/PKG/$PKG/" | sed "s/VER/$VER/" \
	> $pkgdir/root/opt/tpkg/etc/profile.d/groovy.sh
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

