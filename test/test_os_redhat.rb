#
# Tests Red Hat OS abstraction code
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

# Make private methods public so that we can test them
class Tpkg::OS::RedHat
  public :create_rpm
end

class TpkgOSRedHatTests < Test::Unit::TestCase
  include TpkgTests

  def setup
    @redhat = Tpkg::OS::RedHat.new(
      :yumcmd => File.join(TESTCMDDIR, 'redhat/yum'),
      )
  end

  def test_supported
    fact = Facter::Util::Fact.new('operatingsystem')
    Facter.stubs(:[]).returns(fact)
    fact.stubs(:value).returns('RedHat')
    assert Tpkg::OS::RedHat.supported?
    fact.stubs(:value).returns('CentOS')
    assert Tpkg::OS::RedHat.supported?
    fact.stubs(:value).returns('Fedora')
    assert Tpkg::OS::RedHat.supported?
    fact.stubs(:value).returns('Other')
    refute Tpkg::OS::RedHat.supported?
  end
  def test_initialize
    [:yumcmd, :rpmcmd, :rpmbuildcmd].each do |cmdvar|
      redhat = Tpkg::OS::RedHat.new(cmdvar => TESTCMD)
      assert_equal TESTCMD, redhat.instance_variable_get("@#{cmdvar}")
      redhat = Tpkg::OS::RedHat.new(:testcmd => TESTCMD)
      assert_equal TESTCMD, redhat.instance_variable_get("@#{cmdvar}")
    end
    [true, false].each do |quietval|
      redhat = Tpkg::OS::RedHat.new(:quiet => quietval)
      assert_equal quietval, redhat.instance_variable_get(:@quiet)
    end
    # Test that super is called
    [true, false].each do |debugval|
      redhat = Tpkg::OS::RedHat.new(:debug => debugval)
      assert_equal debugval, redhat.instance_variable_get(:@debug)
    end
  end
  def test_init_links
    correct = (2..5).collect{|i| "/etc/rc.d/rc#{i}.d/S99script"}
    assert_equal correct, @redhat.init_links('/path/to/init/script', {:init => {}})
  end
  def test_cron_dot_d_directory
    assert_equal '/etc/cron.d', @redhat.cron_dot_d_directory
  end
  def test_available_native_packages
    assert_equal(
      [
        {:metadata=>
          {:name=>'curl', :version=>'7.19.7', :package_version=>'26.el6_2.4'},
          :source=>:native_installed,
          :prefer=>true},
      ],
      @redhat.available_native_packages('curl'))
    assert_equal(
      [
        {:metadata=>
          {:name=>'wget', :version=>'1.12', :package_version=>'1.4.el6'},
          :source=>:native_available}
      ],
      @redhat.available_native_packages('wget'))
    assert_equal [], @redhat.available_native_packages('bogus')
  end
  def test_install_native_package
    redhat = Tpkg::OS::RedHat.new
    redhat.expects(:system).with('yum -y install curl-7.19.7-26.el6_2.4')
    redhat.install_native_package(
      {:metadata => {:name => 'curl', :version => '7.19.7', :package_version => '26.el6_2.4'}})
  end
  def test_upgrade_native_package
    redhat = Tpkg::OS::RedHat.new
    redhat.expects(:system).with('yum -y install curl-7.19.7-26.el6_2.4')
    redhat.install_native_package(
      {:metadata => {:name => 'curl', :version => '7.19.7', :package_version => '26.el6_2.4'}})
  end
  def test_stub_native_pkg
    metafile = File.join(TESTPKGDIR, 'tpkg-nativedeps.yml')
    metatext = File.read(metafile)
    metadata = Metadata.new(metatext, 'yml')
    redhat = Tpkg::OS::RedHat.new(
      :rpmbuildcmd => File.join(TESTCMDDIR, 'redhat/rpmbuild'))
    redhat.expects(:create_rpm).returns('/path/to/rpm.rpm')
    redhat.expects(:system).with('rpm -i /path/to/rpm.rpm')
    redhat.stub_native_pkg({:metadata => metadata})
  end
  def test_remove_native_stub_pkg
    metafile = File.join(TESTPKGDIR, 'tpkg-nativedeps.yml')
    metatext = File.read(metafile)
    metadata = Metadata.new(metatext, 'yml')
    redhat = Tpkg::OS::RedHat.new
    redhat.expects(:system).with('yum -y remove stub_for_testpkg')
    redhat.remove_native_stub_pkg({:metadata => metadata})
  end
  def test_os_version
    fact = Facter::Util::Fact.new('lsbmajdistrelease')
    fact.stubs(:value).returns('6')
    Facter.expects(:[]).with('lsbmajdistrelease').returns(fact).at_least_once
    assert_equal '6', Tpkg::OS::RedHat.new.os_version
  end
  def test_create_rpm
    # Test that rpmbuild is called with reasonable arguments
    redhat = Tpkg::OS::RedHat.new(:quiet => true)
    redhat.expects(:system).
      with(regexp_matches(%r{rpmbuild -bb --define '_topdir .*' .*/SPECS/pkg.spec}))
    redhat.create_rpm('test', [{:name => 'dep1'}, {:name => 'dep2'}])
    # Test that, with a fake rpmbuild, the method produces the expected result
    redhat = Tpkg::OS::RedHat.new(
      :rpmbuildcmd => File.join(TESTCMDDIR, 'redhat/rpmbuild'))
    fakerpm = redhat.create_rpm('test', [{:name => 'dep1'}, {:name => 'dep2'}])
    assert_equal 'This is a fake rpm', File.read(fakerpm)
    FileUtils.rm_f(fakerpm)
  end
end
