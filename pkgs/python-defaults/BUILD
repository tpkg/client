#!/bin/sh
# TODO update this when tpkg supports provides/conflicts mechanism

set -e
set -u

PKG=python-defaults
VERS="2.7 3.2"
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
	ln -s python$ver $pkgdir/reloc/bin/python
	# Due to
	# http://docs.python.org/py3k/whatsnew/3.2.html#pep-3149-abi-version-tagged-so-files
	# the binary is called something like python3.2m-config where the
	# letter(s) following the version depend on the build flags used.
	# Sigh, what a PITA.
	if [ $ver = "3.2" ]
	then
		# Automating this is more pain than I want to deal with right now
		ln -s python${ver}m-config $pkgdir/reloc/bin/python-config
	else
		ln -s python$ver-config $pkgdir/reloc/bin/python-config
	fi

	tpkg --make $pkgdir
	rm -rf $pkgdir
done

