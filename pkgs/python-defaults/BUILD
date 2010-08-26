#!/bin/sh
# TODO update this when tpkg supports provides/conflicts mechanism

set -e
set -u

PKG=python-defaults
VERS="2.6 3.1"
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
  <description>Link python binaries into top level bin directory</description>
  <dependencies>
    <dependency>
      <name>python</name>
      <minimum_version>$ver</minimum_version>
      <maximum_version>$ver.9999</maximum_version>
    </dependency>
  </dependencies>
</tpkg>
EOF

	mkdir -p $pkgdir/reloc/bin
	for i in python
	do
		ln -s python$ver $pkgdir/reloc/bin/$i
	done

	tpkg --make $pkgdir
	rm -rf $pkgdir
done

