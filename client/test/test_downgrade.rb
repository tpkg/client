#
# Test tpkg's ability to upgrade packages
#

require File.dirname(__FILE__) + '/tpkgtest'

class TpkgDowngradeTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)

    @pkgfiles = []   
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.mkdir(File.join(srcdir, 'reloc'))

    # Creating packages that will be used for testing
 
    # Package a-1 and a-2. No dependency.
    @pkgfiles << make_package(:change => {'name' => 'a', 'version' => '1', 'package_version' => '1'}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    @pkgfiles << make_package(:change => {'name' => 'a', 'version' => '2', 'package_version' => '1'}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])

    # Package b-1 and b-2. b-1 depends on c-1
    @pkgfiles << make_package(:change => {'name' => 'b', 'version' => '1', 'package_version' => '1'}, :dependencies => {'c' => {}}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    @pkgfiles << make_package(:change => {'name' => 'b', 'version' => '2', 'package_version' => '1'}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    @pkgfiles << make_package(:change => {'name' => 'c', 'version' => '1', 'package_version' => '1'}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])

    # Package d-1 and d-2. d-1 depends on nonexistingpkg
    @pkgfiles << make_package(:change => {'name' => 'd', 'version' => '1', 'package_version' => '1'}, :dependencies => {'nonexistingpkg' => {}}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    @pkgfiles << make_package(:change => {'name' => 'd', 'version' => '2', 'package_version' => '1'}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])

    # Package e-1, e-2 and f-1. f-1 depends on e-2
    @pkgfiles << make_package(:change => {'name' => 'e', 'version' => '1', 'package_version' => '1'}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    @pkgfiles << make_package(:change => {'name' => 'e', 'version' => '2', 'package_version' => '1'}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    @pkgfiles << make_package(:change => {'name' => 'f', 'version' => '1', 'package_version' => '1'}, :dependencies => {'e' => {'minimum_version' => '2.0', 'maximum_version' => '2.0'}}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])

    FileUtils.rm_rf(srcdir)
    
    @testroot = Tempdir.new("testroot")
    @testbase = File.join(@testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(@testbase)
    @tpkg = Tpkg.new(:file_system_root => @testroot, :base => File.join('home', 'tpkg'), :sources => @pkgfiles)
    @tpkg.install(['a', 'b', 'd', 'e', 'f'], PASSPHRASE)
  end

  def test_downgrade

    # should be able to downgrade to a-1
    assert_nothing_raised {@tpkg.upgrade(['a=1'], PASSPHRASE, {:downgrade => true})}

    # should be able to downgrade to b-1, 
    assert_nothing_raised {@tpkg.upgrade(['b=1'], PASSPHRASE, {:downgrade => true})}

    # should not be able to downgrade to d-1 since it depends on non-existing pkg
    assert_raise(RuntimeError) {@tpkg.upgrade(['d=1'], PASSPHRASE, {:downgrade => true})}

    # should not be able to downgrade to e-1 since f-1 depends on e-2
    assert_raise(RuntimeError) {@tpkg.upgrade(['e=1'], PASSPHRASE, {:downgrade => true})}

    #  There should be 6 packages installed
    metadata = @tpkg.metadata_for_installed_packages
    assert_equal(6, metadata.size)
    # a, b, c  and f should be version 1
    metadata.each do | m |
      if ['a','b','c','f'].include?(m[:name])
        assert_equal('1', m[:version])       
      elsif ['d', 'e'].include?(m[:name])
        assert_equal('2', m[:version])       
      else
        assert(false)
      end
    end
  end
  
  def teardown
    @pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
    FileUtils.rm_rf(@testroot)
  end
end

