BUILDROOT=/var/tmp/tpkg-buildroot
# Grab the current version from the library
VER=$(shell ruby -e "$$:.unshift('.'); require 'tpkg'; puts Tpkg::VERSION")

all:

redhat: redhatprep rpm
redhatprep:
	# Install everything needed for the command which sets VER above
	rpm --quiet -q ruby || sudo yum install ruby
	# And the package which contains the rpmbuild command
	rpm --quiet -q rpm-build || sudo yum install rpm-build
rpm: tpkg.spec
	#
	# Create package file structure in build root
	#
	rm -rf $(BUILDROOT)
	mkdir -p $(BUILDROOT)/usr/bin
	cp -p tpkg $(BUILDROOT)/usr/bin
	chmod 555 $(BUILDROOT)/usr/bin/tpkg
	cp -p gem2tpkg $(BUILDROOT)/usr/bin
	chmod 555 $(BUILDROOT)/usr/bin/gem2tpkg
	mkdir -p $(BUILDROOT)/etc/profile.d
	cp -p tpkg_profile.sh $(BUILDROOT)/etc/profile.d
	chmod 755 $(BUILDROOT)/etc/profile.d/tpkg_profile.sh
	mkdir -p $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/tpkg
	cp -p tpkg.rb $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/tpkg.rb
	cp -p versiontype.rb $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/tpkg/versiontype.rb
	cp -p deployer.rb $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/tpkg/deployer.rb
	cp -p thread_pool.rb $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/tpkg/thread_pool.rb
	find thirdparty -name .svn -prune -o -print | cpio -pdum $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/tpkg
	mkdir -p $(BUILDROOT)/usr/share/man/man1
	cp -p tpkg.1 $(BUILDROOT)/usr/share/man/man1
	mkdir -p $(BUILDROOT)/etc
	cp -p tpkg.conf $(BUILDROOT)/etc/tpkg.conf
	chmod 644 $(BUILDROOT)/etc/tpkg.conf
	mkdir -p $(BUILDROOT)/etc/tpkg
	cp -p dhparams $(BUILDROOT)/etc/tpkg/dhparams
	chmod 644 $(BUILDROOT)/etc/tpkg/dhparams
	mkdir -p $(BUILDROOT)/etc/cron.d
	cp tpkg_cron $(BUILDROOT)/etc/cron.d/tpkg
	chmod 444 $(BUILDROOT)/etc/cron.d/tpkg
	mkdir -p $(BUILDROOT)/home/t/var/tpkg/externals
	cp -p externals/* $(BUILDROOT)/home/t/var/tpkg/externals
	chmod 755 $(BUILDROOT)/home/t/var/tpkg/externals/*
	#
	# Now build the package
	#
	sed 's/VER/$(VER)/' tpkg.spec > tpkg.spec_withversion
	rpmbuild -bb --buildroot $(BUILDROOT) tpkg.spec_withversion
	rm -rf $(BUILDROOT)

debian: debianprep deb
debianprep:
	# Install everything needed for the command which sets VER above
	sudo apt-get --no-upgrade --quiet install ruby libopenssl-ruby rubygems facter
deb: control
	sudo rm -rf $(BUILDROOT)
	mkdir -p $(BUILDROOT)/DEBIAN
	grep -v '^#' control | sed 's/VER/$(VER)/' > $(BUILDROOT)/DEBIAN/control
	mkdir -p $(BUILDROOT)/usr/bin
	cp -p tpkg $(BUILDROOT)/usr/bin
	chmod 555 $(BUILDROOT)/usr/bin/tpkg
	cp -p gem2tpkg $(BUILDROOT)/usr/bin
	chmod 555 $(BUILDROOT)/usr/bin/gem2tpkg
	mkdir -p $(BUILDROOT)/etc/profile.d
	cp -p tpkg_profile.sh $(BUILDROOT)/etc/profile.d
	chmod 755 $(BUILDROOT)/etc/profile.d/tpkg_profile.sh
	mkdir -p $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg
	cp -p tpkg.rb $(BUILDROOT)/usr/local/lib/site_ruby/1.8
	chmod 444 $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg.rb
	cp -p versiontype.rb $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg/versiontype.rb
	cp -p deployer.rb $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg/deployer.rb
	cp -p thread_pool.rb $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg/thread_pool.rb
	find thirdparty -name .svn -prune -o -print | cpio -pdum $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg
	mkdir -p $(BUILDROOT)/usr/share/man/man1
	cp -p tpkg.1 $(BUILDROOT)/usr/share/man/man1
	mkdir -p $(BUILDROOT)/etc
	cp -p tpkg.conf $(BUILDROOT)/etc/tpkg.conf
	chmod 644 $(BUILDROOT)/etc/tpkg.conf
	mkdir -p $(BUILDROOT)/etc/tpkg
	cp -p dhparams $(BUILDROOT)/etc/tpkg/dhparams
	chmod 644 $(BUILDROOT)/etc/tpkg/dhparams
	mkdir -p $(BUILDROOT)/home/t/var/tpkg/externals
	cp -p externals/* $(BUILDROOT)/home/t/var/tpkg/externals
	chmod 755 $(BUILDROOT)/home/t/var/tpkg/externals/*
	sudo chown -R 0:0 $(BUILDROOT)
	dpkg --build $(BUILDROOT) tpkg-$(VER).deb
	sudo rm -rf $(BUILDROOT)

solaris: solarisprep sysvpkg
solarisprep:
	# Install everything needed for the command which sets VER above
	pkginfo -q CSWruby || sudo pkg-get -i ruby
	pkginfo -q CSWrubygems || sudo pkg-get -i rubygems
	pkginfo -q CSWfacter || sudo pkg-get -i facter
sysvpkg: pkginfo depend
	#
	# Create package file structure in build root
	#
	rm -rf $(BUILDROOT)
	mkdir -p $(BUILDROOT)/usr/bin
	cp -p tpkg $(BUILDROOT)/usr/bin
	mv $(BUILDROOT)/usr/bin/tpkg $(BUILDROOT)/usr/bin/tpkg.tmp
	cat $(BUILDROOT)/usr/bin/tpkg.tmp | sed 's,/usr/bin/ruby,/opt/csw/bin/ruby,' > $(BUILDROOT)/usr/bin/tpkg
	rm $(BUILDROOT)/usr/bin/tpkg.tmp
	chmod 555 $(BUILDROOT)/usr/bin/tpkg
	cp -p gem2tpkg $(BUILDROOT)/usr/bin
	mv $(BUILDROOT)/usr/bin/gem2tpkg $(BUILDROOT)/usr/bin/gem2tpkg.tmp
	cat $(BUILDROOT)/usr/bin/gem2tpkg.tmp | sed 's,/usr/bin/ruby,/opt/csw/bin/ruby,' > $(BUILDROOT)/usr/bin/gem2tpkg
	rm $(BUILDROOT)/usr/bin/gem2tpkg.tmp
	chmod 555 $(BUILDROOT)/usr/bin/gem2tpkg
	mkdir -p $(BUILDROOT)/etc/profile.d
	cp -p tpkg_profile.sh $(BUILDROOT)/etc/profile.d
	chmod 755 $(BUILDROOT)/etc/profile.d/tpkg_profile.sh
	mkdir -p $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg
	cp -p tpkg.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg.rb
	cp -p versiontype.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg/versiontype.rb
	cp -p deployer.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg/deployer.rb
	cp -p thread_pool.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg/thread_pool.rb
	find thirdparty -name .svn -prune -o -print | cpio -pdum $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg
	mkdir -p $(BUILDROOT)/usr/share/man/man1
	cp -p tpkg.1 $(BUILDROOT)/usr/share/man/man1
	mkdir -p $(BUILDROOT)/etc
	cp -p tpkg.conf $(BUILDROOT)/etc/tpkg.conf
	chmod 644 $(BUILDROOT)/etc/tpkg.conf
	mkdir -p $(BUILDROOT)/etc/tpkg
	cp -p dhparams $(BUILDROOT)/etc/tpkg/dhparams
	chmod 644 $(BUILDROOT)/etc/tpkg/dhparams
	mkdir -p $(BUILDROOT)/home/t/var/tpkg/externals
	cp -p externals/* $(BUILDROOT)/home/t/var/tpkg/externals
	chmod 755 $(BUILDROOT)/home/t/var/tpkg/externals/*
	#
	# Now build the package
	#
	rm -rf solbuild
	mkdir solbuild
	sed 's/%VER%/$(VER)/' pkginfo > solbuild/pkginfo
	echo "i pkginfo=./pkginfo" > solbuild/prototype
	cp depend solbuild/depend
	echo "i depend=./depend" >> solbuild/prototype
	cp postinstall.solaris solbuild/postinstall
	echo "i postinstall=./postinstall" >> solbuild/prototype
	cp postremove.solaris solbuild/postremove
	echo "i postremove=./postremove" >> solbuild/prototype
	# The tail +2 removes the first line, which is the base directory
	# and doesn't need to be included in the package.
	# The first sed just cleans up the directory names
	# The second sed tell pkgadd to not force our permissions on directories
	#  The $$ in that sed escapes the $ from make
	find $(BUILDROOT) | pkgproto | tail +2 | sed "s,$(BUILDROOT),," | sed '/^d/s/[^ ]* [^ ]* [^ ]*$$/? ? ?/' >> solbuild/prototype
	cd solbuild && pkgmk -r $(BUILDROOT) -d $(PWD)/solbuild
	pkgtrans solbuild ../OSStpkg-$(VER).pkg YPCtpkg
	rm -rf solbuild
	rm -rf $(BUILDROOT)

# It may seem odd to package tpkg with tpkg, but if users want to
# program against the tpkg library it is handy for them to be able to
# install and depend on the library along with other tpkgs.
# In order to reduce confusion this package does not contain any of the
# executables that go in the normal packages.
tpkgpkg: tpkg.xml
	rm -rf $(BUILDROOT)
	mkdir -p $(BUILDROOT)/root/home/t/ruby/lib/ruby/site_ruby/1.8/tpkg
	sed 's/VER/$(VER)/' tpkg.xml > $(BUILDROOT)/tpkg.xml
	cp -p tpkg.rb $(BUILDROOT)/root/home/t/ruby/lib/ruby/site_ruby/1.8
	cp -p versiontype.rb $(BUILDROOT)/root/home/t/ruby/lib/ruby/site_ruby/1.8/tpkg
	cp -p deployer.rb $(BUILDROOT)/root/home/t/ruby/lib/ruby/site_ruby/1.8/tpkg
	cp -p thread_pool.rb $(BUILDROOT)/root/home/t/ruby/lib/ruby/site_ruby/1.8/tpkg
	find thirdparty -name .svn -prune -o -print | cpio -pdum $(BUILDROOT)/root/home/t/ruby/lib/ruby/site_ruby/1.8/tpkg
	tpkg --make $(BUILDROOT)
	rm -rf $(BUILDROOT)

