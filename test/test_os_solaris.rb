#
# Tests Solaris OS abstraction code
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgOSSolarisTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    @pkginfo = File.join(TESTCMDDIR, 'solaris/pkginfo')
    @pkgutil = File.join(TESTCMDDIR, 'solaris/pkgutil')
    @solaris = Tpkg::OS::Solaris.new(
      :pkginfocmd => @pkginfo,
      :pkgutilcmd => @pkgutil,
      )
  end
  
  def test_supported
    res = Facter::Util::Resolution.new('operatingsystem')
    Facter.expects(:[]).with('operatingsystem').returns(res).at_least_once
    res.setcode(lambda {'Solaris'})
    assert Tpkg::OS::Solaris.supported?
    res.setcode(lambda {'Other'})
    refute Tpkg::OS::Solaris.supported?
  end
  def test_initialize
    [:pkginfocmd, :pkgutilcmd].each do |cmdvar|
      solaris = Tpkg::OS::Solaris.new(cmdvar => TESTCMD)
      assert_equal TESTCMD, solaris.instance_variable_get("@#{cmdvar}")
      solaris = Tpkg::OS::Solaris.new(:testcmd => TESTCMD)
      assert_equal TESTCMD, solaris.instance_variable_get("@#{cmdvar}")
    end
    # Test that super is called
    [true, false].each do |debugval|
      solaris = Tpkg::OS::Solaris.new(:debug => debugval)
      assert_equal debugval, solaris.instance_variable_get(:@debug)
    end
  end
  def test_init_links
    correct = (2..3).collect{|i| "/etc/rc#{i}.d/S99script"}
    assert_equal correct, @solaris.init_links('/path/to/init/script', {:init => {}})
  end
  def test_available_native_packages
    assert_equal(
      [
        {:metadata=>
          {:name=>'CSWcurl', :version => '7.25.0', :package_version => '2012.04.26'},
          :source=>:native_installed,
          :prefer=>true},
        {:metadata=>
          {:name=>'CSWcurl', :version => '7.25.0', :package_version => '2012.04.26'},
          :source=>:native_available},
      ],
      @solaris.available_native_packages('CSWcurl'))
    assert_equal(
      [
        {:metadata=>
          {:name=>'CSWwget', :version=>'1.13.4', :package_version=>'2012.05.12'},
          :source=>:native_available},
      ],
      @solaris.available_native_packages('CSWwget'))
    assert_equal(
      [
        {:metadata=>
          {:name=>'SUNWzfsu', :version=>'11.10.0', :package_version=>'2006.05.18.01.46'},
          :source=>:native_installed,
          :prefer=>true},
      ],
      @solaris.available_native_packages('SUNWzfsu'))
    assert_equal [], @solaris.available_native_packages('bogus')
  end
  def test_native_pkg_to_install_string
    assert_equal 'pkg-1.0,REV=1', @solaris.native_pkg_to_install_string({:metadata => {:name => 'pkg', :version => '1.0', :package_version => '1'}})
    assert_equal 'pkg-1.0', @solaris.native_pkg_to_install_string({:metadata => {:name => 'pkg', :version => '1.0'}})
  end
  def test_install_native_package
    @solaris.expects(:system).with("#{@pkgutil} -y -i CSWcurl-7.25.0,REV=2012.04.26")
    @solaris.install_native_package({:metadata => {:name => 'CSWcurl', :version => '7.25.0', :package_version => '2012.04.26'}})
  end
  def test_upgrade_native_package
    @solaris.expects(:system).with("#{@pkgutil} -y -u CSWcurl-7.25.0,REV=2012.04.26")
    @solaris.upgrade_native_package({:metadata => {:name => 'CSWcurl', :version => '7.25.0', :package_version => '2012.04.26'}})
  end
end
