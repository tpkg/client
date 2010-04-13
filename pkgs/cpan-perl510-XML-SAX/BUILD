#!/bin/sh

set -e

/home/t/perl-5.10/bin/perl /usr/bin/cpan2tpkg --package-version 2 XML::SAX

# Probably should add an option to cpan2tpkg to allow the user to
# specify a postinstall script
VER=0.96-2
rm -rf /tmp/cpan-perl510-XML-SAX-$VER
tar -C /tmp -xf /tmp/cpan-perl510-XML-SAX-$VER.tpkg
rm /tmp/cpan-perl510-XML-SAX-$VER.tpkg
tar -C /tmp/cpan-perl510-XML-SAX-$VER \
	-xf /tmp/cpan-perl510-XML-SAX-$VER/tpkg.tar
cp postinstall /tmp/cpan-perl510-XML-SAX-$VER/tpkg
chmod 755 /tmp/cpan-perl510-XML-SAX-$VER/tpkg/postinstall
tpkg --make /tmp/cpan-perl510-XML-SAX-$VER/tpkg
mv /tmp/cpan-perl510-XML-SAX-$VER/cpan-perl510-XML-SAX-$VER.tpkg /tmp
rm -rf /tmp/cpan-perl510-XML-SAX-$VER

