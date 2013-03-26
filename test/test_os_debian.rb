#
# Tests Debian OS abstraction code
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgOSDebianTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    @debian = Tpkg::OS::Debian.new(
      :dpkgquerycmd => File.join(TESTCMDDIR, 'debian/dpkg-query'),
      :aptcachecmd => File.join(TESTCMDDIR, 'debian/apt-cache'),
      )
  end
  
  def test_supported
    res = Facter::Util::Resolution.new('operatingsystem')
    Facter.expects(:[]).with('operatingsystem').returns(res).at_least_once
    res.setcode(lambda {'Debian'})
    assert Tpkg::OS::Debian.supported?
    res.setcode(lambda {'Ubuntu'})
    assert Tpkg::OS::Debian.supported?
    res.setcode(lambda {'Other'})
    refute Tpkg::OS::Debian.supported?
  end
  def test_initialize
    [:dpkgquerycmd, :aptcachecmd, :aptgetcmd].each do |cmdvar|
      debian = Tpkg::OS::Debian.new(cmdvar => TESTCMD)
      assert_equal TESTCMD, debian.instance_variable_get("@#{cmdvar}")
      debian = Tpkg::OS::Debian.new(:testcmd => TESTCMD)
      assert_equal TESTCMD, debian.instance_variable_get("@#{cmdvar}")
    end
    # Test that super is called
    [true, false].each do |debugval|
      debian = Tpkg::OS::Debian.new(:debug => debugval)
      assert_equal debugval, debian.instance_variable_get(:@debug)
    end
  end
  def test_init_links
    correct = (2..5).collect{|i| "/etc/rc#{i}.d/S99script"}
    assert_equal correct, @debian.init_links('/path/to/init/script', {:init => {}})
  end
  def test_cron_dot_d_directory
    assert_equal '/etc/cron.d', @debian.cron_dot_d_directory
  end
  def test_available_native_packages
    assert_equal(
      [
        {:metadata=>
          {:name=>'ruby1.9.1', :version=>'1.9.3.194', :package_version=>'3'},
          :source=>:native_installed,
          :prefer=>true},
        {:metadata=>
          {:name=>'ruby1.9.1', :version=>'1.9.3.194', :package_version=>'7'},
          :source=>:native_available},
      ],
      @debian.available_native_packages('ruby1.9.1'))
    assert_equal(
      [
        {:metadata=>
          {:name=>'exim4', :version=>'4.80', :package_version=>'7'},
          :source=>:native_available}
      ],
      @debian.available_native_packages('exim4'))
    assert_equal [], @debian.available_native_packages('bogus')
  end
  def test_native_pkg_to_install_string
    assert_equal 'pkg=1.0-1', @debian.native_pkg_to_install_string({:metadata => {:name => 'pkg', :version => '1.0', :package_version => '1'}})
    assert_equal 'pkg=1.0', @debian.native_pkg_to_install_string({:metadata => {:name => 'pkg', :version => '1.0'}})
  end
  def test_install_native_package
    @debian.expects(:system).with('apt-get -y install ruby1.9.1=1.9.3.194-7')
    @debian.install_native_package({:metadata => {:name => 'ruby1.9.1', :version => '1.9.3.194', :package_version => '7'}})
  end
  def test_upgrade_native_package
    @debian.expects(:system).with('apt-get -y install ruby1.9.1=1.9.3.194-7')
    @debian.upgrade_native_package({:metadata => {:name => 'ruby1.9.1', :version => '1.9.3.194', :package_version => '7'}})
  end
  def test_os_version
    # The os_version method caches its result, so we need a new object for
    # each test
    res = Facter::Util::Resolution.new('lsbmajdistrelease')
    Facter.expects(:[]).with('lsbmajdistrelease').returns(res).at_least_once
    res.setcode(lambda {'6'})
    assert_equal '6', Tpkg::OS::Debian.new.os_version
    res.setcode(lambda {'testing'})
    assert_equal 'testing', Tpkg::OS::Debian.new.os_version
    res.setcode(lambda {'testing/unstable'})
    assert_equal 'testing', Tpkg::OS::Debian.new.os_version
    
    # Test fallback to lsbdistrelease
    res = Facter::Util::Resolution.new('lsbdistrelease')
    res.setcode(lambda {'6.0.7'})
    Facter.expects(:[]).with('lsbmajdistrelease').returns(nil)
    Facter.expects(:[]).with('lsbdistrelease').returns(res).at_least_once
    assert_equal '6', Tpkg::OS::Debian.new.os_version
  end
end
