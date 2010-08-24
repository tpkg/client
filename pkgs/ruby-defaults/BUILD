#!/bin/sh
# TODO update this when tpkg supports provides/conflicts mechanism

set -e
set -u

PKG=ruby-defaults
VERS="1.8 1.9"
PKGVER=1
prefix=/opt/tpkg

for ver in $VERS
do
	pkgdir=`mktemp -d -t tpkg.XXXXXX`
	cat > $pkgdir/tpkg.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE tpkg SYSTEM "http://tpkg.sourceforge.net/tpkg-1.0.dtd">
<tpkg>
  <name>$PKG</name>
  <version>$ver</version>
  <package_version>$PKGVER</package_version>
  <maintainer>tpkg-users@lists.sourceforge.net</maintainer>
  <dependencies>
    <dependency>
      <name>ruby</name>
      <minimum_version>$ver</minimum_version>
      <maximum_version>$ver.9999</maximum_version>
    </dependency>
  </dependencies>
</tpkg>
EOF

	mkdir -p $pkgdir/reloc/bin
	for i in erb irb rdoc ri ruby 
	do
		ln -s ../ruby-$ver/bin/$i $pkgdir/reloc/bin/$i
	done

	tpkg --make $pkgdir
	rm -rf $pkgdir
done

