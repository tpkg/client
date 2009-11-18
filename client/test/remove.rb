#!/usr/bin/ruby -w

#
# Test tpkg's ability to remove packages
#

require 'test/unit'
require File.dirname(__FILE__) + '/tpkgtest'
require 'fileutils'

class TpkgRemoveTests < Test::Unit::TestCase
  include TpkgTests

  def setup
    Tpkg::set_prompt(false)
    
    @tempoutdir = Tempdir.new("tempoutdir")  # temp dir that will automatically get deleted at end of test run
                                             # can be used for storing packages
  end
  
  def test_remove
    pkgfiles = []
    # Make up a couple of packages with different files in them so that
    # they don't conflict
    ['a', 'b'].each do |pkgname|
      srcdir = Tempdir.new("srcdir")
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc', 'directory'))
      File.open(File.join(srcdir, 'reloc', 'directory', pkgname), 'w') do |file|
        file.puts pkgname
      end
      pkgfiles << make_package(:output_directory => @tempoutdir, :change => {'name' => pkgname}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      FileUtils.rm_rf(srcdir)
    end
    
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => pkgfiles)
    
    tpkg.install(['a', 'b'], PASSPHRASE)
    
    assert_nothing_raised { tpkg.remove(['a']) }
    
    assert(!File.exist?(File.join(testbase, 'directory', 'a')))
    assert(File.exist?(File.join(testbase, 'directory', 'b')))
    
    assert_nothing_raised { tpkg.remove(['b']) }
    
    assert(!File.exist?(File.join(testbase, 'directory', 'b')))
    assert(!File.exist?(File.join(testbase, 'directory')))
    assert(File.exist?(File.join(testbase)))

    # Test that we can use package filename for remove
    tpkg.install(['a', 'b'], PASSPHRASE)
    filenames = pkgfiles.collect{ |pkgfile| File.basename(pkgfile)}
    assert_nothing_raised { tpkg.remove(filenames) }
    assert(!File.exist?(File.join(testbase, 'directory', 'a')))
    assert(!File.exist?(File.join(testbase, 'directory', 'b')))
    assert(!File.exist?(File.join(testbase, 'directory')))
    assert(File.exist?(File.join(testbase)))
    
    # Remove a file manually.  tpkg.remove should warn that the file
    # is missing but not abort.
    tpkg.install(['a'], PASSPHRASE)
    File.delete(File.join(testbase, 'directory', 'a'))
    puts "Missing file warning expected here:"
    assert_nothing_raised { tpkg.remove(['a']) }
    
    # Insert another file into the directory.  tpkg.remove should warn
    # that the directory isn't empty but not abort.
    tpkg.install(['a'], PASSPHRASE)
    File.open(File.join(testbase, 'directory', 'anotherfile'), 'w') do |file|
      file.puts 'junk'
    end
    assert_nothing_raised { tpkg.remove(['a']) }
    
    # Test removing all packages by passing no arguments to remove
    tpkg.install(['a', 'b'], PASSPHRASE)
    assert_nothing_raised { tpkg.remove }
    assert(!File.exist?(File.join(testbase, 'directory', 'a')))
    assert(!File.exist?(File.join(testbase, 'directory', 'b')))
    
    # Clean up
    pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
    FileUtils.rm_rf(testroot)
    
    # Test that preremove/postremove are run at the right points
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
    ['preremove', 'postremove'].each do |script|
      File.open(File.join(srcdir, script), 'w') do |scriptfile|
        # We have each script write to a temporary file (so that we can
        # check the timestamp of that file to ensure proper ordering) and
        # print out the name of the file (just to aid debugging)
        tmpfile = Tempfile.new('tpkgtest_script')
        scriptfiles[script] = tmpfile
        scriptfile.puts('#!/bin/sh')
        # Test that tpkg set $TPKG_HOME before running the script
        scriptfile.puts('echo TPKG_HOME: \"$TPKG_HOME\"')
        # Test that we had chdir'ed to package unpack directory
        scriptfile.puts('ls dummyfile || exit 1')
        scriptfile.puts('test -n "$TPKG_HOME" || exit 1')
        scriptfile.puts("echo #{script} > #{tmpfile.path}")
        scriptfile.puts("echo #{script}: #{tmpfile.path}")
        scriptfile.puts('sleep 1')
      end
      File.chmod(0755, File.join(srcdir, script))
    end
    # Change name of package so that the file doesn't conflict with @pkgfile
    pkgfile = make_package(:output_directory => @tempoutdir, :source_directory => srcdir, :change => {'name' => 'scriptpkg'}, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    # Install the script package
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkgfile])
    assert_nothing_raised { tpkg.install([pkgfile], PASSPHRASE) }
    assert_nothing_raised { tpkg.remove(['scriptpkg']) }
    # FIXME: Need a way to test that the package remove occurred between the two scripts
    assert(File.stat(scriptfiles['preremove'].path).mtime < File.stat(scriptfiles['postremove'].path).mtime)
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkgfile)
    
    # Test init script handling
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
    File.open(File.join(srcdir, 'reloc', 'myinit'), 'w') do |file|
      file.puts('init script')
    end
    pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg' }, :source_directory => srcdir, :files => { 'myinit' => { 'init' => {} } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    pkg2 = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg2' }, :source_directory => srcdir, :files => { 'myinit' => { 'init' => {} } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg,pkg2])
    testbase2 = File.join(testroot, 'home', 'tpkg2')
    FileUtils.mkdir_p(testbase2)
    tpkg2 = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg2'), :sources => [pkg,pkg2])
    metadata = Tpkg::metadata_xml_to_hash(Tpkg::metadata_from_package(pkg))
    metadata2 = Tpkg::metadata_xml_to_hash(Tpkg::metadata_from_package(pkg2))
    begin
      tpkg.install([pkg], PASSPHRASE)
      tpkg2.install([pkg2], PASSPHRASE)
      tpkg.remove(['initpkg'])
      tpkg.init_links(metadata).each do |link, init_script|
        assert(!File.exist?(link) && !File.symlink?(link))
      end
      # Test the handling of packages with conflicting init scripts.
      # The link should end up named with a '1' at the end.
      # Make sure it is still there after the removal of 'initpkg'
      tpkg2.init_links(metadata2).each do |link, init_script|
        assert(File.symlink?(link + '1'))
        assert_equal(init_script, File.readlink(link + '1'))
      end
      # Now remove 'initpkg2' and verify that it is gone
      tpkg2.remove(['initpkg2'])
      tpkg2.init_links(metadata2).each do |link, init_script|
        assert(!File.exist?(link + '1') && !File.symlink?(link + '1'))
      end
    rescue RuntimeError => e
      warn "No init script support on this platform, init script handling will not be tested (#{e.message})"
    end
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)
    FileUtils.rm_f(pkg2)
    
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
    FileUtils.rm_rf(srcdir)
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
    testbase = File.join(testroot, 'home', 'tpkg2')
    FileUtils.mkdir_p(testbase2)
    tpkg2 = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg2'), :sources => [pkg2])
    metadata = Tpkg::metadata_xml_to_hash(Tpkg::metadata_from_package(pkg))
    metadata2 = Tpkg::metadata_xml_to_hash(Tpkg::metadata_from_package(pkg2))
    begin
      tpkg.install([pkg], PASSPHRASE)
      tpkg2.install([pkg2], PASSPHRASE)
      tpkg.remove(['crontabpkg'])
      tpkg.crontab_destinations(metadata).each do |crontab, destination|
        if destination[:link]
          assert(!File.exist?(destination[:link]) && !File.symlink?(destination[:link]))
        end
      end
      # Test the handling of packages with conflicting crontabs.
      # Systems where we put the crontab into a user file should end up
      # with two copies of the crontab contents in that file.  Systems
      # where we link the crontab into a directory should end up with a
      # link ending in '1'.
      tpkg2.crontab_destinations(metadata2).each do |crontab, destination|
        if destination[:file]
          # With crontabpkg removed the crontab should contain only one
          # copy of the crontab contents
          assert(File.file?(destination[:file]))
          contents = IO.read(destination[:file])
          assert(contents.include?(crontab_contents))
          # Strip out one copy of the crontab contents and verify that no
          # copies of the crontab contents remain
          contents.sub!(crontab_contents, '')
          assert(!contents.include?(crontab_contents))
        elsif destination[:link]
          assert(File.symlink?(destination[:link] + '1'))
          assert_equal(crontab, File.readlink(destination[:link] + '1'))
        end
      end
      # Now remove 'crontabpkg2' and verify that the crontab is gone
      tpkg2.remove(['crontabpkg2'])
      tpkg2.crontab_destinations(metadata2).each do |crontab, destination|
        if destination[:file]
          # Verify that the crontab file is empty
          assert_equal('', IO.read(destination[:file]))
        elsif destination[:link]
          assert(!File.exist?(destination[:link] + '1') && !File.symlink?(destination[:link] + '1'))
        end
      end
    rescue RuntimeError => e
      warn "No crontab support on this platform, crontab handling will not be tested (#{e.message})"
    end
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)
    FileUtils.rm_f(pkg2)
    
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
    externalsdir = File.join(testbase, 'var', 'tpkg', 'externals')
    FileUtils.mkdir_p(externalsdir)
    # Create an external script which puts the data into a file named after
    # the package, and removes any files named after the package on removal.
    externaltestdir = Tempdir.new('externaltest')
    extscript = File.join(externalsdir, extname)
    File.open(extscript, 'w') do |file|
      file.puts <<EOF
