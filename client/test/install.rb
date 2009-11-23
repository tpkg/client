

#
# Test tpkg's ability to install packages
#

require File.dirname(__FILE__) + '/tpkgtest'

class TpkgInstallTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    # Make up our regular test package
    @pkgfile = make_package(:remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    @testroot = Tempdir.new("testroot")
  end
  
  def test_install
    # The install method does little to nothing itself, it farms everything
    # out to various helper methods that we unit test in the other files of
    # this test suite.  So just do a basic install or two and verify that
    # the whole thing seems to work together
    
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

  # Test that if packages have dependencies on each others, then they
  # should installed in the correct order
  def test_install_order

    @pkgfiles = []
    ['a', 'b', 'c'].each do |pkgname|
      srcdir = Tempdir.new("srcdir")
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

      @pkgfiles << make_package(:change => {'name' => pkgname}, :source_directory => srcdir, :dependencies => deps, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      FileUtils.rm_rf(srcdir)
    end

    @tpkg = Tpkg.new(:file_system_root => @testroot, :base => File.join('home', 'tpkg'), :sources => @pkgfiles)
    @tpkg.install(['a'], PASSPHRASE)

    actime = File.new(File.join(File.join(@testroot,'home','tpkg', 'a'))).ctime
    bctime = File.new(File.join(File.join(@testroot,'home','tpkg', 'b'))).ctime
    cctime = File.new(File.join(File.join(@testroot,'home','tpkg', 'c'))).ctime
    assert(actime > cctime)
    assert(cctime > bctime)

  end
  
  def teardown
    FileUtils.rm_f(@pkgfile)
    FileUtils.rm_rf(@testroot)
  end
end

