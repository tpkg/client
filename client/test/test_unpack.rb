

#
# Test tpkg's ability to unpack packages
#

require File.dirname(__FILE__) + '/tpkgtest'

class TpkgUnpackTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    @tempoutdir = Tempdir.new("tempoutdir")  # temp dir that will automatically get deleted at end of test run
                                             # can be used for storing packages
    # Make up a package with both relocatable and non-relocatable
    # directory trees so that we can ensure both types are unpacked
    # properly.
    srcdir = Tempdir.new("srcdir")
    # The stock test package has a reloc directory we can use
    system("#{Tpkg::find_tar} -C #{TESTPKGDIR} --exclude .svn -cf - . | #{Tpkg::find_tar} -C #{srcdir} -xf -")
    # Then add a root directory
    FileUtils.mkdir_p(File.join(srcdir, 'root', 'etc'))
    File.open(File.join(srcdir, 'root', 'etc', 'rootfile'), 'w') do |file|
      file.puts "Hello"
    end
    @pkgfile = make_package(:output_directory => @tempoutdir, :source_directory => srcdir, :files => {'/etc/rootfile' => {'perms' => '0666'}}, :remove => ['posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
  end
  
  def test_unpack
    testbase = Tempdir.new("testbase")
    FileUtils.mkdir_p(File.join(testbase, 'home', 'tpkg'))
    tpkg = Tpkg.new(:file_system_root => testbase, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])
    assert_nothing_raised { tpkg.unpack(@pkgfile, PASSPHRASE) }
    # This file should have the default 0444 perms
    assert(File.exist?(File.join(testbase, 'home', 'tpkg', 'file')))
    assert_equal(0444, File.stat(File.join(testbase, 'home', 'tpkg', 'file')).mode & 07777)
    # This file should have the 0400 perms specified specifically for it in the stock test tpkg.xml
    assert(File.exist?(File.join(testbase, 'home', 'tpkg', 'encfile')))
    assert_equal(0400, File.stat(File.join(testbase, 'home', 'tpkg', 'encfile')).mode & 07777)
    assert_equal(IO.read(File.join(TESTPKGDIR, 'reloc', 'encfile')), IO.read(File.join(testbase, 'home', 'tpkg', 'encfile')))
    # This file should have the 0666 perms we specified above
    assert(File.exist?(File.join(testbase, 'etc', 'rootfile')))
    assert_equal(0666, File.stat(File.join(testbase, 'etc', 'rootfile')).mode & 07777)
    
    # Change the package base and unpack
    testbase2 = Tempdir.new("testbase2")
    tpkg2 = Tpkg.new(:file_system_root => testbase2, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])
    assert_nothing_raised { tpkg2.unpack(@pkgfile, PASSPHRASE) }
    # Check that the files from the package ended up in the right place
    assert(File.exist?(File.join(testbase2, 'home', 'tpkg', 'file')))
    
    FileUtils.rm_rf(testbase)
    FileUtils.rm_rf(testbase2)
    
    # Pass a nil passphrase to unpack and verify that it installs the
    # package, skipping the unencrypted files
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:file_system_root => testbase, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])
    assert_nothing_raised { tpkg.unpack(@pkgfile, nil) }
    # Check that the files from the package ended up in the right place
    assert(File.exist?(File.join(testbase, 'home', 'tpkg', 'file')))
    assert(!File.exist?(File.join(testbase, 'home', 'tpkg', 'encfile')))
    FileUtils.rm_rf(testbase)
    
    # Test permissions with no default permissions specified in tpkg.xml
    # The stock test package has default permissions specified, so start
    # with the -nofiles template which doesn't have default permissions.
    srcdir = Tempdir.new("srcdir")
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
    pkg = make_package(:change => { 'name' => 'a' }, :output_directory => @tempoutdir, :source_directory => srcdir, :files => {'etc/666file' => {'perms' => '0666'}, 'etc/400file' => {'perms' => '0400'}}, :remove => ['posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:file_system_root => testbase, :base => File.join('home', 'tpkg'), :sources => [pkg])
    # Standard umask settings are likely to be the same as the default
    # permissions, which would mask failure here.  Set an extreme umask
    # so that we know tpkg is enforcing the desired permissions.
    oldumask = File.umask
    File.umask(0)
    assert_nothing_raised { tpkg.unpack(pkg, nil) }
    File.umask(oldumask)
    # This file should have the 0666 perms we specified above
    assert_equal(0666, File.stat(File.join(testbase, 'home', 'tpkg', 'etc', '666file')).mode & 07777)
    # This file should have the default 0400 perms we specified above
    assert_equal(0400, File.stat(File.join(testbase, 'home', 'tpkg', 'etc', '400file')).mode & 07777)
    # This file should have the 0666 perms we set on the file itself
    assert_equal(0666, File.stat(File.join(testbase, 'home', 'tpkg', 'etc', 'nopermsfile')).mode & 07777)
    # This directory should have the default 0755 tpkg directory perms
    assert_equal(0755, File.stat(File.join(testbase, 'home', 'tpkg', 'etc')).mode & 07777)
    FileUtils.rm_f(pkg)
    FileUtils.rm_rf(testbase)


    # Test perms for default directory setting
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-dir-default.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
    FileUtils.mkdir_p(File.join(srcdir, 'reloc', 'dir1'))
    FileUtils.mkdir_p(File.join(srcdir, 'reloc', 'dir1', 'subdir1'))
    pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'dir_default' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
   
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
    # Standard umask settings are likely to be the same as the default
    # permissions, which would mask failure here.  Set an extreme umask
    # so that we know tpkg is enforcing the desired permissions.
    oldumask = File.umask
    File.umask(0)
    assert_nothing_raised { tpkg.unpack(pkg, nil) }
    File.umask(oldumask)
    # This dir should have the 0555 perms we specified in the tpkg-dir-default.xml file
    assert_equal(0555, File.stat(File.join(testbase, 'dir1')).mode & 07777)
    assert_equal(0555, File.stat(File.join(testbase, 'dir1', 'subdir1')).mode & 07777)
    FileUtils.rm_f(pkg)
    FileUtils.rm_rf(testbase)
    FileUtils.rm_rf(testroot)
    
    # Test that preinstall/postinstall are run at the right points
    #   Make up a package with scripts that create files so we can check timestamps
    # Also, test PS-476 tpkg should chdir to package unpack directory before calling pre/post/install/remove scripts
    srcdir = Tempdir.new("srcdir")
    # Include the stock test package contents
    system("#{Tpkg::find_tar} -C #{TESTPKGDIR} --exclude .svn -cf - . | #{Tpkg::find_tar} -C #{srcdir} -xf -")

    # Add some dummy file for testing relative path
    File.open(File.join(srcdir, "dummyfile"), 'w') do |file|
      file.puts("hello world")
    end

    # Then add scripts
    scriptfiles = {}
    ['preinstall', 'postinstall'].each do |script|
      File.open(File.join(srcdir, script), 'w') do |scriptfile|
        # We have each script write to a temporary file (so that we can
        # check the timestamp of that file to ensure proper ordering) and
        # print out the name of the file (just to aid debugging)
        tmpfile = Tempfile.new('tpkgtest_script')
        scriptfiles[script] = tmpfile
        scriptfile.puts('#!/bin/sh')
        # Test that tpkg set $TPKG_HOME before running the script
        scriptfile.puts('echo TPKG_HOME: \"$TPKG_HOME\"')
        scriptfile.puts('test -n "$TPKG_HOME" || exit 1')
        # Test that we had chdir'ed to package unpack directory
        scriptfile.puts('ls dummyfile || exit 1')
        scriptfile.puts("echo #{script} > #{tmpfile.path}")
        scriptfile.puts("echo #{script}: #{tmpfile.path}")
        scriptfile.puts('sleep 1')
      end
      File.chmod(0755, File.join(srcdir, script))
    end
    # Change name of package so that the file doesn't conflict with @pkgfile
    pkgfile = make_package(:output_directory => @tempoutdir, :source_directory => srcdir, :change => {'name' => 'scriptpkg'}, :remove => ['posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    # Install the script package
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkgfile])
    assert_nothing_raised { tpkg.unpack(pkgfile, PASSPHRASE) }
    # FIXME: Need a way to test that the package install occurred between the two scripts
    assert(File.stat(scriptfiles['preinstall'].path).mtime < File.stat(scriptfiles['postinstall'].path).mtime)
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkgfile)

    # Test init script handling
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
    # These packages have different init scripts of the same name
    (1..3).each do  | i |
      FileUtils.mkdir(File.join(srcdir, 'reloc', i.to_s))
      File.open(File.join(srcdir, 'reloc', i.to_s, "myinit"), 'w') do |file|
        file.puts('init script')
      end
    end
    pkg  = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg'  }, :source_directory => srcdir, :files => { File.join('1','myinit') => { 'init' => {} } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    pkg2 = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg2' }, :source_directory => srcdir, :files => { File.join('2','myinit') => { 'init' => {} } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    pkg3 = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg3' }, :source_directory => srcdir, :files => { File.join('3','myinit') => { 'init' => {} } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg,pkg2,pkg3])
    metadata  = Tpkg::metadata_from_package(pkg)
    metadata2 = Tpkg::metadata_from_package(pkg2)
    metadata3 = Tpkg::metadata_from_package(pkg3)
    begin
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

    rescue RuntimeError => e
      if e.message =~ /No init script support/
        warn "No init script support on this platform, init script handling will not be tested (#{e.message})"
      else
        raise
      end
    end
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)
    FileUtils.rm_f(pkg2)
    FileUtils.rm_f(pkg3)
    
    # Test crontab handling
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
    crontab_contents = '* * * * *  crontab'
    File.open(File.join(srcdir, 'reloc', 'mycrontab'), 'w') do |file|
      file.puts(crontab_contents)
    end
    pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'crontabpkg' }, :source_directory => srcdir, :files => { 'mycrontab' => { 'crontab' => {'user' => 'root'} } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    pkg2 = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'crontabpkg2' }, :source_directory => srcdir, :files => { 'mycrontab' => { 'crontab' => {'user' => 'root'} } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    pkg3 = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'crontabpkg3' }, :source_directory => srcdir, :files => { 'mycrontab' => { 'crontab' => {'user' => 'root'} } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg,pkg2,pkg3])
    metadata  = Tpkg::metadata_from_package(pkg)
    metadata2 = Tpkg::metadata_from_package(pkg2)
    metadata3 = Tpkg::metadata_from_package(pkg3)
    begin
      tpkg.install([pkg], PASSPHRASE)
      tpkg.crontab_destinations(metadata).each do |crontab, destination|
        if destination[:file]
          assert(File.file?(destination[:file]))
          assert(IO.read(destination[:file]).include?(crontab_contents))
        elsif destination[:link]
          assert(File.symlink?(destination[:link]))
          assert_equal(crontab, File.readlink(destination[:link]))
        end
      end
      # Test the handling of packages with conflicting crontabs.
      # Systems where we put the crontab into a user file should end up
      # with three copies of the crontab contents in that file.  Systems
      # where we link the crontab into a directory should end up with a
      # link ending in '1' and a link ending in '2'.
      tpkg.install([pkg2], PASSPHRASE)
      tpkg.install([pkg3], PASSPHRASE)
      tpkg.crontab_destinations(metadata2).each do |crontab, destination|
        if destination[:file]
          assert(File.file?(destination[:file]))
          contents = IO.read(destination[:file])
          # Strip out two copies of the crontab contents and verify that
          # it still contains the contents, as installing the additional
          # packages should add two copies of the contents to the file.
          contents.sub!(crontab_contents, '')
          contents.sub!(crontab_contents, '')
          assert(contents.include?(crontab_contents))
        elsif destination[:link]
          assert(File.symlink?(destination[:link] + '1'))
          assert_equal(crontab, File.readlink(destination[:link] + '1'))
          assert(File.symlink?(destination[:link] + '2'))
          assert_equal(crontab, File.readlink(destination[:link] + '2'))
        end
      end
    rescue RuntimeError => e
      if e.message =~ /No crontab support/
        warn "No crontab support on this platform, crontab handling will not be tested (#{e.message})"
      else
        raise
      end
    end
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)
    FileUtils.rm_f(pkg2)
    FileUtils.rm_f(pkg3)
    
    # Test external handling
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    extname = 'testext'
    extdata = "This is a test of an external hook\nwith multiple lines\nof data"
    pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'externalpkg' }, :externals => { extname => { 'data' => extdata } }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    # Make an external script which writes the data it receives to a temporary
    # file, so that we can verify the external script received the data
    # properly.
    exttmpfile = Tempfile.new('tpkgtest_external')
    externalsdir = File.join(testbase, 'var', 'tpkg', 'externals')
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
    assert_nothing_raised { tpkg.unpack(pkg, PASSPHRASE) }
    assert_equal(extdata, IO.read(exttmpfile.path))
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)
    
    # Test handling of external with datafile
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    extname = 'testext'
    # Create the datafile
    extdata = "This is a test of an external hook\nwith multiple lines\nof data from a datafile"
    File.open(File.join(srcdir, 'datafile'), 'w') do |file|
      file.print(extdata)
    end
    File.chmod(0755, File.join(srcdir, 'datafile'))
    pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'externalpkg' }, :externals => { extname => { 'datafile' => './datafile' } }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    # Make an external script which writes the data it receives to a temporary
    # file, so that we can verify the external script received the data
    # properly.
    exttmpfile = Tempfile.new('tpkgtest_external')
    externalsdir = File.join(testbase, 'var', 'tpkg', 'externals')
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
    assert_nothing_raised { tpkg.unpack(pkg, PASSPHRASE) }
    assert_equal(extdata, IO.read(exttmpfile.path))
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)
    
    # Test handling of external with datascript
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    extname = 'testext'
    # Create the datascript
    extdata = "This is a test of an external hook\nwith multiple lines\nof data from a datascript"
    File.open(File.join(srcdir, 'datascript'), 'w') do |file|
      file.puts('#!/bin/sh')
      # echo may or may not add a trailing \n depending on which echo we end
      # up, so use printf, which doesn't add things.
      file.puts("printf \"#{extdata}\"")
    end
    File.chmod(0755, File.join(srcdir, 'datascript'))
    pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'externalpkg' }, :externals => { extname => { 'datascript' => './datascript' } }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    # Make an external script which writes the data it receives to a temporary
    # file, so that we can verify the external script received the data
    # properly.
    exttmpfile = Tempfile.new('tpkgtest_external')
    externalsdir = File.join(testbase, 'var', 'tpkg', 'externals')
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
    assert_nothing_raised { tpkg.unpack(pkg, PASSPHRASE) }
    assert_equal(extdata, IO.read(exttmpfile.path))
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)
    
    # Test that existing files/directories' perm and ownership are preserved
    # unless specified by user
    testbase = Tempdir.new("testbase")
    FileUtils.mkdir_p(File.join(testbase, 'home', 'tpkg'))
    FileUtils.mkdir_p(File.join(testbase, 'etc'))
    tpkg = Tpkg.new(:file_system_root => testbase, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])
   
    # set up 2 existing files for the test
    File.open(File.join(testbase, 'home', 'tpkg', 'file'), 'w') do |file|
      file.puts "Hello"
    end
    #system("chmod 707 #{File.join(testbase, 'home', 'tpkg', 'file')}")
    File.chmod(0707, File.join(testbase, 'home', 'tpkg', 'file'))

    File.open(File.join(testbase, 'etc', 'rootfile'), 'w') do |file|
      file.puts "Hello"
    end
    File.chmod(0707, File.join(testbase, 'etc', 'rootfile'))
