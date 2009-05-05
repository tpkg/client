#!/usr/bin/ruby -w

#
# Test tpkg's ability to install packages
#

require 'test/unit'
require 'tpkgtest'
require 'facter'
require 'tempfile'
require 'fileutils'

class TpkgInstallTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    # Make up our regular test package
    @pkgfile = make_package(:remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
  end
  
  def test_install
    # The install method does little to nothing itself, it farms everything
    # out to various helper methods that we unit test in the other files of
    # this test suite.  So just do a basic install or two and verify that
    # the whole thing seems to work together
    
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])
    
    assert_nothing_raised { tpkg.install([@pkgfile], PASSPHRASE) }
    
    # Check that the files from the package ended up in the right place
    assert(File.exist?(File.join(testbase, 'file')))
    assert_equal(IO.read(File.join('testpkg', 'reloc', 'file')), IO.read(File.join(testbase, 'file')))
    assert(File.exist?(File.join(testbase, 'encfile')))
    assert_equal(IO.read(File.join('testpkg', 'reloc', 'encfile')), IO.read(File.join(testbase, 'encfile')))
    
    FileUtils.rm_rf(testroot)
  end
  
  def teardown
    FileUtils.rm_f(@pkgfile)
  end
end

