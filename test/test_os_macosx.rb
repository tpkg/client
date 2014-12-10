#
# Tests Mac OS X OS abstraction code
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgOSMacOSXTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    @testport = File.join(TESTCMDDIR, 'macosx/port')
    @macosx = Tpkg::OS::MacOSX.new(
      :portcmd => @testport,
      )
  end
  
  def test_supported
    fact = Facter::Util::Fact.new('operatingsystem')
    Facter.expects(:[]).with('operatingsystem').returns(fact).at_least_once
    fact.stubs(:value).returns('Darwin')
    assert Tpkg::OS::MacOSX.supported?
    fact.stubs(:value).returns('Other')
    refute Tpkg::OS::MacOSX.supported?
  end
  def test_initialize
    [:portcmd].each do |cmdvar|
      macosx = Tpkg::OS::MacOSX.new(cmdvar => TESTCMD)
      assert_equal TESTCMD, macosx.instance_variable_get("@#{cmdvar}")
      macosx = Tpkg::OS::MacOSX.new(:testcmd => TESTCMD)
      assert_equal TESTCMD, macosx.instance_variable_get("@#{cmdvar}")
    end
    # Test that super is called
    [true, false].each do |debugval|
      macosx = Tpkg::OS::MacOSX.new(:debug => debugval)
      assert_equal debugval, macosx.instance_variable_get(:@debug)
    end
  end
  def test_available_native_packages
    assert_equal(
      [
        {:metadata=>
          {:name=>'curl', :version=>'7.27.0', :package_version=>'1'},
          :source=>:native_installed,
          :prefer=>true},
        {:metadata=>
          {:name=>'curl', :version=>'7.28.1'},
          :source=>:native_available},
      ],
      @macosx.available_native_packages('curl'))
    assert_equal(
      [
        {:metadata=>
          {:name=>'ruby186', :version=>'1.8.6-p420'},
          :source=>:native_available}
      ],
      @macosx.available_native_packages('ruby186'))
    assert_equal [], @macosx.available_native_packages('bogus')
  end
  def test_native_pkg_to_install_string
    assert_equal 'pkg', @macosx.native_pkg_to_install_string({:metadata => {:name => 'pkg', :version => '1.0', :package_version => '1'}})
    assert_equal 'pkg', @macosx.native_pkg_to_install_string({:metadata => {:name => 'pkg', :version => '1.0'}})
  end
  def test_install_native_package
    @macosx.expects(:system).with("#{@testport} install curl")
    @macosx.install_native_package(
      {:metadata => {:name => 'curl', :version => '7.28.1'}})
  end
  def test_upgrade_native_package
    @macosx.expects(:system).with("#{@testport} upgrade curl")
    @macosx.upgrade_native_package(
      {:metadata => {:name => 'curl', :version => '7.28.1', :package_version => '7'}})
  end
  def test_os_version
    fact = Facter::Util::Fact.new('macosx_productversion')
    Facter.expects(:[]).with('macosx_productversion').returns(fact).at_least_once
    fact.stubs(:value).returns('10.8.2')
    assert_equal '10.8', Tpkg::OS::MacOSX.new.os_version
  end
end
