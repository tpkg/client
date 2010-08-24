#!/bin/sh

PKG=oracle_client
PKGVER=2

# The installer expects the user to be in whatever group we specify in
# the UNIX_GROUP_NAME setting in the configuration (dba in our case), so
# make sure the user actually is in that group.  The error the installer
# kicks out (SEVERE:S_OWNER_SYSTEM_EPERM) is not very obvious.
if ! id | awk '{print $3}' | grep dba
then
	echo "You need to be in the dba group" >&2
	exit 1
fi

#for ver in 10.2.0.1.0 11.1.0.6.0
for ver in 10.2.0.1.0
do
	# tpkg expects i686 as the architecture on 32 bit Red Hat boxes
	for arch in i686 x86_64
	do
		if [ -d "/opt/tpkg/$PKG-$ver" ]
		then
			echo "Install directory already exist, unfortunately you need to build this package on a box where the package is not installed because the Oracle installer has to install the files into the real location." >&2
			exit 1
		fi

		rm -rf $HOME/oraInventory

		# Make the appropriate directory structure
		sudo mkdir -p /opt/tpkg/$PKG-$ver || exit 1
		sudo chown $USER /opt/tpkg/$PKG-$ver || exit 1
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
			sed "/^ORACLE_BASE/s,=.*,=/opt/tpkg/$PKG-$ver," | \
			sed "/^ORACLE_HOME/s,=.*,=/opt/tpkg/$PKG-$ver," | \
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
		mkdir -p $pkgdir/root/opt/tpkg || exit 1
		sudo mv /opt/tpkg/$PKG-$ver $pkgdir/root/opt/tpkg || exit 1
		# Fix permissions
		find $pkgdir/root/opt/tpkg -type d | xargs chmod g-w,o+rx
		find $pkgdir/root/opt/tpkg -type f | xargs chmod g-w,o+rX
		# Make package
		tpkg --make $pkgdir || exit 1
		# Cleanup
		rm -rf $pkgdir
	done
done

