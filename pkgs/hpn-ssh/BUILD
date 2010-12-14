#!/bin/sh

set -e

PKG=hpn-ssh
VER="5.6p1"
HPNVER="13v10"
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

if echo $OS | egrep 'RedHat|CentOS'
then
	rpm --quiet -q zlib-devel openssl-devel pam-devel krb5-devel || sudo yum install zlib-devel openssl-devel pam-devel krb5-devel
fi

#rm -rf $PKG-$VER
rm -rf openssh-$VER
#tar zxvf $PKG-$VER.tar.gz
tar zxvf openssh-$VER.tar.gz
#cd $PKG-$VER
cd openssh-$VER
#zcat ../$PKG-$VER-hpn$HPNVER.diff.gz
zcat ../openssh-$VER-hpn$HPNVER.diff.gz | patch
./configure --prefix=/opt/tpkg \
	--datarootdir=/opt/tpkg \
	--with-pid-dir=/opt/tpkg/var/run \
	--with-privsep-path=/opt/tpkg/var/empty \
	--with-pam \
	--with-kerberos5
make
pkgdir=`mktemp -d -t tpkg.XXXXXX`
cat ../../tpkg.xml | \
	sed "s/NAME/$PKG/" | \
	sed "s/VERSION/$VER/" | \
	sed "s/PKGVER/$PKGVER/" | \
	sed "s/OS/$OS/" | \
	sed "s/ARCH/$ARCH/" | \
	sed '/<files>/a\
<file><path>/opt/tpkg/etc/init.d/hpn-ssh</path><init/></file>' \
	> $pkgdir/tpkg.xml
mkdir $pkgdir/root
# Install
make install DESTDIR=$pkgdir/root
# Change sshd port so as to not conflict with system sshd
sed 's/#Port 22/Port 2222/' $pkgdir/root/opt/tpkg/etc/sshd_config > $pkgdir/root/opt/tpkg/etc/sshd_config.new
mv $pkgdir/root/opt/tpkg/etc/sshd_config.new $pkgdir/root/opt/tpkg/etc/sshd_config
# Make the privsep directory
mkdir -p $pkgdir/root/opt/tpkg/var/empty
# Insert init script
mkdir -p $pkgdir/root/opt/tpkg/etc/init.d
cp ../$PKG.init $pkgdir/root/opt/tpkg/etc/init.d/$PKG
chmod 555 $pkgdir/root/opt/tpkg/etc/init.d/$PKG
# Make package
tpkg --make $pkgdir
# Cleanup
rm -rf $pkgdir
cd ..
#rm -rf $PKG-$VER
rm -rf openssh-$VER

