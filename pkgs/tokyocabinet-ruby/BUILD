#!/bin/bash
set -e
set -u
set -o pipefail

PKG=tokyocabinet-ruby
VER=1.23
RUBYDEP=${RUBYDEP-"ruby"}
PKGVER=1$RUBYDEP
prefix=/opt/tpkg
rubyprefix=$prefix/$RUBYDEP

test -x $rubyprefix/bin/ruby || \
	{ echo >&2 "$prefix/bin/ruby not found"; exit 1; }
test -e $prefix/lib/libtokyocabinet.a || \
	{ echo >&2 "libtokyocabinet.a not found"; exit 1; }

PATH=$rubyprefix/bin:$prefix/bin:$PATH
export PATH

OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER
tar zxf $PKG-$VER.tar.gz
cd $PKG-$VER
ruby extconf.rb
make LOCAL_LIBS="-Wl,-rpath=$prefix/lib"

pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat > $pkgdir/tpkg.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE tpkg SYSTEM "http://tpkg.sourceforge.net/tpkg-1.0.dtd">
<tpkg>
  <name>$PKG</name>
  <version>$VER</version>
  <package_version>$PKGVER</package_version>
  <maintainer>tpkg-users@lists.sourceforge.net</maintainer>
  <operatingsystem>RedHat-$OSMAJOR,CentOS-$OSMAJOR</operatingsystem>
  <architecture>$ARCH</architecture>
  <dependencies>
    <dependency>
      <name>tokyocabinet</name>
      <name>$RUBYDEP</name>
    </dependency>
  </dependencies>
</tpkg>
EOF

mkdir -p $pkgdir/root$rubyprefix
make install DESTDIR=$pkgdir/root

# Make package
tpkg --make $pkgdir || exit 1
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER
