#!/bin/sh

VER=1.0.5
PKGVER=1

ORAVER=10.2.0.4.0

tpkg -q oracle_instant_client-sdk=$ORAVER || tpkg -i oracle_instant_client-sdk=$ORAVER
sh -c "LD_LIBRARY_PATH=/home/t/oracle_instant_client-$ORAVER gem2tpkg ruby-oci8 --version=$VER --package-version=$PKGVER --extra-deps=oracle_instant_client-basic,$ORAVER,$ORAVER, --build-options '--with-dldflags=-Wl,-rpath,/home/t/oracle_instant_client-$ORAVER'"

