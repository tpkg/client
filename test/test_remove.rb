#
# Test tpkg's ability to remove packages
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgRemoveTests < Test::Unit::TestCase
  include TpkgTests

  def setup
    Tpkg::set_prompt(false)
    
    # temp dir that will automatically get deleted at end of test run, can be
    # used for storing packages
    @tempoutdir = Dir.mktmpdir('tempoutdir')
    
    # Pretend to be an OS with init script support
    res = Facter::Util::Resolution.new('operatingsystem')
    res.setcode(lambda {'RedHat'})
    Facter.stubs(:[]).returns(res)
  end

  def test_remove_dep
    # b and c depends on a
    # d depends on b
    pkgfiles = []
    pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a' }, :remove => ['operatingsystem', 'architecture'])
    pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'b' }, :remove => ['operatingsystem', 'architecture'], :dependencies => {'a' => {}})
    pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'c' }, :remove => ['operatingsystem', 'architecture'], :dependencies => {'a' => {}})
    pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'd' }, :remove => ['operatingsystem', 'architecture'], :dependencies => {'b' => {}})
    Dir.mktmpdir('testbase') do |testbase|
      tpkg = Tpkg.new(:base => testbase, :sources => pkgfiles)
      assert_nothing_raised { tpkg.install(pkgfiles, PASSPHRASE) }
      
      # a, b, c and d are installed
      metadata = tpkg.metadata_for_installed_packages
      assert_equal(4, metadata.length)
      
      # removing a with :remove_all_dep option should remove b, c and d as well
      assert_nothing_raised { tpkg.remove(['a'], {:remove_all_dep => true})}
      metadata = tpkg.metadata_for_installed_packages
      assert_equal(0, metadata.length)
    end
  end

  def test_remove_prereq
    # e requires c
    # d requires c and b
    # c requires a
    pkgfiles = []
    pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a' }, :remove => ['operatingsystem', 'architecture'])
    pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'b' }, :remove => ['operatingsystem', 'architecture'])
    pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'c' }, :remove => ['operatingsystem', 'architecture'], :dependencies => {'a' => {}})
    pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'd' }, :remove => ['operatingsystem', 'architecture'], :dependencies => {'c' => {}, 'b' => {}})
    pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'e' }, :remove => ['operatingsystem', 'architecture'], :dependencies => {'c' => {}})
    Dir.mktmpdir('testbase') do |testbase|
      tpkg = Tpkg.new(:base => testbase, :sources => pkgfiles)
      assert_nothing_raised { tpkg.install(pkgfiles, PASSPHRASE) }
      
      # a, b, c, d and e are installed
      metadata = tpkg.metadata_for_installed_packages
      assert_equal(5, metadata.length)
      
      # removing d with :remove_all_prereq option should remove d and b only and not c and a because
      # e still depends on c
      assert_nothing_raised { tpkg.remove(['d'], {:remove_all_prereq => true})}
      metadata = tpkg.metadata_for_installed_packages
      assert_equal(3, metadata.length)
    end
  end
  
  def test_remove
    pkgfiles = []
    # Make up a couple of packages with different files in them so that
    # they don't conflict
    ['a', 'b'].each do |pkgname|
      Dir.mktmpdir('srcdir') do |srcdir|
        FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
        FileUtils.mkdir_p(File.join(srcdir, 'reloc', 'directory'))
        File.open(File.join(srcdir, 'reloc', 'directory', pkgname), 'w') do |file|
          file.puts pkgname
        end
        File.open(File.join(srcdir, 'reloc', 'directory', "#{pkgname}.conf"), 'w') do |file|
          file.puts pkgname
        end
        pkgfiles << make_package(:output_directory => @tempoutdir, :change => {'name' => pkgname}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture'], :files => { "directory/#{pkgname}.conf" => { 'config' => true}})
      end
    end
    
    Dir.mktmpdir('testroot') do |testroot|
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
      
      # Test removing config files
      # If config file has been modified, then tpkg should not remove it
      tpkg.install(['a', 'b'], PASSPHRASE)
      File.open(File.join(testbase, 'directory', "a.conf"), 'w') do |file|
        file.puts "Modified"
      end
      assert_nothing_raised { tpkg.remove }
      assert(File.exist?(File.join(testbase, 'directory', 'a.conf')))
      assert(!File.exist?(File.join(testbase, 'directory', 'b.conf')))
    end
    
    # Clean up
    pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
    
    # Test that preremove/postremove are run at the right points
    #   Make up a package with scripts that create files so we can check timestamps
    # Also, test tpkg should chdir to package unpack directory before calling
    # pre/post/install/remove scripts
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
      pkgfile = make_package(:output_directory => @tempoutdir, :source_directory => srcdir, :change => {'name' => 'scriptpkg'}, :remove => ['operatingsystem', 'architecture'])
    end
    
    # Install the script package
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkgfile])
      assert_nothing_raised { tpkg.install([pkgfile], PASSPHRASE) }
      assert_nothing_raised { tpkg.remove(['scriptpkg']) }
      # FIXME: Need a way to test that the package remove occurred between the two scripts
      assert(File.stat(scriptfiles['preremove'].path).mtime < File.stat(scriptfiles['postremove'].path).mtime)
    end
    
    # Test init script handling
    pkg = nil
    pkg2 = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
      File.open(File.join(srcdir, 'reloc', 'myinit'), 'w') do |file|
        file.puts('init script')
      end
      pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg' }, :source_directory => srcdir, :files => { 'myinit' => { 'init' => {} } }, :remove => ['operatingsystem', 'architecture'])
      pkg2 = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg2' }, :source_directory => srcdir, :files => { 'myinit' => { 'init' => {} } }, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg,pkg2])
      tpkg2 = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg2'), :sources => [pkg,pkg2])
      metadata = Tpkg::metadata_from_package(pkg)
      metadata2 = Tpkg::metadata_from_package(pkg2)
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
    end
    
    # Test external handling
    extname = 'testext'
    extdata = "This is a test of an external hook\nwith multiple lines\nof data"
    pkg = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'externalpkg' }, :externals => { extname => { 'data' => extdata } }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      externalsdir = File.join(testroot, 'usr', 'lib', 'tpkg', 'externals')
      FileUtils.mkdir_p(externalsdir)
      # Create an external script which puts the data into a file named after
      # the package, and removes any files named after the package on removal.
      Dir.mktmpdir('externaltest') do |externaltestdir|
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
	# Avoid generating SIGPIPE in tpkg
	cat > /dev/null
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
      end
    end
    
    # Test handling of external with datafile
    # The datafile is only read at install, not at remove, so this really
    # doesn't test a unique code path.  Rather it just serves to verify that
    # nothing breaks on removal in the face of a datafile being defined.
    extname = 'testext'
    extdata = "This is a test of an external hook\nwith multiple lines\nof data from a datafile"
    pkg = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      # Create the datafile
      File.open(File.join(srcdir, 'datafile'), 'w') do |file|
        file.print(extdata)
      end
      pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'externalpkg' }, :externals => { extname => { 'datafile' => './datafile' } }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      externalsdir = File.join(testroot, 'usr', 'lib', 'tpkg', 'externals')
      FileUtils.mkdir_p(externalsdir)
      # Create an external script which puts the data into a file named after
      # the package, and removes any files named after the package on removal.
      Dir.mktmpdir('externaltest') do |externaltestdir|
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
	# Avoid generating SIGPIPE in tpkg
	cat > /dev/null
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
      end
    end

    # Test handling of external with datascript
    # The datascript is only run at install, not at remove, so this really
    # doesn't test a unique code path.  Rather it just serves to verify that
    # nothing breaks on removal in the face of a datascript being defined.
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
      externalsdir = File.join(testroot, 'usr', 'lib', 'tpkg', 'externals')
      FileUtils.mkdir_p(externalsdir)
      # Create an external script which puts the data into a file named after
      # the package, and removes any files named after the package on removal.
      Dir.mktmpdir('externaltest') do |externaltestdir|
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
	# Avoid generating SIGPIPE in tpkg
	cat > /dev/null
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
      end
    end
  end
  
  def test_remove_init_scripts
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(File.join(srcdir, 'tpkg.xml'), :change => { 'name' => 'initpkg'  }, :files => { 'etc/init.d/initscript' => { 'init' => {} } })
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end
    
    Dir.mktmpdir('testroot') do |testroot|
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
        # Standard symlink using the base name is removed
        FileUtils.mkdir_p(File.dirname(link))
        File.symlink(init_script, link)
        tpkg.remove_init_scripts(metadata)
        assert(!File.exist?(link) && !File.symlink?(link))
        
        # Links with suffixes from 1..9 are removed
        1.upto(9) do |i|
          FileUtils.rm(Dir.glob(link + '*'))
          File.symlink(init_script, link + i.to_s)
          File.symlink(init_script, link + '1') if (i != 1)
          2.upto(i-1) do |j|
            File.symlink('somethingelse', link + j.to_s)
          end
          tpkg.remove_init_scripts(metadata)
          assert(!File.exist?(link) && !File.symlink?(link))
          assert(!File.exist?(link + '1') && !File.symlink?(link + '1'))
          2.upto(i-1) do |j|
            assert(File.symlink?(link + j.to_s))
            assert_equal('somethingelse', File.readlink(link + j.to_s))
          end
        end
        
        # Links with suffixes of 0 or 10 are left alone
        File.symlink(init_script, link + '0')
        File.symlink(init_script, link + '10')
        tpkg.remove_init_scripts(metadata)
        assert(File.symlink?(link + '0'))
        assert_equal(init_script, File.readlink(link + '0'))
        assert(File.symlink?(link + '10'))
        assert_equal(init_script, File.readlink(link + '10'))
        
        # Running as non-root, permissions issues prevent link removal, warning
        FileUtils.rm(Dir.glob(link + '*'))
        File.symlink(init_script, link)
        File.chmod(0000, File.dirname(link))
        assert_nothing_raised { tpkg.remove_init_scripts(metadata) }
        # FIXME: look for warning in stderr
        File.chmod(0755, File.dirname(link))
        assert(File.symlink?(link))
        assert_equal(init_script, File.readlink(link))
      end
    end
  end
  
  # Test that the remove method calls remove_crontabs as appropriate
  def test_remove_remove_crontabs
    # FIXME
  end
  
  def test_skip_remove_stop
    # Make a test package with an init script
    pkg = nil
    tmpfile = Tempfile.new('tpkgtest_script')
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
      initscript = File.join(srcdir, 'reloc', 'myinit')
      File.open(initscript, 'w') do |file|
        file.puts('#!/bin/sh')
        file.puts('case "$1" in')
        file.puts("'stop')")
        file.puts("  echo 'test_skip_remove_stop' > #{tmpfile.path}")
        file.puts('  ;;')
        file.puts('esac')
      end
      File.chmod(0755, initscript)
      pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg' }, :source_directory => srcdir, :files => { 'myinit' => { 'init' => {} } }, :remove => ['operatingsystem', 'architecture'])
    end
    
    # Removing the package without skip_remove_stop should run the init script
    # with a "stop" argument on package removal
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
      tpkg.install([pkg], PASSPHRASE)
      tpkg.remove(['initpkg'])
      assert_equal("test_skip_remove_stop\n", File.read(tmpfile.path))
    end
    
    # Clear out the temp file to reset
    File.open(tmpfile.path, 'w') {}
    
    # Removing the package with skip_remove_stop should not run the init
    # script on package removal
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
      tpkg.install([pkg], PASSPHRASE)
      tpkg.remove(['initpkg'], :skip_remove_stop => true)
      assert_equal("", File.read(tmpfile.path))
    end
  end
  
  def teardown
    FileUtils.rm_rf(@tempoutdir)
  end
end

