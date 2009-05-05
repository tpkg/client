#!/usr/bin/ruby -w

#
# Test tpkg's ability to unpack packages
#

require 'test/unit'
require 'tpkgtest'
require 'fileutils'

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
    system("#{Tpkg::find_tar} -C testpkg --exclude .svn -cf - . | #{Tpkg::find_tar} -C #{srcdir} -xf -")
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
    assert_equal(IO.read(File.join('testpkg', 'reloc', 'encfile')), IO.read(File.join(testbase, 'home', 'tpkg', 'encfile')))
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
    
    # Test that preinstall/postinstall are run at the right points
    #   Make up a package with scripts that create files so we can check timestamps
    srcdir = Tempdir.new("srcdir")
    # Include the stock test package contents
    system("#{Tpkg::find_tar} -C testpkg --exclude .svn -cf - . | #{Tpkg::find_tar} -C #{srcdir} -xf -")
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
    FileUtils.cp(File.join('testpkg', 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
    File.open(File.join(srcdir, 'reloc', 'myinit'), 'w') do |file|
      file.puts('init script')
    end
    pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg' }, :source_directory => srcdir, :files => { 'myinit' => { 'init' => true } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    pkg2 = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg2' }, :source_directory => srcdir, :files => { 'myinit' => { 'init' => true } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg,pkg2])
    metadata = Tpkg::metadata_from_package(pkg)
    metadata2 = Tpkg::metadata_from_package(pkg2)
    begin
      tpkg.install([pkg], PASSPHRASE)
      tpkg.init_links(metadata).each do |link, init_script|
        assert(File.symlink?(link))
        assert_equal(init_script, File.readlink(link))
      end
      # Test the handling of packages with conflicting init scripts.
      # The link should end up named with a '1' at the end.
      tpkg.install([pkg2], PASSPHRASE)
      tpkg.init_links(metadata2).each do |link, init_script|
        assert(File.symlink?(link + '1'))
        assert_equal(init_script, File.readlink(link + '1'))
      end
    rescue RuntimeError => e
      warn "No init script support on this platform, init script handling will not be tested (#{e.message})"
    end
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)
    FileUtils.rm_f(pkg2)
    
    # Test crontab handling
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join('testpkg', 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
    crontab_contents = '* * * * *  crontab'
    File.open(File.join(srcdir, 'reloc', 'mycrontab'), 'w') do |file|
      file.puts(crontab_contents)
    end
    pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'crontabpkg' }, :source_directory => srcdir, :files => { 'mycrontab' => { 'crontab' => {'user' => 'root'} } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    pkg2 = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'crontabpkg2' }, :source_directory => srcdir, :files => { 'mycrontab' => { 'crontab' => {'user' => 'root'} } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg,pkg2])
    metadata = Tpkg::metadata_from_package(pkg)
    metadata2 = Tpkg::metadata_from_package(pkg2)
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
      # with two copies of the crontab contents in that file.  Systems
      # where we link the crontab into a directory should end up with a
      # link ending in '1'.
      tpkg.install([pkg2], PASSPHRASE)
      tpkg.crontab_destinations(metadata2).each do |crontab, destination|
        if destination[:file]
          assert(File.file?(destination[:file]))
          contents = IO.read(destination[:file])
          # Strip out one copy of the crontab contents and verify that it
          # still contains the contents, as installing the second package
          # should add another copy of the contents to the file.
          contents.sub!(crontab_contents, '')
          assert(contents.include?(crontab_contents))
        elsif destination[:link]
          assert(File.symlink?(destination[:link] + '1'))
          assert_equal(crontab, File.readlink(destination[:link] + '1'))
        end
      end
    rescue RuntimeError => e
      warn "No crontab support on this platform, crontab handling will not be tested (#{e.message})"
    end
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)
    FileUtils.rm_f(pkg2)
  end
  
  def teardown
    FileUtils.rm_f(@pkgfile)
  end
end

