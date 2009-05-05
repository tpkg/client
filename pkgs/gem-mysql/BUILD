#!/bin/sh

VER=2.7
PKGVER=1

rpm --quiet -q openssl-devel zlib-devel || sudo yum -y install openssl-devel zlib-devel
tpkg -q mysql || sudo tpkg -i mysql
sudo gem2tpkg mysql --version=$VER --package-version=$PKGVER --extra-deps=mysql,,, --native-deps=openssl,,,zlib,,, --build-options '--with-mysql-config=/home/t/bin/mysql_config --with-dldflags="-Wl,-rpath,/home/t/lib/mysql"'

