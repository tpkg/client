#
# Tests FreeBSD OS abstraction code
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgOSFreeBSDTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    @freebsd = Tpkg::OS::FreeBSD.new(
      :pkginfocmd => File.join(TESTCMDDIR, 'freebsd/pkg_info'),
      )
  end
  def setup_mock_os
    fact = Facter::Util::Fact.new('hardwaremodel')
    fact.stubs(:value).returns('i386')
    Facter.expects(:[]).with('hardwaremodel').returns(fact).at_least_once
    fact = Facter::Util::Fact.new('operatingsystemrelease')
    fact.stubs(:value).returns('9.1-RELEASE')
    Facter.expects(:[]).with('operatingsystemrelease').returns(fact).at_least_once
  end
  
  def test_supported
    fact = Facter::Util::Fact.new('operatingsystem')
    Facter.expects(:[]).with('operatingsystem').returns(fact).at_least_once
    fact.stubs(:value).returns('FreeBSD')
    assert Tpkg::OS::FreeBSD.supported?
    fact.stubs(:value).returns('Other')
    refute Tpkg::OS::FreeBSD.supported?
  end
  def test_initialize
    [:pkginfocmd, :pkgaddcmd, :pkgdeletecmd].each do |cmdvar|
      freebsd = Tpkg::OS::FreeBSD.new(cmdvar => TESTCMD)
      assert_equal TESTCMD, freebsd.instance_variable_get("@#{cmdvar}")
      freebsd = Tpkg::OS::FreeBSD.new(:testcmd => TESTCMD)
      assert_equal TESTCMD, freebsd.instance_variable_get("@#{cmdvar}")
    end
    # Test that super is called
    [true, false].each do |debugval|
      freebsd = Tpkg::OS::FreeBSD.new(:debug => debugval)
      assert_equal debugval, freebsd.instance_variable_get(:@debug)
    end
  end
  
  def test_packagesite
    setup_mock_os
    assert_equal 'ftp://ftp.freebsd.org/pub/FreeBSD/ports/i386/packages-9-stable/All/', @freebsd.packagesite
    freebsd = Tpkg::OS::FreeBSD.new(:packagesite => 'http://example.com/freebsd/<%= os_version %>/<%= arch %>')
    assert_equal 'http://example.com/freebsd/9/i386/', freebsd.packagesite
  end
  def test_init_links
    assert_equal ['/usr/local/etc/rc.d/script'], @freebsd.init_links('/path/to/init/script', {:init => {}})
  end
  def test_available_native_packages
    assert_equal(
      [
        {:metadata=>
          {:name=>'curl', :version=>'7.24.0'},
          :source=>:native_installed,
          :prefer=>true},
      ],
      @freebsd.available_native_packages('curl'))
    assert_equal [], @freebsd.available_native_packages('bogus')
  end
  def test_native_pkg_to_install_string
    assert_equal 'pkg-1.0_1', @freebsd.native_pkg_to_install_string({:metadata => {:name => 'pkg', :version => '1.0', :package_version => '1'}})
    assert_equal 'pkg-1.0', @freebsd.native_pkg_to_install_string({:metadata => {:name => 'pkg', :version => '1.0'}})
  end
  def test_install_native_package
    setup_mock_os
    @freebsd.expects(:system).
      with('sh', '-c', "PACKAGESITE=#{@freebsd.packagesite} pkg_add -r curl-7.24.0")
    @freebsd.install_native_package({:metadata => {:name => 'curl', :version => '7.24.0'}})
  end
  def test_upgrade_native_package
    setup_mock_os
    @freebsd.expects(:system).with('pkg_delete curl-7.24.0')
    @freebsd.expects(:system).
      with('sh', '-c', "PACKAGESITE=#{@freebsd.packagesite} pkg_add -r curl-7.24.0")
    @freebsd.upgrade_native_package({:metadata => {:name => 'curl', :version => '7.24.0'}})
  end
  def test_os_version
    fact = Facter::Util::Fact.new('operatingsystemrelease')
    fact.stubs(:value).returns('9.1-RELEASE')
    Facter.expects(:[]).with('operatingsystemrelease').returns(fact).at_least_once
    assert_equal '9', Tpkg::OS::FreeBSD.new.os_version
  end
end