#    system("chmod 707 #{File.join(testbase, 'etc', 'rootfile')}")
   
    assert_nothing_raised { tpkg.unpack(@pkgfile, PASSPHRASE) }

    # This file should have the default 0444 perms
    # but the file already exists. So it should keep its old perms, which is 707
    assert(File.exist?(File.join(testbase, 'home', 'tpkg', 'file')))
    assert_equal(0707, File.stat(File.join(testbase, 'home', 'tpkg', 'file')).mode & 07777)

    # Even if this file exists, we specifically set the perm. So the perm should be set to what
    # we want
    assert(File.exist?(File.join(testbase, 'etc', 'rootfile')))
    assert_equal(0666, File.stat(File.join(testbase, 'etc', 'rootfile')).mode & 07777)
    FileUtils.rm_rf(testbase)
  end
  
  def test_install_init_scripts
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    create_metadata_file(File.join(srcdir, 'tpkg.xml'), :change => { 'name' => 'initpkg'  }, :files => { 'etc/init.d/initscript' => { 'init' => {} } })
    metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    FileUtils.rm_rf(srcdir)
    
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'))
      
    begin
      link = nil
      init_script = nil
      tpkg.init_links(metadata).each do |l, is|
        link = l
        init_script = is
      end
      
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
      assert_nothing_raised { tpkg.install_init_scripts(metadata) }
      # FIXME: look for warning in stderr
      assert(!File.exist?(link) && !File.symlink?(link))
      File.chmod(0755, File.dirname(link))
      
      # Running as root, permissions issues prevent link creation, exception raised
      # FIXME: I don't actually know of a way to trigger EACCES in this
      # situation when running as root, and we never run the unit tests as
      # root anyway.
    rescue RuntimeError => e
      if e.message =~ /No init script support/
        warn "No init script support on this platform, install_init_scripts will not be tested (#{e.message})"
      else
        raise
      end
    end
    
    FileUtils.rm_rf(testroot)
  end
  
  def test_install_crontabs
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    create_metadata_file(File.join(srcdir, 'tpkg.xml'), :change => { 'name' => 'cronpkg'  }, :files => { 'etc/cron.d/crontab' => { 'crontab' => {'user' => 'root'} } })
    metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    FileUtils.rm_rf(srcdir)
    
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'))
    
    crontab_contents = '* * * * *  crontab'
    FileUtils.mkdir_p(File.join(srcdir, 'reloc', 'etc/cron.d'))
    File.open(File.join(srcdir, 'reloc', 'etc/cron.d/crontab'), 'w') do |file|
      file.puts(crontab_contents)
    end
    
    begin
      crontab = nil
      destination = nil
      tpkg.crontab_destinations(metadata).each do |c, d|
        crontab = c
        destination = d
      end
      
      dest = destination[:link] || destination[:file]
      
      # Running as non-root, permissions issues prevent file creation, warning
      FileUtils.mkdir_p(File.dirname(dest))
      File.chmod(0000, File.dirname(dest))
      assert_nothing_raised { tpkg.install_crontabs(metadata) }
      # FIXME: look for warning in stderr
      assert(!File.exist?(dest) && !File.symlink?(dest))
      File.chmod(0755, File.dirname(dest))
      
      # Running as root, permissions issues prevent link creation, exception raised
      # FIXME: I don't actually know of a way to trigger EACCES in this
      # situation when running as root, and we never run the unit tests as
      # root anyway.
    rescue RuntimeError => e
      if e.message =~ /No crontab support/
        warn "No crontab support on this platform, install_crontabs will not be tested (#{e.message})"
      else
        raise
      end
    end
    
    FileUtils.rm_rf(testroot)
  end
  def test_install_crontab_link
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    create_metadata_file(File.join(srcdir, 'tpkg.xml'), :change => { 'name' => 'cronpkg'  }, :files => { 'etc/cron.d/crontab' => { 'crontab' => {} } })
    metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    FileUtils.rm_rf(srcdir)
    
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'))
    
    crontab = File.join(testbase, 'etc/cron.d/crontab')
    destination = {:link => File.join(testroot, 'etc/cron.d/crontab')}
    
    # Directory for link doesn't exist, directory and link are created
    tpkg.install_crontab_link(metadata, crontab, destination)
    assert(File.symlink?(destination[:link]))
    assert_equal(crontab, File.readlink(destination[:link]))
    
    # Link already exists, nothing is done
    sleep 2
    beforetime = File.lstat(destination[:link]).mtime
    tpkg.install_crontab_link(metadata, crontab, destination)
    assert(File.symlink?(destination[:link]))
    assert_equal(crontab, File.readlink(destination[:link]))
    assert_equal(beforetime, File.lstat(destination[:link]).mtime)
    
    # Existing files or links up to 8 already exist, link created with appropriate suffix
    File.delete(destination[:link])
    File.symlink('somethingelse', destination[:link])
    0.upto(8) do |i|
      File.delete(destination[:link] + i.to_s) if (i != 0)
      File.symlink('somethingelse', destination[:link] + i.to_s)
      tpkg.install_crontab_link(metadata, crontab, destination)
      assert(File.symlink?(destination[:link] + (i + 1).to_s))
      assert_equal(crontab, File.readlink(destination[:link] + (i + 1).to_s))
    end
    
    # Existing files or links up to 9 already exist, exception raised
    File.delete(destination[:link] + '9')
    File.symlink('somethingelse', destination[:link] + '9')
    assert_raise(RuntimeError) { tpkg.install_crontab_link(metadata, crontab, destination) }
    
    FileUtils.rm_rf(testroot)
  end
  def test_install_crontab_file
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    create_metadata_file(File.join(srcdir, 'tpkg.xml'), :change => { 'name' => 'cronpkg'  }, :files => { 'etc/cron.d/crontab' => { 'crontab' => {'user' => 'root'} } })
    metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    FileUtils.rm_rf(srcdir)
    
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'))
    
    crontab = File.join(testbase, 'etc/cron.d/crontab')
    destination = {:file => File.join(testroot, 'etc/cron.d/crontab')}
    
    crontab_contents = '* * * * *  crontab'
    FileUtils.mkdir_p(File.dirname(crontab))
    File.open(crontab, 'w') do |file|
      file.puts(crontab_contents)
    end
    
    # Directory for file doesn't exist, directory and file are created
    tpkg.install_crontab_file(metadata, crontab, destination)
    assert(File.file?(destination[:file]))
    contents = IO.read(destination[:file])
    assert(contents.include?(crontab_contents))
    
    # File exists, contents added and permissions retained
    File.chmod(0707, destination[:file])
    tpkg.install_crontab_file(metadata, crontab, destination)
    assert(File.file?(destination[:file]))
    assert_equal(0707, File.stat(destination[:file]).mode & 07777)
    contents = IO.read(destination[:file])
    # Strip out a copy of the crontab contents and verify that it still
    # contains the contents, as installing the crontab a second time should
    # add another copy of the contents to the file.
    contents.sub!(crontab_contents, '')
    assert(contents.include?(crontab_contents))
    
    # FIXME: Should test rescue of EPERM, but we can't trigger it without root
    # privileges here to set the file ownership to another user.
    
    FileUtils.rm_rf(testroot)
  end
  
  def teardown
    FileUtils.rm_f(@pkgfile)
  end
end

