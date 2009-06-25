#!/bin/sh

PKG=oracle_client
PKGVER=1

#for ver in 10.2.0.1.0 11.1.0.6.0
for ver in 10.2.0.1.0
do
	# tpkg expects i686 as the architecture on 32 bit Red Hat boxes
	for arch in i686 x86_64
	do
		if [ -d "/home/t/$PKG-$ver" ]
		then
			echo "Install directory already exist, unfortunately you need to build this package on a box where the package is not installed because the Oracle installer has to install the files into the real location." >&2
			exit 1
		fi

		rm -rf $HOME/oraInventory

		# Make the appropriate directory structure
		sudo mkdir -p /home/t/$PKG-$ver || exit 1
		sudo chown $USER /home/t/$PKG-$ver || exit 1
		# Unpack Oracle's zip file
		rm -rf client || exit 1
		# Oracle's filenames are completely inconsistent.  Sigh.
		if [ $ver = '10.2.0.1.0' ]
		then
			if [ $arch = 'i686' ]
			then
				unzip 10201_client_linux32.zip
			elif [ $arch = 'x86_64' ]
			then
				# Gah, they couldn't even stick to one packaging format
				zcat 10201_client_linux_x86_64.cpio.gz | cpio --extract -dm
			fi
		elif [ $ver = '11.1.0.6.0' ]
		then
			if [ $arch = 'i686' ]
			then
				unzip linux_x86_11gR1_client.zip
			elif [ $arch = 'x86_64' ]
			then
				unzip linux.x64_11gR1_client.zip
			fi
		fi
		if [ ! -d 'client' ]
		then
			echo "No matching zip file from Oracle" >&2
			exit 1
		fi
		# Build response file from sample
		# ORACLE_BASE is new in 11g
		cat client/response/clientadmin.rsp | \
			sed '/^UNIX_GROUP_NAME/s,=.*,=dba,' | \
			sed "/^ORACLE_BASE/s,=.*,=/home/t/$PKG-$ver," | \
			sed "/^ORACLE_HOME/s,=.*,=/home/t/$PKG-$ver," | \
			sed "/^ORACLE_HOME_NAME/s,=.*,=OraClient," > client/response/tpkg.rsp
		cat client/response/tpkg.rsp
		# Run install
		(cd client && ./runInstaller -silent -responseFile $PWD/response/tpkg.rsp) || exit 1
		# Oh genius, the installer forks into the background so
		# you don't know when it finishes or if it fails.
		sleep 180
		echo "Hit return when install seems to be finished"
		read junk
		# Cleanup
		rm -rf client || exit 1
		# Prep package directory
		pkgdir=`mktemp -d -t tpkg.XXXXXX` || exit 1
		cat ../tpkg.xml | \
			sed "s/NAME/$PKG/" | \
			sed "s/VERSION/$ver/" | \
			sed "s/PKGVER/$PKGVER/" | \
			sed "s/OS/RedHat-3,CentOS-3,RedHat-4,CentOS-4,RedHat-5,CentOS-5/" | \
			sed "s/ARCH/$arch/" | \
			grep -v files > $pkgdir/tpkg.xml
		cat $pkgdir/tpkg.xml
		# Move over installed files
		mkdir -p $pkgdir/root/home/t || exit 1
		sudo mv /home/t/$PKG-$ver $pkgdir/root/home/t || exit 1
		# Make package
		sudo tpkg --make $pkgdir || exit 1
		# Rename the package to reflect OS and arch
		sudo mv /tmp/$PKG-$ver-$PKGVER.tpkg /tmp/$PKG-$ver-$PKGVER-redhat-$arch.tpkg
		# Cleanup
		sudo rm -rf $pkgdir
	done
done

