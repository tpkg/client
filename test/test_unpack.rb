#
# Test tpkg's ability to unpack packages
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))
require 'find'

class TpkgUnpackTests < Test::Unit::TestCase
  include TpkgTests

  def setup
    Tpkg::set_prompt(false)

    # temp dir that will automatically get deleted at end of test run, can be
    # used for storing packages
    @tempoutdir = Dir.mktmpdir('tempoutdir')
    # Make up a package with both relocatable and non-relocatable
    # directory trees so that we can ensure both types are unpacked
    # properly.
    Dir.mktmpdir('srcdir') do |srcdir|
      # The stock test package has a reloc directory we can use
      system("#{Tpkg::find_tar} -C #{TESTPKGDIR} --exclude .svn -cf - . | #{Tpkg::find_tar} -C #{srcdir} -xf -")
      # Then add a root directory
      FileUtils.mkdir_p(File.join(srcdir, 'root', 'etc'))
      File.open(File.join(srcdir, 'root', 'etc', 'rootfile'), 'w') do |file|
        file.puts "Hello"
      end
      @pkgfile = make_package(:output_directory => @tempoutdir, :source_directory => srcdir, :files => {'/etc/rootfile' => {'perms' => '0666'}})
    end

    # Pretend to be an OS with init script support
    fact = Facter::Util::Fact.new('operatingsystem')
    fact.stubs(:value).returns('RedHat')
    Facter.stubs(:[]).returns(fact)
  end

  def test_unpack
    Dir.mktmpdir('testroot') do |testroot|
      FileUtils.mkdir_p(File.join(testroot, 'home', 'tpkg'))
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])
      assert_nothing_raised { tpkg.unpack(@pkgfile, :passphrase => PASSPHRASE) }
      # This file should have the default 0444 perms
      assert(File.exist?(File.join(testroot, 'home', 'tpkg', 'file')))
      assert_equal(0444, File.stat(File.join(testroot, 'home', 'tpkg', 'file')).mode & 07777)
      # This file should have the 0400 perms specified specifically for it in the stock test tpkg.xml
      assert(File.exist?(File.join(testroot, 'home', 'tpkg', 'encfile')))
      assert_equal(0400, File.stat(File.join(testroot, 'home', 'tpkg', 'encfile')).mode & 07777)
      assert_equal(IO.read(File.join(TESTPKGDIR, 'reloc', 'encfile')), IO.read(File.join(testroot, 'home', 'tpkg', 'encfile')))
      # This file should have the 0666 perms we specified above
      assert(File.exist?(File.join(testroot, 'etc', 'rootfile')))
      assert_equal(0666, File.stat(File.join(testroot, 'etc', 'rootfile')).mode & 07777)
    end

    # Change the package base and unpack
    Dir.mktmpdir('testroot2') do |testroot2|
      tpkg2 = Tpkg.new(:file_system_root => testroot2, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])
      assert_nothing_raised { tpkg2.unpack(@pkgfile, :passphrase => PASSPHRASE) }
      # Check that the files from the package ended up in the right place
      assert(File.exist?(File.join(testroot2, 'home', 'tpkg', 'file')))
    end

    # Pass a nil passphrase to unpack and verify that it installs the
    # package, skipping the unencrypted files
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])
      assert_nothing_raised { tpkg.unpack(@pkgfile) }
      # Check that the files from the package ended up in the right place
      assert(File.exist?(File.join(testroot, 'home', 'tpkg', 'file')))
      assert(!File.exist?(File.join(testroot, 'home', 'tpkg', 'encfile')))
    end

    # Test permissions with no default permissions specified in tpkg.xml
    # The stock test package has default permissions specified, so start
    # with the -nofiles template which doesn't have default permissions.
    pkg = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc', 'etc'))
      # Set non-standard permissions on the directory so that we can
      # ensure that the default permissions are applied by tpkg
      File.chmod(0775, File.join(srcdir, 'reloc', 'etc'))
      File.open(File.join(srcdir, 'reloc', 'etc', '666file'), 'w') do |file|
        file.puts "Hello"
      end
      File.open(File.join(srcdir, 'reloc', 'etc', '400file'), 'w') do |file|
        file.puts "Hello"
      end
      File.open(File.join(srcdir, 'reloc', 'etc', 'nopermsfile'), 'w') do |file|
        file.puts "Hello"
      end
      # Set some crazy perms on this file so that we can be sure they
      # are preserved (there are no default permissions for files)
      File.chmod(0666, File.join(srcdir, 'reloc', 'etc', 'nopermsfile'))
      pkg = make_package(:change => { 'name' => 'no-default-perms' }, :output_directory => @tempoutdir, :source_directory => srcdir, :files => {'etc/666file' => {'perms' => '0666'}, 'etc/400file' => {'perms' => '0400'}})
    end
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
      # Standard umask settings might be the same as the default permissions,
      # which would mask failure here.  Set an extreme umask so that we know
      # tpkg is enforcing the desired permissions.
      oldumask = File.umask
      File.umask(0)
      assert_nothing_raised { tpkg.unpack(pkg) }
      File.umask(oldumask)
      # This file should have the 0666 perms we specified above
      assert_equal(0666, File.stat(File.join(testroot, 'home', 'tpkg', 'etc', '666file')).mode & 07777)
      # This file should have the default 0400 perms we specified above
      assert_equal(0400, File.stat(File.join(testroot, 'home', 'tpkg', 'etc', '400file')).mode & 07777)
      # This file should have the 0666 perms we set on the file itself
      assert_equal(0666, File.stat(File.join(testroot, 'home', 'tpkg', 'etc', 'nopermsfile')).mode & 07777)
      # This directory should have the default 0755 tpkg directory perms
      assert_equal(0755, File.stat(File.join(testroot, 'home', 'tpkg', 'etc')).mode & 07777)
    end
    FileUtils.rm_f(pkg)

    # Test file_defaults and dir_defaults usage in a package
    pkg = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-default-perms.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc', 'dir1'))
      File.open(File.join(srcdir, 'reloc', 'dir1', 'file1'), 'w') do |file|
        file.puts 'Testing file_defaults'
      end
      # Ensure that the file goes into the package with permissions different
      # from what we specify in the metadata so that we know tpkg set the
      # permissions requested by the metadata and not that the file just came
      # out of tar with the right permissions already.
      File.chmod(0640, File.join(srcdir, 'reloc', 'dir1', 'file1'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc', 'dir1', 'subdir1'))
      File.chmod(0750, File.join(srcdir, 'reloc', 'dir1', 'subdir1'))
      pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'default-perms' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
      # Standard umask settings might be the same as the default permissions,
      # which would mask failure here.  Set an extreme umask so that we know
      # tpkg is enforcing the desired permissions.
      oldumask = File.umask
      File.umask(0)
      assert_nothing_raised { tpkg.unpack(pkg) }
      File.umask(oldumask)
      # This file should have the 0444 perms we specified in the
      # tpkg-default-perms.xml file
      assert_equal(0444, File.stat(File.join(testbase, 'dir1', 'file1')).mode & 07777)
      # These directories should have the 0555 perms we specified
      assert_equal(0555, File.stat(File.join(testbase, 'dir1')).mode & 07777)
      assert_equal(0555, File.stat(File.join(testbase, 'dir1', 'subdir1')).mode & 07777)
      # The mktmpdir cleanup process doesn't seem to like cleaning up
      # non-writeable directories and links.  Note that any assertion failures
      # will cause this to get skipped.  So if you start getting permission
      # errors from the cleanup process look to see if you might have caused
      # an assertion to fail.
      Find.find(testroot) do |f|
        if File.symlink?(f)
          begin
            File.lchmod(0700, f)
          rescue NotImplementedError
          end
        else
          File.chmod(0700, f)
        end
      end
    end
    FileUtils.rm_f(pkg)

    # Test that applying standard default permissions works in the face of
    # symlinks in the package
    pkg = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
      # Broken link to ensure that nothing attempts to traverse the link and
      # fails as a result
      File.symlink('/path/to/nowhere', File.join(srcdir, 'reloc', 'brokenlink'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc', 'dir'))
      File.symlink('dir', File.join(srcdir, 'reloc', 'dirlink'))
      File.open(File.join(srcdir, 'reloc', 'file'), 'w') do |file|
        file.puts 'Hello'
      end
      # Set some crazy perms on this file so that we can be sure they
      # are preserved (there are no default permissions for files)
      File.chmod(0777, File.join(srcdir, 'reloc', 'file'))
      File.symlink('file', File.join(srcdir, 'reloc', 'filelink'))
      pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'no-default-perms-with-links' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
      assert_nothing_raised { tpkg.unpack(pkg) }
      assert_equal(0777, File.stat(File.join(testbase, 'file')).mode & 07777)
      assert_equal(Tpkg::DEFAULT_DIR_PERMS, File.stat(File.join(testbase, 'dir')).mode & 07777)
    end
    FileUtils.rm_f(pkg)

    # Test that applying specified default permissions works in the face of
    # symlinks in the package
    pkg = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-default-perms.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
      # Broken link to ensure that nothing attempts to traverse the link and
      # fails as a result
      File.symlink('/path/to/nowhere', File.join(srcdir, 'reloc', 'brokenlink'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc', 'dir'))
      File.symlink('dir', File.join(srcdir, 'reloc', 'dirlink'))
      File.open(File.join(srcdir, 'reloc', 'file'), 'w') do |file|
        file.puts 'Hello'
      end
      File.chmod(0777, File.join(srcdir, 'reloc', 'file'))
      File.symlink('file', File.join(srcdir, 'reloc', 'filelink'))
      pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'default-perms-with-links' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
      assert_nothing_raised { tpkg.unpack(pkg) }
      assert_equal(0444, File.stat(File.join(testbase, 'file')).mode & 07777)
      assert_equal(0555, File.stat(File.join(testbase, 'dir')).mode & 07777)
      begin
        # Test to see if lchmod is implemented on this platform.  If not then
        # tpkg won't have been able to use it and we can't check if it worked.
        lchmodtestfile = Tempfile.new('lchmodtest')
        File.lchmod(0555, lchmodtestfile.path)
        # If that didn't raise an exception then we can proceed with
        # assertions related to lchmod
        assert_equal(0444, File.lstat(File.join(testbase, 'brokenlink')).mode & 07777)
        assert_equal(0444, File.lstat(File.join(testbase, 'filelink')).mode & 07777)
        assert_equal(0444, File.lstat(File.join(testbase, 'dirlink')).mode & 07777)
      rescue NotImplementedError
        warn "lchmod not available on this platform, link permissions not tested"
      end
      # The mktmpdir cleanup process doesn't seem to like cleaning up
      # non-writeable directories and links.  Note that any assertion failures
      # will cause this to get skipped.  So if you start getting permission
      # errors from the cleanup process look to see if you might have caused
      # an assertion to fail.
      Find.find(testroot) do |f|
        if File.symlink?(f)
          begin
            File.lchmod(0700, f)
          rescue NotImplementedError
          end
        else
          File.chmod(0700, f)
        end
      end
    end
    FileUtils.rm_f(pkg)

    # Test that symlinks are not followed when applying permissions to
    # specific files
    pkg = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
      # Broken link to ensure that nothing attempts to traverse the link and
      # fails as a result
      File.symlink('/path/to/nowhere', File.join(srcdir, 'reloc', 'brokenlink'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc', 'dir'))
      File.symlink('dir', File.join(srcdir, 'reloc', 'dirlink'))
      File.open(File.join(srcdir, 'reloc', 'file'), 'w') do |file|
        file.puts 'Hello'
      end
      File.chmod(0400, File.join(srcdir, 'reloc', 'file'))
      File.symlink('file', File.join(srcdir, 'reloc', 'filelink'))
      pkg = make_package(:change => { 'name' => 'specific-perms-with-links' }, :files => {'brokenlink' => {'perms' => '0555'}, 'dirlink' => {'perms' => '0770'}, 'filelink' => {'perms' => '0666'}}, :source_directory => srcdir, :output_directory => @tempoutdir, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
      assert_nothing_raised { tpkg.unpack(pkg) }
      assert_equal(Tpkg::DEFAULT_DIR_PERMS, File.stat(File.join(testbase, 'dir')).mode & 07777)
      assert_equal(0400, File.stat(File.join(testbase, 'file')).mode & 07777)
      begin
        # Test to see if lchmod is implemented on this platform.  If not then
        # tpkg won't have been able to use it and we can't check if it worked.
        lchmodtestfile = Tempfile.new('lchmodtest')
        File.lchmod(0555, lchmodtestfile.path)
        # If that didn't raise an exception then we can proceed with
        # assertions related to lchmod
        assert_equal(0555, File.lstat(File.join(testbase, 'brokenlink')).mode & 07777)
        assert_equal(0666, File.lstat(File.join(testbase, 'filelink')).mode & 07777)
        assert_equal(0770, File.lstat(File.join(testbase, 'dirlink')).mode & 07777)
      rescue NotImplementedError
        warn "lchmod not available on this platform, link permissions not tested"
      end
    end
    FileUtils.rm_f(pkg)

    # Test that preinstall/postinstall are run at the right points
    #   Make up a package with scripts that create files so we can check timestamps
    # Also, test that tpkg will chdir to package unpack directory before
    # calling pre/post/install/remove scripts
    scriptfiles = {}
    pkgfile = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      # Include the stock test package contents
      system("#{Tpkg::find_tar} -C #{TESTPKGDIR} --exclude .svn -cf - . | #{Tpkg::find_tar} -C #{srcdir} -xf -")

      # Add some dummy file for testing relative path
      File.open(File.join(srcdir, "dummyfile"), 'w') do |file|
        file.puts("hello world")
      end

      # Then add scripts
      ['preinstall', 'postinstall'].each do |script|
        File.open(File.join(srcdir, script), 'w') do |scriptfile|
          # We have each script write to a temporary file (so that we can
          # check the timestamp of that file to ensure proper ordering) and
          # print out the name of the file (just to aid debugging)
          tmpfile = Tempfile.new('tpkgtest_script')
          scriptfiles[script] = tmpfile
          scriptfile.puts('#!/bin/sh')
          scriptfile.puts('set -e')
          # Test that tpkg set $TPKG_HOME before running the script
          scriptfile.puts('test -n "$TPKG_HOME"')
          # Test that we had chdir'ed to package unpack directory
          scriptfile.puts('test -e dummyfile')
          scriptfile.puts("echo #{script} > #{tmpfile.path}")
          scriptfile.puts('sleep 1')
        end
        File.chmod(0755, File.join(srcdir, script))
      end
      # Change name of package so that the file doesn't conflict with @pkgfile
      pkgfile = make_package(:output_directory => @tempoutdir, :source_directory => srcdir, :change => {'name' => 'scriptpkg'})
    end
    # Install the script package
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkgfile])
      assert_nothing_raised { tpkg.unpack(pkgfile, :passphrase => PASSPHRASE) }
      # FIXME: Need a way to test that the package install occurred between the two scripts
      assert(File.stat(scriptfiles['preinstall'].path).mtime < File.stat(scriptfiles['postinstall'].path).mtime)
    end
    FileUtils.rm_f(pkgfile)

    # Test init script handling
    pkg = nil
    pkg2 = nil
    pkg3 = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
      # These packages have different init scripts of the same name
      (1..3).each do  | i |
        FileUtils.mkdir(File.join(srcdir, 'reloc', i.to_s))
        File.open(File.join(srcdir, 'reloc', i.to_s, "myinit"), 'w') do |file|
          file.puts('init script')
        end
      end
      pkg  = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg'  }, :source_directory => srcdir, :files => { File.join('1','myinit') => { 'init' => {} } }, :remove => ['operatingsystem', 'architecture'])
      pkg2 = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg2' }, :source_directory => srcdir, :files => { File.join('2','myinit') => { 'init' => {} } }, :remove => ['operatingsystem', 'architecture'])
      pkg3 = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg3' }, :source_directory => srcdir, :files => { File.join('3','myinit') => { 'init' => {} } }, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg,pkg2,pkg3])
      metadata  = Tpkg::metadata_from_package(pkg)
      metadata2 = Tpkg::metadata_from_package(pkg2)
      metadata3 = Tpkg::metadata_from_package(pkg3)
      tpkg.install([pkg], PASSPHRASE)
      tpkg.init_links(metadata).each do |link, init_script|
        assert(File.symlink?(link))
        assert_equal(init_script, File.readlink(link))
      end
      # Test the handling of packages with conflicting init scripts.
      # We should end up with a link named with a '1' at the end and a
      # link named with a '2' at the end.
      tpkg.install([pkg2], PASSPHRASE)
      tpkg.install([pkg3], PASSPHRASE)
      tpkg.init_links(metadata2).each do |link, init_script|
        assert(File.symlink?(link + '1'))
        assert_equal(init_script, File.readlink(link + '1'))
      end
      tpkg.init_links(metadata3).each do |link, init_script|
        assert(File.symlink?(link + '2'))
        assert_equal(init_script, File.readlink(link + '2'))
      end
    end
    FileUtils.rm_f(pkg)
    FileUtils.rm_f(pkg2)
    FileUtils.rm_f(pkg3)

    # Test external handling
    extname = 'testext'
    extdata = "This is a test of an external hook\nwith multiple lines\nof data"
    pkg = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'externalpkg' }, :externals => { extname => { 'data' => extdata } }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      # Make an external script which writes the data it receives to a temporary
      # file, so that we can verify the external script received the data
      # properly.
      exttmpfile = Tempfile.new('tpkgtest_external')
      externalsdir = File.join(testroot, 'usr', 'lib', 'tpkg', 'externals')
      FileUtils.mkdir_p(externalsdir)
      extscript = File.join(externalsdir, extname)
      File.open(extscript, 'w') do |file|
        file.puts('#!/bin/sh')
        file.puts("cat >> #{exttmpfile.path}")
      end
      File.chmod(0755, extscript)
      # And run the test
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
      metadata  = Tpkg::metadata_from_package(pkg)
      assert_nothing_raised { tpkg.unpack(pkg, :passphrase => PASSPHRASE) }
      assert_equal(extdata, IO.read(exttmpfile.path))
    end
    FileUtils.rm_f(pkg)

    # Test handling of external with datafile
    extname = 'testext'
    extdata = "This is a test of an external hook\nwith multiple lines\nof data from a datafile"
    pkg = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      # Create the datafile
      File.open(File.join(srcdir, 'datafile'), 'w') do |file|
        file.print(extdata)
      end
      File.chmod(0755, File.join(srcdir, 'datafile'))
      pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'externalpkg' }, :externals => { extname => { 'datafile' => './datafile' } }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      # Make an external script which writes the data it receives to a temporary
      # file, so that we can verify the external script received the data
      # properly.
      exttmpfile = Tempfile.new('tpkgtest_external')
      externalsdir = File.join(testroot, 'usr', 'lib', 'tpkg', 'externals')
      FileUtils.mkdir_p(externalsdir)
      extscript = File.join(externalsdir, extname)
      File.open(extscript, 'w') do |file|
        file.puts('#!/bin/sh')
        file.puts("cat > #{exttmpfile.path}")
      end
      File.chmod(0755, extscript)
      # And run the test
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
      metadata  = Tpkg::metadata_from_package(pkg)
      assert_nothing_raised { tpkg.unpack(pkg, :passphrase => PASSPHRASE) }
      assert_equal(extdata, IO.read(exttmpfile.path))
    end
    FileUtils.rm_f(pkg)

    # Test handling of external with datascript
    extname = 'testext'
    extdata = "This is a test of an external hook\nwith multiple lines\nof data from a datascript"
    pkg = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      # Create the datascript
      File.open(File.join(srcdir, 'datascript'), 'w') do |file|
        file.puts('#!/bin/sh')
        # echo may or may not add a trailing \n depending on which echo we end
        # up, so use printf, which doesn't add things.
        file.puts("printf \"#{extdata}\"")
      end
      File.chmod(0755, File.join(srcdir, 'datascript'))
      pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'externalpkg' }, :externals => { extname => { 'datascript' => './datascript' } }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      # Make an external script which writes the data it receives to a temporary
      # file, so that we can verify the external script received the data
      # properly.
      exttmpfile = Tempfile.new('tpkgtest_external')
      externalsdir = File.join(testroot, 'usr', 'lib', 'tpkg', 'externals')
      FileUtils.mkdir_p(externalsdir)
      extscript = File.join(externalsdir, extname)
      File.open(extscript, 'w') do |file|
        file.puts('#!/bin/sh')
        file.puts("cat > #{exttmpfile.path}")
      end
      File.chmod(0755, extscript)
      # And run the test
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
      metadata  = Tpkg::metadata_from_package(pkg)
      assert_nothing_raised { tpkg.unpack(pkg, :passphrase => PASSPHRASE) }
      assert_equal(extdata, IO.read(exttmpfile.path))
    end
    FileUtils.rm_f(pkg)

    # Test that existing files/directories' perm and ownership are preserved
    # unless specified by user
    Dir.mktmpdir('testroot') do |testroot|
      FileUtils.mkdir_p(File.join(testroot, 'home', 'tpkg'))
      FileUtils.mkdir_p(File.join(testroot, 'etc'))
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])

      # set up 2 existing files for the test
      File.open(File.join(testroot, 'home', 'tpkg', 'file'), 'w') do |file|
        file.puts "Hello"
      end
      #system("chmod 707 #{File.join(testroot, 'home', 'tpkg', 'file')}")
      File.chmod(0707, File.join(testroot, 'home', 'tpkg', 'file'))

      File.open(File.join(testroot, 'etc', 'rootfile'), 'w') do |file|
        file.puts "Hello"
      end
      File.chmod(0707, File.join(testroot, 'etc', 'rootfile'))
  #    system("chmod 707 #{File.join(testroot, 'etc', 'rootfile')}")

      assert_nothing_raised { tpkg.unpack(@pkgfile, :passphrase => PASSPHRASE) }

      # This file should have the default 0444 perms
      # but the file already exists. So it should keep its old perms, which is 707
      assert(File.exist?(File.join(testroot, 'home', 'tpkg', 'file')))
      assert_equal(0707, File.stat(File.join(testroot, 'home', 'tpkg', 'file')).mode & 07777)

      # Even if this file exists, we specifically set the perm. So the perm should be set to what
      # we want
      assert(File.exist?(File.join(testroot, 'etc', 'rootfile')))
      assert_equal(0666, File.stat(File.join(testroot, 'etc', 'rootfile')).mode & 07777)
    end
  end

  # Test that the unpack method calls install_crontabs as appropriate
  def test_unpack_install_crontabs
    # FIXME
  end

  # Check that if a config file already existed in the system, then we don't
  # overwrite it. Instead we save the new one with a .tpkgnew extension.
  def test_config_files_handling
    pkgfile = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      # The stock test package has a reloc directory we can use
      system("#{Tpkg::find_tar} -C #{TESTPKGDIR} --exclude .svn -cf - . | #{Tpkg::find_tar} -C #{srcdir} -xf -")
      # Then add some configuration files
      FileUtils.mkdir_p(File.join(srcdir, 'root'))
      ['conf1', 'conf2'].each do |conf|
        File.open(File.join(srcdir, 'root', conf), 'w') do |file|
          file.puts conf
        end
      end
      pkgfile = make_package(:output_directory => @tempoutdir, :source_directory => srcdir,
                              :files => {'/conf1' => {'config' => true}, '/conf2' => {'config' => true}})
    end

    Dir.mktmpdir('testroot') do |testroot|
      # Create an existing configuration file
      File.open(File.join(testroot, 'conf1'), 'w') do |file|
        file.puts "Existing conf file"
      end

      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])
      assert_nothing_raised { tpkg.unpack(pkgfile, :passphrase => PASSPHRASE) }
      assert(File.exists?(File.join(testroot, 'conf1.tpkgnew')))
      assert(!File.exists?(File.join(testroot, 'conf2.tpkgnew')))
    end
  end

  def test_install_init_scripts
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(File.join(srcdir, 'tpkg.xml'), :change => { 'name' => 'initpkg'  }, :files => { 'etc/init.d/initscript' => { 'init' => {} } })
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end

    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'))

      link = nil
      init_script = nil
      tpkg.init_links(metadata).each do |l, is|
        link = l
        init_script = is
      end

      # init_links returns an empty list on platforms where tpkg doesn't have
      # init script support
      if link
        # Directory for link doesn't exist, directory and link are created
        tpkg.install_init_scripts(metadata)
        assert(File.symlink?(link))
        assert_equal(init_script, File.readlink(link))

        # Link already exists, nothing is done
        sleep 2
        beforetime = File.lstat(link).mtime
        tpkg.install_init_scripts(metadata)
        assert(File.symlink?(link))
        assert_equal(init_script, File.readlink(link))
        assert_equal(beforetime, File.lstat(link).mtime)

        # Existing files or links up to 8 already exist, link created with appropriate suffix
        File.delete(link)
        File.symlink('somethingelse', link)
        0.upto(8) do |i|
          File.delete(link + i.to_s) if (i != 0)
          File.symlink('somethingelse', link + i.to_s)
          tpkg.install_init_scripts(metadata)
          assert(File.symlink?(link + (i + 1).to_s))
          assert_equal(init_script, File.readlink(link + (i + 1).to_s))
        end

        # Existing files or links up to 9 already exist, exception raised
        File.delete(link + '9')
        File.symlink('somethingelse', link + '9')
        assert_raise(RuntimeError) { tpkg.install_init_scripts(metadata) }

        # Running as non-root, permissions issues prevent link creation, warning
        FileUtils.rm(Dir.glob(link + '*'))
        File.chmod(0000, File.dirname(link))
        # assert_nothing_raised { tpkg.install_init_scripts(metadata) }
        tpkg.install_init_scripts(metadata)
        # FIXME: look for warning in stderr
        assert(!File.exist?(link) && !File.symlink?(link))
        File.chmod(0755, File.dirname(link))

        # Running as root, permissions issues prevent link creation, exception raised
        # FIXME: I don't actually know of a way to trigger EACCES in this
        # situation when running as root, and we never run the unit tests as
        # root anyway.
      end
    end
  end
  def test_install_init_script
    # FIXME
  end

  def test_run_preinstall
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'))

      Dir.mktmpdir('test_run_preinstall') do |workdir|
        FileUtils.mkdir(File.join(workdir, 'tpkg'))

        # workdir/preinstall doesn't exist, nothing done
        assert_nothing_raised { tpkg.run_preinstall('mypkg.tpkg', workdir) }

        # Now test when preinstall does exist
        outputfile = Tempfile.new('test_run_preinstall')
        File.open(File.join(workdir, 'tpkg', 'preinstall'), 'w') do |file|
          file.puts '#!/bin/sh'
          file.puts "echo preinstall >> #{outputfile.path}"
          file.puts "cat otherfile >> #{outputfile.path}"
        end
        File.chmod(0755, File.join(workdir, 'tpkg', 'preinstall'))
        File.open(File.join(workdir, 'tpkg', 'otherfile'), 'w') do |file|
          file.puts 'otherfile contents'
        end
        pwd = Dir.pwd
        r = tpkg.run_preinstall('mypkg.tpkg', workdir)
        # Verify that the script was run and the working directory was changed
        # such that the script's relative path to otherfile was valid.
        assert_match(/preinstall/, File.read(outputfile.path))
        assert_match(/otherfile contents/, File.read(outputfile.path))
        # Verify that our pwd was restored
        assert_equal(pwd, Dir.pwd)

        # Ensure that the user is warned of a non-executable script
        File.chmod(0644, File.join(workdir, 'tpkg', 'preinstall'))
        assert_raise(RuntimeError) { tpkg.run_preinstall('mypkg.tpkg', workdir) }
        # FIXME: need to capture stderr to confirm that a warning was displayed

        # Verify that by default run_preinstall raises an exception if the script
        # did not run succesfully
        File.open(File.join(workdir, 'tpkg', 'preinstall'), 'w') do |file|
          file.puts '#!/bin/sh'
          file.puts "exit 1"
        end
        File.chmod(0755, File.join(workdir, 'tpkg', 'preinstall'))
        assert_raise(RuntimeError) { tpkg.run_preinstall('mypkg.tpkg', workdir) }
        # And verify that our pwd was restored
        assert_equal(pwd, Dir.pwd)

        # Verify that run_preinstall only displays a warning if the script
        # did not run succesfully and the user specified the force option.
        tpkgforce = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :force => true)
        assert_nothing_raised { tpkg.run_postinstall('mypkg.tpkg', workdir) }
        # FIXME: need to capture stderr to confirm that a warning was displayed
        # And verify that our pwd was restored
        assert_equal(pwd, Dir.pwd)
      end
    end
  end

  def test_run_postinstall
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'))

      Dir.mktmpdir('test_run_postinstall') do |workdir|
        FileUtils.mkdir(File.join(workdir, 'tpkg'))

        # workdir/postinstall doesn't exist, nothing done
        assert_nothing_raised { tpkg.run_postinstall('mypkg.tpkg', workdir) }

        # Now test when postinstall does exist
        outputfile = Tempfile.new('test_run_postinstall')
        File.open(File.join(workdir, 'tpkg', 'postinstall'), 'w') do |file|
          file.puts '#!/bin/sh'
          file.puts "echo postinstall >> #{outputfile.path}"
          file.puts "cat otherfile >> #{outputfile.path}"
        end
        File.chmod(0755, File.join(workdir, 'tpkg', 'postinstall'))
        File.open(File.join(workdir, 'tpkg', 'otherfile'), 'w') do |file|
          file.puts 'otherfile contents'
        end
        pwd = Dir.pwd
        r = tpkg.run_postinstall('mypkg.tpkg', workdir)
        # Verify that the script was run and the working directory was changed
        # such that the script's relative path to otherfile was valid.
        assert_match(/postinstall/, File.read(outputfile.path))
        assert_match(/otherfile contents/, File.read(outputfile.path))
        # Verify that run_postinstall returns 0 if the script ran succesfully
        assert_equal(0, r)
        # Verify that our pwd was restored
        assert_equal(pwd, Dir.pwd)

        # Ensure that the user is warned of a non-executable script
        File.chmod(0644, File.join(workdir, 'tpkg', 'postinstall'))
        tpkg.run_postinstall('mypkg.tpkg', workdir)
        # FIXME: need to capture stderr to confirm that a warning was displayed

        # Verify that run_postinstall returns Tpkg::POSTINSTALL_ERR if the script
        # did not run succesfully
        File.open(File.join(workdir, 'tpkg', 'postinstall'), 'w') do |file|
          file.puts '#!/bin/sh'
          file.puts "exit 1"
        end
        File.chmod(0755, File.join(workdir, 'tpkg', 'postinstall'))
        r = tpkg.run_postinstall('mypkg.tpkg', workdir)
        assert_equal(Tpkg::POSTINSTALL_ERR, r)
        # And verify that our pwd was restored
        assert_equal(pwd, Dir.pwd)
      end
    end
  end

  def test_run_externals_for_install
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'))
      tpkg_force = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :force => true)

      Dir.mktmpdir('run_externals_for_install') do |workdir|
        FileUtils.mkdir(File.join(workdir, 'tpkg'))

        pwd = Dir.pwd

        # No metadata[:externals], no problem
        FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(workdir, 'tpkg', 'tpkg.xml'))
        create_metadata_file(File.join(workdir, 'tpkg', 'tpkg.xml'), :change => { 'name' => 'run_externals_for_install'  })
        metadata = Metadata.new(File.read(File.join(workdir, 'tpkg', 'tpkg.xml')), 'xml')
        # value is nil
        metadata[:externals] = nil
        assert_nothing_raised { tpkg.run_externals_for_install(metadata, workdir) }
        assert_equal(pwd, Dir.pwd)
        # value is empty array
        metadata[:externals] = []
        assert_nothing_raised { tpkg.run_externals_for_install(metadata, workdir) }
        assert_equal(pwd, Dir.pwd)

        # Make up a package metadata with a mix of externals with inline data, a
        # datafile, and a datascript
        output = {}
        # Inline data
        inlineextname = 'inlineextname'
        inlinedata = "This is a test of an external hook\nwith multiple lines\nof data"
        output[inlineextname] = {}
        output[inlineextname][:data] = inlinedata
        # datafile
        fileextname = 'fileextname'
        filedata = "This is a test of an external hook\nwith multiple lines\nof data from a datafile"
        File.open(File.join(workdir, 'tpkg', 'datafile'), 'w') do |file|
          file.print(filedata)
        end
        output[fileextname] = {}
        output[fileextname][:data] = filedata
        # datascript
        scriptextname = 'scriptextname'
        scriptdata = "This is a test of an external hook\nwith multiple lines\nof data from a datascript"
        File.open(File.join(workdir, 'tpkg', 'datascript'), 'w') do |file|
          file.puts('#!/bin/sh')
          # echo may or may not add a trailing \n depending on which echo we end
          # up, so use printf, which doesn't add things.
          file.puts("printf \"#{scriptdata}\"")
        end
        File.chmod(0755, File.join(workdir, 'tpkg', 'datascript'))
        output[scriptextname] = {}
        output[scriptextname][:data] = scriptdata

        FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(workdir, 'tpkg', 'tpkg.xml'))
        create_metadata_file(File.join(workdir, 'tpkg', 'tpkg.xml'),
                             :change => { 'name' => 'run_externals_for_install'  },
                             :externals => { inlineextname => { 'data' => inlinedata },
                                             fileextname   => { 'datafile' => 'datafile' },
                                             scriptextname => { 'datascript' => './datascript' } })
        metadata = Metadata.new(File.read(File.join(workdir, 'tpkg', 'tpkg.xml')), 'xml')
        metadata[:filename] = 'test_run_externals_for_install'

        # We need a copy of these later
        original_externals = metadata[:externals].collect {|e| e.dup}

        # Make external scripts which write the data they receive to temporary
        # files so that we can verify that run_externals_for_install called
        # run_external with the proper parameters.
        externalsdir = File.join(testroot, 'usr', 'lib', 'tpkg', 'externals')
        FileUtils.mkdir_p(externalsdir)
        [inlineextname, fileextname, scriptextname].each do |extname|
          exttmpfile = Tempfile.new('tpkgtest_external')
          extscript = File.join(externalsdir, extname)
          File.open(extscript, 'w') do |file|
            file.puts('#!/bin/sh')
            file.puts("cat >> #{exttmpfile.path}")
          end
          File.chmod(0755, extscript)
          output[extname][:file] = exttmpfile
        end

        # Make sure the hash keys we expect are in metadata, so that when we check
        # later that they are gone we know run_externals_for_install removed them.
        fileext = metadata[:externals].find {|e| e[:name] == fileextname}
        assert(fileext.has_key?(:datafile))
        assert(!fileext.has_key?(:data))
        scriptext = metadata[:externals].find {|e| e[:name] == scriptextname}
        assert(scriptext.has_key?(:datascript))
        assert(!scriptext.has_key?(:data))

        tpkg.run_externals_for_install(metadata, workdir)

        assert_equal(pwd, Dir.pwd)
        output.each do |extname, extinfo|
          assert_equal(extinfo[:data], File.read(extinfo[:file].path))
        end

        # Make sure run_externals_for_install performed the expected switcheroo on
        # these hash entries
        fileext = metadata[:externals].find {|e| e[:name] == fileextname}
        assert(!fileext.has_key?(:datafile))
        assert(fileext.has_key?(:data))
        fileext = metadata[:externals].find {|e| e[:name] == scriptextname}
        assert(!scriptext.has_key?(:datascript))
        assert(scriptext.has_key?(:data))

        # Cleanup for another run
        output.each do |extname, extinfo|
          File.delete(extinfo[:file].path)
        end

        # externals_to_skip skipped
        tpkg.run_externals_for_install(metadata, workdir, [scriptext])
        assert_equal(pwd, Dir.pwd)
        output.each do |extname, extinfo|
          if extname != scriptextname
            assert_equal(extinfo[:data], File.read(extinfo[:file].path))
          else
            assert(!File.exist?(extinfo[:file].path))
          end
        end

        # Error reading datafile raises exception
        FileUtils.mv(File.join(workdir, 'tpkg', 'datafile'), File.join(workdir, 'datafile'))
        # Previous runs of run_externals_for_install using metadata will have
        # resulted in the data for the datafile and datascript externals being
        # read in and cached.  Revert to a copy where that hasn't been done yet so
        # this test is effective.
        metadata[:externals] = original_externals
        assert_raise(Errno::ENOENT) { tpkg.run_externals_for_install(metadata, workdir) }
        assert_equal(pwd, Dir.pwd)
        # Unless forced
        assert_nothing_raised { tpkg_force.run_externals_for_install(metadata, workdir) }
        # Put datafile back
        FileUtils.mv(File.join(workdir, 'datafile'), File.join(workdir, 'tpkg', 'datafile'))

        # Error running datascript raises exception
        FileUtils.mv(File.join(workdir, 'tpkg', 'datascript'), File.join(workdir, 'datascript'))
        # Same deal as last test, revert to unmodified copy
        metadata[:externals] = original_externals
        # RuntimeError in ruby 1.8 as popen doesn't fail, so the failure is
        # caught by our exit status check
        # Errno::ENOENT in ruby 1.9, raised by popen
        assert_raise(RuntimeError, Errno::ENOENT) { tpkg.run_externals_for_install(metadata, workdir) }
        assert_equal(pwd, Dir.pwd)
        # Unless forced
        assert_nothing_raised { tpkg_force.run_externals_for_install(metadata, workdir) }
        # Put datascript back
        FileUtils.mv(File.join(workdir, 'datascript'), File.join(workdir, 'tpkg', 'datascript'))

        # Check non-executable datascript permissions case too
        File.chmod(0644, File.join(workdir, 'tpkg', 'datascript'))
        metadata[:externals] = original_externals
        # RuntimeError in ruby 1.8 as popen doesn't fail, so the failure is
        # caught by our exit status check
        # Errno::EACCES in ruby 1.9, raised by popen
        assert_raise(RuntimeError, Errno::EACCES) { tpkg.run_externals_for_install(metadata, workdir) }
        assert_equal(pwd, Dir.pwd)
        # Unless forced
        assert_nothing_raised { tpkg_force.run_externals_for_install(metadata, workdir) }
        # Restore permissions
        File.chmod(0755, File.join(workdir, 'tpkg', 'datascript'))

        # Datascript that exits with error raises exception
        File.open(File.join(workdir, 'tpkg', 'datascript'), 'w') do |file|
          file.puts('#!/bin/sh')
          file.puts("exit 1")
        end
        File.chmod(0755, File.join(workdir, 'tpkg', 'datascript'))
        # Same deal as last test, revert to unmodified copy
        metadata[:externals] = original_externals
        assert_raise(RuntimeError) { tpkg.run_externals_for_install(metadata, workdir) }
        assert_equal(pwd, Dir.pwd)
        # Unless forced
        assert_nothing_raised { tpkg_force.run_externals_for_install(metadata, workdir) }
      end
    end
  end

  # This method only tests that we can save pkg metadata and pkg file metadata. The rest of the
  # unit tests for file metadata are in test_filemetadata.rb
  def test_save_package_metadata
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(File.join(srcdir, 'tpkg.xml'), :change => { 'name' => 'save_pkg_metadata'  })
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end

    Dir.mktmpdir('testroot') do |testroot|
      package_file = '/tmp/save_pkg_metadata-1.0-1.tpkg'
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'))

      Dir.mktmpdir('workdir') do |workdir|
        FileUtils.cp_r(File.join(TESTPKGDIR, 'reloc'), workdir)

        # FIXME: add in some test data for these hashes
        # generate files_info
        files_info = {}
        # generate checksums_of_decrypted_files
        checksums_of_decrypted_files = {}

        FileUtils.mkdir_p(File.join(workdir, 'tpkg'))
        File.open(File.join(File.join(workdir, 'tpkg', 'file_metadata.bin')), 'w') do |f|
          filemetadata = Tpkg::get_filemetadata_from_directory(workdir)
          data = filemetadata.to_hash.recursively{|h| h.stringify_keys }
          Marshal::dump(data, f)
        end

        tpkg.save_package_metadata(package_file, workdir, metadata, files_info, checksums_of_decrypted_files)

        # verify metadata and file_metadata are actually there
        assert(File.exists?(File.join(tpkg.instance_variable_get(:@metadata_directory), 'save_pkg_metadata-1.0-1', 'tpkg.yml')))
        assert(File.exists?(File.join(tpkg.instance_variable_get(:@metadata_directory), 'save_pkg_metadata-1.0-1', 'file_metadata.bin')))
      end
    end
  end

  def teardown
    Facter.unstub(:[])
    FileUtils.rm_f(@pkgfile)
    FileUtils.rm_rf(@tempoutdir)
  end
end

