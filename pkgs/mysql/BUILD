#!/sbin/sh

set -e

PKG=mysql
VER=5.1.33
PKGVER=4
OS=`tpkg --qenv | grep 'Operating System' | awk '{print $NF}'`
if echo $OS | egrep 'RedHat|CentOS'
then
        # Save folks from having to build separate packages for Red Hat and
        # CentOS
        OSMAJOR=`echo $OS | cut -d- -f2`
        OS="RedHat-$OSMAJOR,CentOS-$OSMAJOR"
fi
ARCH=`tpkg --qenv | grep 'Architecture' | awk '{print $NF}'`

rm -rf $PKG-$VER
tar zxvf $PKG-$VER.tar.gz
cd $PKG-$VER
rpm --quiet -q ncurses-devel || sudo yum install ncurses-devel
rpm --quiet -q openssl-devel || sudo yum install openssl-devel
./configure \
	--prefix=/home/t \
	--localstatedir=/home/t/var/mysql \
	--with-unix-socket-path=/home/t/var/mysql/mysql.sock \
	--with-innodb \
	--with-extra-charsets=complex \
	--with-ssl=/usr
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" | \
	sed '/<files>/i\
<externals><external><name>user</name><data>mysql</data></external><external><name>group</name><data>mysql</data></external></externals>' | \
	sed '/<files>/a\
<file><path>/home/t/etc/init.d/mysql</path><init/></file>' | \
	sed '/<files>/a\
<file><path>/home/t/var/run/mysqld</path><posix><owner>mysql</owner><group>mysql</group></posix></file>' > $pkgdir/tpkg.xml
mkdir -p $pkgdir/root/home/t
# Add config file
mkdir -p $pkgdir/root/home/t/etc
cp ../my.cnf $pkgdir/root/home/t/etc/my.cnf
# Add init script
mkdir -p $pkgdir/root/home/t/etc/init.d
cp ../$PKG.init $pkgdir/root/home/t/etc/init.d/$PKG
chmod 755 $pkgdir/root/home/t/etc/init.d/$PKG
# Make directory for data and socket
#mkdir -p $pkgdir/root/home/t/var/mysql
#chown mysql:mysql $pkgdir/root/home/t/var/mysql
# Directories for log and pid file
mkdir -p $pkgdir/root/home/t/var/log
mkdir -p $pkgdir/root/home/t/var/run/mysqld
# Install
make install prefix=$pkgdir/root/home/t
# Clean out stuff we don't want
rm -rf $pkgdir/root/home/t/mysql-test
rm -rf $pkgdir/root/home/t/sql-bench
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

