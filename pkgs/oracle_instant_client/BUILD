#!/bin/sh

PKG=oracle_instant_client
PKGVER=1

for ver in 10.2.0.4.0 11.1.0.7.0
do
	for arch in i686 x86_64
	do
		for component in basic jdbc sdk sqlplus
		do
			pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1

			# The !basic packages need to depend on the basic package
			add_dep=cat
			if [ $component != 'basic' ]
			then
				add_dep="sed /<files>/i\
<dependencies><dependency><name>$PKG-basic</name><minimum_version>$ver</minimum_version><maximum_version>$ver</maximum_version></dependency></dependencies>"
			fi
			cat ../tpkg.xml | \
				sed "s/NAME/$PKG-$component/" | \
				sed "s/VERSION/$ver/" | \
				sed "s/PKGVER/$PKGVER/" | \
				sed "s/OS/RedHat-3,CentOS-3,RedHat-4,CentOS-4,RedHat-5,CentOS-5/" | \
				sed "s/ARCH/$arch/" | \
				$add_dep | grep -v files > $pkgdir/tpkg.xml
			cat $pkgdir/tpkg.xml

			# Make the appropriate directory structure
			mkdir -p $pkgdir/reloc/$PKG-$ver || exit 1
			# Unpack Oracle's zip file
			rm -rf instantclient_* || exit 1
			# Oracle's filenames are completely inconsistent.  Sigh.
			# Example: basic-11.1.0.7.0-linux-x86_64.zip
			if [ -f $component-$ver-linux-$arch.zip ]
			then
				unzip $component-$ver-linux-$arch.zip
			elif [ $arch = 'i686' ]
			then
				# Example: instantclient-basic-linux32-11.1.0.7.zip
				ver_variant1=`echo $ver | sed 's/\.0$//'`
				if [ -f instantclient-$component-linux32-$ver_variant1.zip ]
				then
					unzip instantclient-$component-linux32-$ver_variant1.zip
				fi
				# Example: oracle-instantclient-basic-10.2.0.4-1.i386.zip
				ver_variant2=`echo $ver | sed 's/\.0$/-1/'`
				comp_variant=$component
				if [ $component = 'sdk' ]
				then
					comp_variant='devel'
				fi
				if [ -f oracle-instantclient-$comp_variant-$ver_variant2.i386.zip ]
				then
					unzip oracle-instantclient-$comp_variant-$ver_variant2.i386.zip
				fi
			fi
			if [ ! -d instantclient_* ]
			then
				echo "No matching zip file from Oracle" >&2
				exit 1
			fi
			mv instantclient_*/* $pkgdir/reloc/$PKG-$ver || exit 1
			rmdir instantclient_* || exit 1
			# Make package
			tpkg --make $pkgdir || exit 1
			# Rename the package to reflect OS and arch
			mv /tmp/$PKG-$component-$ver-$PKGVER.tpkg /tmp/$PKG-$component-$ver-$PKGVER-redhat-$arch.tpkg
			# Cleanup
			rm -rf $pkgdir
		done
	done
done

