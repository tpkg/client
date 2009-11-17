#!/sbin/sh

PKG=mysql
VER=5.1.33
PKGVER=3
OSMAJOR=`facter | grep lsbmajdistrelease | cut -d' ' -f3`
ARCH=`facter hardwaremodel`

rm -rf $PKG-$VER || exit 1
tar zxvf $PKG-$VER.tar.gz || exit 1
cd $PKG-$VER || exit 1
rpm --quiet -q ncurses-devel || sudo yum install ncurses-devel
rpm --quiet -q openssl-devel || sudo yum install openssl-devel
./configure \
	--prefix=/home/t \
	--localstatedir=/home/t/var/mysql \
	--with-unix-socket-path=/home/t/var/mysql/mysql.sock \
	--with-extra-charsets=complex \
	--with-ssl=/usr \
	|| exit 1
make || exit 1
pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/RedHat-$OSMAJOR,CentOS-$OSMAJOR/" | \
	sed "s/ARCH/$ARCH/" | \
	sed '/<files>/i\
<externals><external><name>user</name><data>mysql</data></external><external><name>group</name><data>mysql</data></external></externals>' | \
	sed '/<files>/a\
<file><path>/home/t/etc/init.d/mysql</path><init/></file>' | \
	sed '/<files>/a\
<file><path>/home/t/var/run/mysqld</path><posix><owner>mysql</owner><group>mysql</group></posix></file>' > $pkgdir/tpkg.xml
mkdir -p $pkgdir/root/home/t || exit 1
# Add config file
mkdir -p $pkgdir/root/home/t/etc || exit 1
cp ../my.cnf $pkgdir/root/home/t/etc/my.cnf || exit 1
# Add init script
mkdir -p $pkgdir/root/home/t/etc/init.d || exit 1
cp ../$PKG.init $pkgdir/root/home/t/etc/init.d/$PKG || exit 1
chmod 755 $pkgdir/root/home/t/etc/init.d/$PKG || exit 1
# Make directory for data and socket
#mkdir -p $pkgdir/root/home/t/var/mysql
#chown mysql:mysql $pkgdir/root/home/t/var/mysql
# Directories for log and pid file
mkdir -p $pkgdir/root/home/t/var/log
mkdir -p $pkgdir/root/home/t/var/run/mysqld
# Install
make install prefix=$pkgdir/root/home/t || exit 1
# Clean out stuff we don't want
rm -rf $pkgdir/root/home/t/mysql-test
rm -rf $pkgdir/root/home/t/sql-bench
# Make package
tpkg --make $pkgdir || exit 1
# Rename the package to reflect OS and arch
mv /tmp/$PKG-$VER-$PKGVER.tpkg /tmp/$PKG-$VER-$PKGVER-redhat$OSMAJOR-$ARCH.tpkg
# Cleanup
rm -rf $pkgdir
cd ..
rm -rf $PKG-$VER

