

#
# Test tpkg's ability to install packages
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgInstallTests < Test::Unit::TestCase
  include TpkgTests

  def setup
    Tpkg::set_prompt(false)

    # Make up our regular test package
    @pkgfile = make_package(:remove => ['operatingsystem', 'architecture'])
    @testroot = Dir.mktmpdir('testroot')
  end

  def test_install_by_filename
    testbase = File.join(@testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => @testroot, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])

    assert_nothing_raised { tpkg.install([@pkgfile], PASSPHRASE) }

    # Check that the files from the package ended up in the right place
    assert(File.exist?(File.join(testbase, 'file')))
    assert_equal(IO.read(File.join(TESTPKGDIR, 'reloc', 'file')), IO.read(File.join(testbase, 'file')))
    assert(File.exist?(File.join(testbase, 'encfile')))
    assert_equal(IO.read(File.join(TESTPKGDIR, 'reloc', 'encfile')), IO.read(File.join(testbase, 'encfile')))
  end

  def test_install_by_pkg_name
    testbase = File.join(@testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => @testroot, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])

    assert_nothing_raised { tpkg.install(['testpkg'], PASSPHRASE) }

    # Check that the files from the package ended up in the right place
    assert(File.exist?(File.join(testbase, 'file')))
    assert_equal(IO.read(File.join(TESTPKGDIR, 'reloc', 'file')), IO.read(File.join(testbase, 'file')))
    assert(File.exist?(File.join(testbase, 'encfile')))
    assert_equal(IO.read(File.join(TESTPKGDIR, 'reloc', 'encfile')), IO.read(File.join(testbase, 'encfile')))

  end

  # Test that if packages have dependencies on each others, then they
  # should installed in the correct order
  def test_install_order

    @pkgfiles = []
    ['a', 'b', 'c'].each do |pkgname|
      Dir.mktmpdir('srcdir') do |srcdir|
        FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
        FileUtils.mkdir(File.join(srcdir, 'reloc'))
        File.open(File.join(srcdir, 'reloc', pkgname), 'w') do |file|
          file.puts pkgname
        end

        # make a depends on c and c depends on b
        deps = {}
        if pkgname == 'a'
          deps['c'] = {}
        elsif pkgname == 'c'
          deps['b'] = {}
        end

        # make a postinstall script that sleeps for 1 second. That way we
        # have enough time between each installation to determine the order of how they
        # were installed
        File.open(File.join(srcdir, 'postinstall'), 'w') do | file |
          file.puts "#!/bin/bash\nsleep 1"
        end
        File.chmod(0755, File.join(srcdir, 'postinstall'))

        @pkgfiles << make_package(:change => {'name' => pkgname}, :source_directory => srcdir, :dependencies => deps, :remove => ['operatingsystem', 'architecture'])
      end
    end

    tpkg = Tpkg.new(:file_system_root => @testroot, :base => File.join('home', 'tpkg'), :sources => @pkgfiles)
    tpkg.install(['a'], PASSPHRASE)

    actime = File.new(File.join(File.join(@testroot,'home','tpkg', 'a'))).ctime
    bctime = File.new(File.join(File.join(@testroot,'home','tpkg', 'b'))).ctime
    cctime = File.new(File.join(File.join(@testroot,'home','tpkg', 'c'))).ctime
    assert(actime > cctime)
    assert(cctime > bctime)

  end

  # Verify that we can install multiple versions of the same package
  def test_install_multiple_versions
    pkgfiles = []
    ['1', '2'].each do |pkgver|
      pkgfiles << make_package(:change => {'version' => pkgver, 'name' => 'versiontest'}, :remove => ['operatingsystem', 'architecture'])
    end

    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => pkgfiles)
      assert_nothing_raised { tpkg.install(['versiontest=1'], PASSPHRASE) }
      assert_nothing_raised { tpkg.install(['versiontest=2'], PASSPHRASE) }
      metadata = tpkg.metadata_for_installed_packages
      # verify that both of them are installed
      assert_equal(metadata.size, 2)
    end

    # verify we can install in reverse order
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => pkgfiles)
      assert_nothing_raised { tpkg.install(['versiontest=2'], PASSPHRASE) }
      assert_nothing_raised { tpkg.install(['versiontest=1'], PASSPHRASE) }
      metadata = tpkg.metadata_for_installed_packages
      # verify that both of them are installed
      assert_equal(metadata.size, 2)
    end

    pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
  end

  def test_install_with_externals
    externalspkg = nil
    extname1 = 'testext1'
    extdata1 = "This is a test of an external hook\nwith multiple lines\nof data"
    extname2 = 'testext2'
    extdata2 = "This is a test of a different external hook\nwith multiple lines\nof different data"
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(
        File.join(TESTPKGDIR, 'tpkg-nofiles.xml'),
        File.join(srcdir, 'tpkg.xml'))
      externalspkg = make_package(
        :change => { 'name' => 'externalpkg', 'version' => '1' },
        :externals => { extname1 => {'data' => extdata1},
                        extname2 => {'data' => extdata2} },
        :source_directory => srcdir,
        :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      # Make external scripts which write the data they receive to temporary
      # files, so that we can verify the external scripts received the data
      # properly.
      exttmpfile1 = Tempfile.new('tpkgtest_external')
      exttmpfile2 = Tempfile.new('tpkgtest_external')
      externalsdir = File.join(testroot, 'usr', 'lib', 'tpkg', 'externals')
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
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :base => File.join('home', 'tpkg'),
        :sources => [externalspkg])
      assert_nothing_raised { tpkg.install([externalspkg], PASSPHRASE) }
      assert_equal("install\n#{extdata1}", IO.read(exttmpfile1.path))
      assert_equal("install\n#{extdata2}", IO.read(exttmpfile2.path))
    end
    FileUtils.rm_f(externalspkg)
  end

  def test_stub_native_pkg
    # FIXME
  end

  def teardown
    FileUtils.rm_f(@pkgfile)
    FileUtils.rm_rf(@testroot)
  end
end