#!/bin/sh
set -e

pkgfile=$1
operation=$2

requestfile=#{externaltestdir}/$pkgfile

case "$operation" in
'install')
	mkdir -p `dirname "$requestfile"`
	tmpfile=`mktemp "$requestfile.XXXXXX"` || exit 1
	# Dump in the data passed to us on stdin
	cat >> $tmpfile
	;;
'remove')
	rm -f "$requestfile".*
	;;
*)
	echo "$0: Invalid arguments"
	exit 1
	;;
esac
EOF
    end
    File.chmod(0755, extscript)
    # And run the test
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
    tpkg.install([pkg], PASSPHRASE)
    assert(Dir.entries(externaltestdir).length > 2)
    assert_nothing_raised { tpkg.remove(['externalpkg']) }
    # . and ..
    assert_equal(2, Dir.entries(externaltestdir).length)
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)
    
    # Test handling of external with datafile
    # The datafile is only read at install, not at remove, so this really
    # doesn't test a unique code path.  Rather it just serves to verify that
    # nothing breaks on removal in the face of a datafile being defined.
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
    externalsdir = File.join(testbase, 'var', 'tpkg', 'externals')
    FileUtils.mkdir_p(externalsdir)
    # Create an external script which puts the data into a file named after
    # the package, and removes any files named after the package on removal.
    externaltestdir = Tempdir.new('externaltest')
    extscript = File.join(externalsdir, extname)
    File.open(extscript, 'w') do |file|
      file.puts <<EOF
