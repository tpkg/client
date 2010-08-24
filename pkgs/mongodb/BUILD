#!/bin/sh

# Abort on failure of any command
set -e

PKG=mongodb
VER=1.4.3
PKGVER=2
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'
then
        # Save folks from having to build separate packages for Red Hat and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR,CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

tpkg -q scons || tpkg -i scons
rpm --quiet -q boost-devel || sudo yum install boost-devel
rpm --quiet -q ncurses-devel || sudo yum install ncurses-devel
rpm --quiet -q pcre-devel || sudo yum install pcre-devel
rpm --quiet -q readline-devel || sudo yum install readline-devel
tpkg -q js || tpkg -i js

rm -rf $PKG-src-r$VER
tar zxvf $PKG-src-r$VER.tar.gz
cd $PKG-src-r$VER
sed '/for.*GetOption.*extrapath/a\
        env.Append( LIBPATH=[ x + "/lib64" ] )' SConstruct > SConstruct.new
mv SConstruct.new SConstruct
scons --extrapath /opt/tpkg all
pkgdir=`mktemp -d -t tpkg.XXXXXX`
# Note no dependencies are added.  The build process links all non-core
# libraries (boost, ncurses, js, etc.) statically.
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" | \
	sed '/<files>/a\
<file><path>/opt/tpkg/etc/init.d/mongodb</path><init/></file>' | \
	sed '/<files>/a\
<file><path>/opt/tpkg/var/mongodb</path><posix><owner>t</owner></posix></file>' \
	> $pkgdir/tpkg.xml
mkdir -p $pkgdir/root/opt/tpkg
# Add config file
mkdir -p $pkgdir/root/opt/tpkg/etc
cp ../mongodb.conf $pkgdir/root/opt/tpkg/etc/mongodb.conf
# Add init script
mkdir -p $pkgdir/root/opt/tpkg/etc/init.d
cp ../$PKG.init $pkgdir/root/opt/tpkg/etc/init.d/$PKG
chmod 755 $pkgdir/root/opt/tpkg/etc/init.d/$PKG
# Directories for log and pid file
mkdir -p $pkgdir/root/opt/tpkg/var/log
mkdir -p $pkgdir/root/opt/tpkg/var/run
# Data directory
mkdir -p $pkgdir/root/opt/tpkg/var/mongodb
# Install
scons --extrapath /opt/tpkg --prefix=$pkgdir/root/opt/tpkg install
# Move a few files to a more appropriate location
mkdir -p $pkgdir/root/opt/tpkg/share/doc/mongodb-$VER
for doc in GNU-AGPL-3.0 README THIRD-PARTY-NOTICES
do
	mv $pkgdir/root/opt/tpkg/$doc $pkgdir/root/opt/tpkg/share/doc/mongodb-$VER
done
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-src-r$VER

