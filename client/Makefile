VER=$(shell ruby -e "$$:.unshift('.'); require 'tpkg'; puts Tpkg::VERSION")

all:

redhat: rpmbuild-redhat rpm
rpmbuild-redhat:
	rpm --quiet -q rpm-build || yum -y install rpm-build
BUILDROOT=/var/tmp/tpkg-buildroot
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
	cp -p -r thirdparty $(BUILDROOT)/usr/lib/ruby/site_ruby/1.8/tpkg
	mkdir -p $(BUILDROOT)/etc
	cp -p tpkg.conf $(BUILDROOT)/etc/tpkg.conf
	chmod 644 $(BUILDROOT)/etc/tpkg.conf
	mkdir -p $(BUILDROOT)/etc/cron.d
	cp tpkg_cron $(BUILDROOT)/etc/cron.d/tpkg
	chmod 444 $(BUILDROOT)/etc/cron.d/tpkg
	#
	# Now build the package
	#
	sed 's/VER/$(VER)/' tpkg.spec > tpkg.spec_withversion
	rpmbuild -bb --buildroot $(BUILDROOT) tpkg.spec_withversion
	rm -rf $(BUILDROOT)

debian: control
	rm -rf $(BUILDROOT)
	mkdir -p $(BUILDROOT)/DEBIAN
	grep -v '^#' control | sed 's/VER/$(VER)/' > $(BUILDROOT)/DEBIAN/control
	mkdir -p $(BUILDROOT)/usr/bin
	cp -p tpkg $(BUILDROOT)/usr/bin
	chmod 555 $(BUILDROOT)/usr/bin/tpkg
	cp -p gem2tpkg $(BUILDROOT)/usr/bin
	chmod 555 $(BUILDROOT)/usr/bin/gem2tpkg
	mkdir -p $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg
	cp -p tpkg.rb $(BUILDROOT)/usr/local/lib/site_ruby/1.8
	chmod 444 $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg.rb
	cp -p versiontype.rb $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg/versiontype.rb
	cp -p deployer.rb $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg/deployer.rb
	cp -p thread_pool.rb $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg/thread_pool.rb
	cp -p -r thirdparty $(BUILDROOT)/usr/local/lib/site_ruby/1.8/tpkg
	mkdir -p $(BUILDROOT)/etc
	cp -p tpkg.conf $(BUILDROOT)/etc/tpkg.conf
	chmod 644 $(BUILDROOT)/etc/tpkg.conf
	sudo chown -R 0:0 $(BUILDROOT)
	dpkg --build $(BUILDROOT) tpkg-$(VER).deb
	rm -rf $(BUILDROOT)

solaris: pkginfo depend
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
	mkdir -p $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg
	cp -p tpkg.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg.rb
	cp -p versiontype.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg/versiontype.rb
	cp -p deployer.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg/deployer.rb
	cp -p thread_pool.rb $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg
	chmod 444 $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg/thread_pool.rb
	cp -p -r thirdparty $(BUILDROOT)/opt/csw/lib/ruby/site_ruby/1.8/tpkg
	mkdir -p $(BUILDROOT)/etc
	cp -p tpkg.conf $(BUILDROOT)/etc/tpkg.conf
	chmod 644 $(BUILDROOT)/etc/tpkg.conf
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
	pkgtrans solbuild OSStpkg-$(VER).pkg YPCtpkg
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
	cp -p -r thirdparty $(BUILDROOT)/root/home/t/ruby/lib/ruby/site_ruby/1.8/tpkg
	tpkg --make $(BUILDROOT)
	rm -rf $(BUILDROOT)

