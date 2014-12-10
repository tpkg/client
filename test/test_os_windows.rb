#
# Tests Windows OS abstraction code
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgOSWindowsTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    @windows = Tpkg::OS::Windows.new
  end
  
  def test_supported
    fact = Facter::Util::Fact.new('operatingsystem')
    Facter.expects(:[]).with('operatingsystem').returns(fact).at_least_once
    fact.stubs(:value).returns('windows')
    assert Tpkg::OS::Windows.supported?
    fact.stubs(:value).returns('Other')
    refute Tpkg::OS::Windows.supported?
  end
  
  def test_sudo_default
    refute @windows.sudo_default?
  end
end