#!/bin/sh
set -e

pkgfile=$1
operation=$2

requestfile=#{externaltestdir}/$pkgfile

case "$operation" in
'install')
	mkdir -p `dirname "$requestfile"`
	tmpfile=`mktemp "$requestfile.XXXXXX"` || exit 1
	# Dump in the data passed to us on stdin
	cat >> $tmpfile
	;;
'remove')
	rm -f "$requestfile".*
	;;
*)
	echo "$0: Invalid arguments"
	exit 1
	;;
esac
EOF
    end
    File.chmod(0755, extscript)
    # And run the test
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
    tpkg.install([pkg], PASSPHRASE)
    assert(Dir.entries(externaltestdir).length > 2)
    assert_nothing_raised { tpkg.remove(['externalpkg']) }
    # . and ..
    assert_equal(2, Dir.entries(externaltestdir).length)
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)

    # Test handling of external with datascript
    # The datascript is only run at install, not at remove, so this really
    # doesn't test a unique code path.  Rather it just serves to verify that
    # nothing breaks on removal in the face of a datascript being defined.
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
    externalsdir = File.join(testbase, 'var', 'tpkg', 'externals')
    FileUtils.mkdir_p(externalsdir)
    # Create an external script which puts the data into a file named after
    # the package, and removes any files named after the package on removal.
    externaltestdir = Tempdir.new('externaltest')
    extscript = File.join(externalsdir, extname)
    File.open(extscript, 'w') do |file|
      file.puts <<EOF
#!/bin/sh
set -e

pkgfile=$1
operation=$2

requestfile=#{externaltestdir}/$pkgfile

case "$operation" in
'install')
	mkdir -p `dirname "$requestfile"`
	tmpfile=`mktemp "$requestfile.XXXXXX"` || exit 1
	# Dump in the data passed to us on stdin
	cat >> $tmpfile
	;;
'remove')
	rm -f "$requestfile".*
	;;
*)
	echo "$0: Invalid arguments"
	exit 1
	;;
esac
EOF
    end
    File.chmod(0755, extscript)
    # And run the test
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
    tpkg.install([pkg], PASSPHRASE)
    assert(Dir.entries(externaltestdir).length > 2)
    assert_nothing_raised { tpkg.remove(['externalpkg']) }
    # . and ..
    assert_equal(2, Dir.entries(externaltestdir).length)
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)
  end
end

