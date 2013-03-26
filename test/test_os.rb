#
# Tests OS abstraction code
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class Tpkg::OS::TestImplementation < Tpkg::OS
end

class TpkgOSTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    @os = Tpkg::OS.new
  end
  
  def test_register_implementation
    Tpkg::OS.register_implementation(Tpkg::OS::TestImplementation)
    assert_includes Tpkg::OS.class_variable_get(:@@implementations), Tpkg::OS::TestImplementation
  end
  def test_create
    res = Facter::Util::Resolution.new('operatingsystem')
    Facter.stubs(:[]).returns(res)
    res.setcode(lambda {'RedHat'})
    assert_instance_of Tpkg::OS::RedHat, Tpkg::OS.create
  end
  def test_initialize
    [true, false].each do |debugval|
      os = Tpkg::OS.new(:debug => debugval)
      assert_equal debugval, os.instance_variable_get(:@debug)
    end
    # Reach into Facter's guts to test that initialize called Facter.loadfacts
    if Facter.collection.respond_to?(:internal_loader)
      assert Facter.collection.internal_loader.instance_variable_get(:@loaded_all)
    else
      assert Facter.collection.loader.instance_variable_get(:@loaded_all)
    end
  end
  
  def test_init_links
    # assert_raise(NotImplementedError) { @os.init_links('/path/to/init/script', {:init => {}}) }
    assert_equal [], @os.init_links('/path/to/init/script', {:init => {}})
  end
  def test_available_native_packages
    assert_raise(NotImplementedError) { @os.available_native_packages('curl') }
  end
  def test_install_native_package
    assert_raise(NotImplementedError) { @os.install_native_package({}) }
  end
  def test_upgrade_native_package
    assert_raise(NotImplementedError) { @os.upgrade_native_package({}) }
  end
  def test_stub_native_pkg
    # See comment in method
    # assert_raise NotImplementedError { @os.stub_native_pkg({}) }
    pkgfile = make_package
    metadata = Tpkg::metadata_from_package(pkgfile)
    pkg = { :metadata => metadata, :source => pkgfile }
    assert_nil @os.stub_native_pkg(pkg)
  end
  def test_remove_native_stub_pkg
    # See comment in method
    # assert_raise NotImplementedError { @os.remove_native_stub_pkg({}) }
    assert_nil @os.remove_native_stub_pkg({})
  end
  def test_os_version
    verres = Facter::Util::Resolution.new('operatingsystemrelease')
    verres.setcode(lambda {'1.2.3'})
    Facter.expects(:[]).with('operatingsystemrelease').returns(verres).at_least_once
    assert_equal '1.2.3', @os.os_version
    
    # Muck with the returned variable and ensure that doesn't stick.  I.e.
    # ensure that the method called dup on the string before returning it.
    ver = @os.os_version
    goodver = ver.dup
    ver << 'junk'
    assert_equal(goodver, @os.os_version)
    
  end
  def test_native_pkg_to_install_string
    assert_equal 'pkg-1.0-1', @os.native_pkg_to_install_string({:metadata => {:name => 'pkg', :version => '1.0', :package_version => '1'}})
    assert_equal 'pkg-1.0', @os.native_pkg_to_install_string({:metadata => {:name => 'pkg', :version => '1.0'}})
  end
  
  def test_os
    osres = Facter::Util::Resolution.new('operatingsystem')
    osres.setcode(lambda {'TestOS'})
    Facter.expects(:[]).with('operatingsystem').returns(osres).at_least_once
    verres = Facter::Util::Resolution.new('operatingsystemrelease')
    verres.setcode(lambda {'1.2.3'})
    Facter.expects(:[]).with('operatingsystemrelease').returns(verres).at_least_once
    assert_equal 'TestOS-1.2.3', @os.os
    
    # Muck with the returned variable and ensure that doesn't stick.  I.e.
    # ensure that the method called dup on the string before returning it.
    os = @os.os
    goodos = os.dup
    os << 'junk'
    assert_equal(goodos, @os.os)
  end
  def test_os_name
    osres = Facter::Util::Resolution.new('operatingsystem')
    osres.setcode(lambda {'TestOS'})
    Facter.expects(:[]).with('operatingsystem').returns(osres).at_least_once
    assert_equal 'TestOS', @os.os_name
    
    # Muck with the returned variable and ensure that doesn't stick.  I.e.
    # ensure that the method called dup on the string before returning it.
    name = @os.os_name
    goodname = name.dup
    name << 'junk'
    assert_equal(goodname, @os.os_name)
  end
  def test_arch
    hwres = Facter::Util::Resolution.new('hardwaremodel')
    hwres.setcode(lambda {'i286'})
    Facter.expects(:[]).with('hardwaremodel').returns(hwres).at_least_once
    assert_equal 'i286', @os.arch
    
    # Muck with the returned variable and ensure that doesn't stick.  I.e.
    # ensure that the method called dup on the string before returning it.
    arch = @os.arch
    goodarch = arch.dup
    arch << 'junk'
    assert_equal(goodarch, @os.arch)
  end
  def test_fqdn
    fqdnres = Facter::Util::Resolution.new('fqdn')
    fqdnres.setcode(lambda {'test.example.com'})
    Facter.expects(:[]).with('fqdn').returns(fqdnres).at_least_once
    assert_equal 'test.example.com', @os.fqdn
    # Test fallback to hostname + domain
    hostres = Facter::Util::Resolution.new('hostname')
    hostres.setcode(lambda {'test2'})
    domainres = Facter::Util::Resolution.new('domain')
    domainres.setcode(lambda {'example.com'})
    Facter.expects(:[]).with('fqdn').returns(nil)
    Facter.expects(:[]).with('hostname').returns(hostres).at_least_once
    Facter.expects(:[]).with('domain').returns(domainres).at_least_once
    assert_equal 'test2.example.com', @os.fqdn
  end
  def test_cron_dot_d_directory
    assert_nil @os.cron_dot_d_directory
  end
  def test_sudo_default
    assert @os.sudo_default?
  end
  
  def test_sys_v_init_links
    installed_path = '/path/to/init/script'
    tpkgfile = {
      :init => {}
    }
    default_levels = ['1', '2', '3']
    init_directory = '/etc/rc.d'
    assert_equal(
      ['/etc/rc.d/rc1.d/S99script',
       '/etc/rc.d/rc2.d/S99script',
       '/etc/rc.d/rc3.d/S99script'],
      @os.sys_v_init_links(installed_path, tpkgfile, default_levels, init_directory))
    
    tpkgfile = {
      :init => {
        :start => '98'
      }
    }
    assert_equal(
      ['/etc/rc.d/rc1.d/S98script',
       '/etc/rc.d/rc2.d/S98script',
       '/etc/rc.d/rc3.d/S98script'],
      @os.sys_v_init_links(installed_path, tpkgfile, default_levels, init_directory))
    
    tpkgfile = {
      :init => {
        :levels => ['1', '2']
      }
    }
    assert_equal(
      ['/etc/rc.d/rc1.d/S99script',
       '/etc/rc.d/rc2.d/S99script'],
      @os.sys_v_init_links(installed_path, tpkgfile, default_levels, init_directory))
    
    tpkgfile = {
      :init => {
        :levels => '13'
      }
    }
    assert_equal(
      ['/etc/rc.d/rc1.d/S99script',
       '/etc/rc.d/rc3.d/S99script'],
      @os.sys_v_init_links(installed_path, tpkgfile, default_levels, init_directory))
  end
end
