#
# Test tpkg's ability to upgrade packages#
#

require "./#{File.dirname(__FILE__)}/tpkgtest"

class TpkgUpgradeTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    @pkgfiles = []
    ['a', 'b'].each do |pkgname|
      # Make sure the files in the a packages don't conflict with
      # the b packages
      Dir.mktmpdir('srcdir') do |srcdir|
        FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
        FileUtils.mkdir(File.join(srcdir, 'reloc'))
        File.open(File.join(srcdir, 'reloc', pkgname), 'w') do |file|
          file.puts pkgname
        end
        # Make the 'b' packages depend on 'a' so that we ensure that we
        # can upgrade a package on which other packages depend.
        deps = {}
        if pkgname == 'b'
          deps['a'] = {}
        end
        ['1.0', '2.0'].each do |pkgver|
          @pkgfiles << make_package(:change => {'name' => pkgname, 'version' => pkgver}, :source_directory => srcdir, :dependencies => deps, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
        end
      end
    end

    # Create pkg c-1.2-3 and c-2-3-1
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir(File.join(srcdir, 'reloc'))
      File.open(File.join(srcdir, 'reloc', 'c'), 'w') do |file|
        file.puts "this file belong to c package"
      end
      @pkgfiles << make_package(:change => {'name' => 'c', 'version' => '1.2', 'package_version' => '3'}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      @pkgfiles << make_package(:change => {'name' => 'c', 'version' => '2.3', 'package_version' => '1'}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    end
    
    @testroot = Dir.mktmpdir('testroot')
    @testbase = File.join(@testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(@testbase)
    @tpkg = Tpkg.new(:file_system_root => @testroot, :base => File.join('home', 'tpkg'), :sources => @pkgfiles)
    @tpkg.install(['a=1.0', 'b=1.0'], PASSPHRASE)
  end

  # pkg ordera-1 and orderb-1 are installed. Package orderb depends on ordera.
  # Now if we were to upgrade orderb-1 to orderb-2, which depends on ordera-2, then 
  # tpkg should do things in the following order:
  # remove orderb-1, remove ordera-1, install ordera-2, install orderb-2
  def test_upgrade_order
    pkgfiles = []
    Dir.mktmpdir('srcdir') do |srcdir|
      # Create pkg ordera-1 and orderb-1
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      pkgfiles <<  make_package(:change => { 'name' => 'ordera', 'version' => '1' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      deps = {'ordera'=> {'minimum_version' => '1.0'}}
      pkgfiles <<  make_package(:change => { 'name' => 'orderb', 'version' => '1' }, :source_directory => srcdir, :dependencies => deps, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      
      # Create pkg ordera-2, which has a file called pkga2
      FileUtils.mkdir(File.join(srcdir, 'reloc'))
      File.open(File.join(srcdir, 'reloc', 'pkga2'), 'w') do |file|
        file.puts "Hello world"
      end
      pkgfiles <<  make_package(:change => { 'name' => 'ordera', 'version' => '2' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      FileUtils.rm(File.join(srcdir, 'reloc', 'pkga2'))
      
      # Create pkg orderb-2, which test that a file called pkga2 exists. We will use this
      # to ensure that during the upgrade, pkg b-2 is installed after pkg a-2
      deps = {'ordera'=> {'minimum_version' => '2.0'}}
      File.open(File.join(srcdir, 'preinstall'), 'w') do |scriptfile|
        scriptfile.puts('#!/bin/sh')
        # Test that tpkg set $TPKG_HOME before running the script
        scriptfile.puts('ls "$TPKG_HOME"/pkga2 || exit 1')
      end
      File.chmod(0755, File.join(srcdir, 'preinstall'))
      pkgfiles <<  make_package(:change => { 'name' => 'orderb', 'version' => '2' }, :source_directory => srcdir, :dependencies => deps, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    end

    tpkg = Tpkg.new(:file_system_root => @testroot, :base => File.join('home', 'tpkg'), :sources => pkgfiles)
    tpkg.install(['ordera=1.0', 'orderb=1.0'], PASSPHRASE)

    assert_nothing_raised { tpkg.upgrade(['orderb']) }
    
    pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
  end
  
  def test_upgrade
    assert_nothing_raised { @tpkg.upgrade(['a']) }
    # Should have two packages installed:  a-2.0 and b-1.0
    metadata = @tpkg.metadata_for_installed_packages
    assert_equal(2, metadata.length)
    apkg = nil
    bpkg = nil
    metadata.each do |m|
      if m[:name] == 'a'
        apkg = m
      elsif m[:name] == 'b'
        bpkg = m
      end
    end
    assert_not_nil(apkg)
    assert_equal('2.0', apkg[:version])
    assert_not_nil(bpkg)
    assert_equal('1.0', bpkg[:version])
    
    assert_nothing_raised { @tpkg.upgrade }
    # Should have two packages installed:  a-2.0 and b-2.0
    metadata = @tpkg.metadata_for_installed_packages
    assert_equal(2, metadata.length)
    apkg = nil
    bpkg = nil
    metadata.each do |m|
      if m[:name] == 'a'
        apkg = m
      elsif m[:name] == 'b'
        bpkg = m
      end
    end
    assert_not_nil(apkg)
    assert_equal('2.0', apkg[:version])
    assert_not_nil(bpkg)
    assert_equal('2.0', bpkg[:version])

    # These test cases are for: Can't upgrade if package has higher version
    # number but lower package version number
    # install  c-1.2.3
    assert_nothing_raised{@tpkg.install(['c=1.2'], PASSPHRASE)}
    metadata = @tpkg.metadata_for_installed_packages
    assert_equal(3, metadata.length)
    # upgrade to c-2.3-1
    assert_nothing_raised{@tpkg.upgrade(['c'], PASSPHRASE)}
    metadata = @tpkg.metadata_for_installed_packages
    cpkg = nil
    metadata.each do |m|
      if m[:name] == 'c'
        assert_equal('2.3', m[:version])
      end
    end
  end
  
  # Test an upgrade using a filename rather than a package spec ('a')
  def test_upgrade_by_filename
    a2pkgfile = @pkgfiles.find {|pkgfile| pkgfile =~ /a-2.0/}
    assert_nothing_raised { @tpkg.upgrade([a2pkgfile]) }
    # Should have two packages installed:  a-2.0 and b-1.0
    metadata = @tpkg.metadata_for_installed_packages
    assert_equal(2, metadata.length)
    apkg = nil
    bpkg = nil
    metadata.each do |m|
      if m[:name] == 'a'
        apkg = m
      elsif m[:name] == 'b'
        bpkg = m
      end
    end
    assert_not_nil(apkg)
    assert_equal('2.0', apkg[:version])
    assert_not_nil(bpkg)
    assert_equal('1.0', bpkg[:version])
  end
  
  # Test upgrading all packages by passing no arguments to upgrade
  def test_upgrade_all
    assert_nothing_raised { @tpkg.upgrade }
    # Should have two packages installed:  a-2.0 and b-2.0
    metadata = @tpkg.metadata_for_installed_packages
    assert_equal(2, metadata.length)
    apkg = nil
    bpkg = nil
    metadata.each do |m|
      if m[:name] == 'a'
        apkg = m
      elsif m[:name] == 'b'
        bpkg = m
      end
    end
    assert_not_nil(apkg)
    assert_equal('2.0', apkg[:version])
    assert_not_nil(bpkg)
    assert_equal('2.0', bpkg[:version])
  end
  
  def test_upgrade_with_externals_add
    oldpkg = nil
    newpkg = nil
    extname1 = 'testext1'
    extdata1 = "This is a test of an external hook\nwith multiple lines\nof data"
    Dir.mktmpdir('srcdir') do |srcdir|
      # Older version has no external, newer version has external
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      oldpkg = make_package(:change => { 'name' => 'externalpkg', 'version' => '1' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      newpkg = make_package(:change => { 'name' => 'externalpkg', 'version' => '2' }, :externals => { extname1 => {'data' => extdata1} }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    end
    # Make external scripts which write the data they receive to temporary
    # files, so that we can verify the external scripts received the data
    # properly.
    exttmpfile1 = Tempfile.new('tpkgtest_external')
    externalsdir = File.join(@testroot, 'usr', 'lib', 'tpkg', 'externals')
    FileUtils.mkdir_p(externalsdir)
    extscript1 = File.join(externalsdir, extname1)
    File.open(extscript1, 'w') do |file|
      file.puts('#!/bin/sh')
      # Operation (install/remove)
      file.puts("echo $2 >> #{exttmpfile1.path}")
      # Data
      file.puts("cat >> #{exttmpfile1.path}")
    end
    File.chmod(0755, extscript1)
    # And run the test
    assert_nothing_raised { @tpkg.install([oldpkg], PASSPHRASE) }
    assert_equal('', IO.read(exttmpfile1.path))
    assert_nothing_raised { @tpkg.upgrade([newpkg], PASSPHRASE) }
    assert_equal("install\n#{extdata1}", IO.read(exttmpfile1.path))
    FileUtils.rm_f(oldpkg)
    FileUtils.rm_f(newpkg)
  end
  
  def test_upgrade_with_externals_add_second
    oldpkg = nil
    newpkg = nil
    extname1 = 'testext1'
    extdata1 = "This is a test of an external hook\nwith multiple lines\nof data"
    extname2 = 'testext2'
    extdata2 = "This is a test of a different external hook\nwith multiple lines\nof different data"
    Dir.mktmpdir('srcdir') do |srcdir|
      # Older version has one external, newer version has same external plus an
      # additional one
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      oldpkg = make_package(:change => { 'name' => 'externalpkg', 'version' => '1' }, :externals => { extname1 => {'data' => extdata1} }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      newpkg = make_package(:change => { 'name' => 'externalpkg', 'version' => '2' }, :externals => { extname1 => {'data' => extdata1}, extname2 => {'data' => extdata2} }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    end
    # Make external scripts which write the data they receive to temporary
    # files, so that we can verify the external scripts received the data
    # properly.
    exttmpfile1 = Tempfile.new('tpkgtest_external')
    exttmpfile2 = Tempfile.new('tpkgtest_external')
    externalsdir = File.join(@testroot, 'usr', 'lib', 'tpkg', 'externals')
    FileUtils.mkdir_p(externalsdir)
    extscript1 = File.join(externalsdir, extname1)
    extscript2 = File.join(externalsdir, extname2)
    File.open(extscript1, 'w') do |file|
      file.puts('#!/bin/sh')
      # Operation (install/remove)
      file.puts("echo $2 >> #{exttmpfile1.path}")
      # Data
      file.puts("cat >> #{exttmpfile1.path}")
    end
    File.open(extscript2, 'w') do |file|
      file.puts('#!/bin/sh')
      # Operation (install/remove)
      file.puts("echo $2 >> #{exttmpfile2.path}")
      # Data
      file.puts("cat >> #{exttmpfile2.path}")
    end
    File.chmod(0755, extscript1)
    File.chmod(0755, extscript2)
    # And run the test
    assert_nothing_raised { @tpkg.install([oldpkg], PASSPHRASE) }
    assert_equal("install\n#{extdata1}", IO.read(exttmpfile1.path))
    assert_equal('', IO.read(exttmpfile2.path))
    assert_nothing_raised { @tpkg.upgrade([newpkg], PASSPHRASE) }
    # The expectation is that since the old and new packages have the same
    # extname1 external that it will not be run during the upgrade, and thus
    # the extdata1 should only occur once in the tempfile.
    assert_equal("install\n#{extdata1}", IO.read(exttmpfile1.path))
    assert_equal("install\n#{extdata2}", IO.read(exttmpfile2.path))
    FileUtils.rm_f(oldpkg)
    FileUtils.rm_f(newpkg)
  end
  
  def test_upgrade_with_externals_different_data
    oldpkg = nil
    newpkg = nil
    extname1 = 'testext1'
    extdata1 = "This is a test of an external hook\nwith multiple lines\nof data"
    extdata2 = "This is a test of an external hook\nwith multiple lines\nof different data"
    Dir.mktmpdir('srcdir') do |srcdir|
      # Both versions have an external with the same name but different data
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      oldpkg = make_package(:change => { 'name' => 'externalpkg', 'version' => '1' }, :externals => { extname1 => {'data' => extdata1} }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      newpkg = make_package(:change => { 'name' => 'externalpkg', 'version' => '2' }, :externals => { extname1 => {'data' => extdata2} }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    end
    # Make external scripts which write the data they receive to temporary
    # files, so that we can verify the external scripts received the data
    # properly.
    exttmpfile1 = Tempfile.new('tpkgtest_external')
    externalsdir = File.join(@testroot, 'usr', 'lib', 'tpkg', 'externals')
    FileUtils.mkdir_p(externalsdir)
    extscript1 = File.join(externalsdir, extname1)
    File.open(extscript1, 'w') do |file|
      file.puts('#!/bin/sh')
      # Operation (install/remove)
      file.puts("echo $2 >> #{exttmpfile1.path}")
      # Data
      file.puts("cat >> #{exttmpfile1.path}")
    end
    File.chmod(0755, extscript1)
    # And run the test
    assert_nothing_raised { @tpkg.install([oldpkg], PASSPHRASE) }
    assert_equal("install\n#{extdata1}", IO.read(exttmpfile1.path))
    assert_nothing_raised { @tpkg.upgrade([newpkg], PASSPHRASE) }
    assert_equal("install\n#{extdata1}remove\n#{extdata1}install\n#{extdata2}", IO.read(exttmpfile1.path))
    FileUtils.rm_f(oldpkg)
    FileUtils.rm_f(newpkg)
  end
 
  # Install pkgA and pkgB, both of version 1.0. pkgB depends on pkgA, min and max version 1.0.
  # Try to upgrade pkgA to 2.0. This should not be allow.
  def test_upgrade_with_strict_dependency
    pkgfiles = []
    Dir.mktmpdir('srcdir') do |srcdir|
      # Create pkg stricta-1 and strictb-1
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      pkgfiles <<  make_package(:change => { 'name' => 'stricta', 'version' => '1.0' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      pkgfiles <<  make_package(:change => { 'name' => 'stricta', 'version' => '2.0' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      pkgfiles <<  make_package(:change => { 'name' => 'strictb', 'version' => '1.0' }, :source_directory => srcdir, :dependencies => {'stricta' => {'minimum_version' => '1.0', 'maximum_version' => '1.0'}}, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    end

    tpkg = Tpkg.new(:file_system_root => @testroot, :base => File.join('home', 'tpkg'), :sources => pkgfiles)
    tpkg.install(['stricta=1.0', 'strictb=1.0'], PASSPHRASE)
    metadata = @tpkg.metadata_for_installed_packages

    # Should not be able to upgrade stricta to 2.0
    tpkg.upgrade(['stricta'])

    metadata = @tpkg.metadata_for_installed_packages

    apkg = nil
    bpkg = nil
    metadata.each do |m|
      if m[:name] == 'stricta'
        apkg = m
      elsif m[:name] == 'strictb'
        bpkg = m
      end
    end
    # Package stricta should still be of version 1.0
    assert_equal('1.0', apkg[:version])
    
    pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
  end
  
  # b-1 depends on a-2
  # b-2 depends on a-1
  # Can we upgrade from b-1 to b-2?
  def test_upgrade_with_dependency_rollback
    pkgfiles = []
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      pkgfiles <<  make_package(:change => { 'name' => 'deprolla', 'version' => '1' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      pkgfiles <<  make_package(:change => { 'name' => 'deprolla', 'version' => '2' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      pkgfiles <<  make_package(:change => { 'name' => 'deprollb', 'version' => '1' }, :source_directory => srcdir, :dependencies => {'deprolla' => {'minimum_version' => '2', 'maximum_version' => '2'}}, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      pkgfiles <<  make_package(:change => { 'name' => 'deprollb', 'version' => '2' }, :source_directory => srcdir, :dependencies => {'deprolla' => {'minimum_version' => '1', 'maximum_version' => '1'}}, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    end
    
    tpkg = Tpkg.new(:file_system_root => @testroot, :base => File.join('home', 'tpkg'), :sources => pkgfiles)
    tpkg.install(['deprollb=1.0'], PASSPHRASE)
    metadata = @tpkg.metadata_for_installed_packages
    
    tpkg.upgrade(['deprollb'])
    
    metadata = @tpkg.metadata_for_installed_packages
    
    apkg = nil
    bpkg = nil
    metadata.each do |m|
      if m[:name] == 'deprolla'
        apkg = m
      elsif m[:name] == 'deprollb'
        bpkg = m
      end
    end
    # Package b should version 2
    assert_equal('2', bpkg[:version])
    # Package a should version 1
    assert_equal('1', apkg[:version])
    
    pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
  end
  
  def teardown
    @pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
    FileUtils.rm_rf(@testroot)
  end
end

