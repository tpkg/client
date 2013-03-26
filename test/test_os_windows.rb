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
    res = Facter::Util::Resolution.new('operatingsystem')
    Facter.expects(:[]).with('operatingsystem').returns(res).at_least_once
    res.setcode(lambda {'windows'})
    assert Tpkg::OS::Windows.supported?
    res.setcode(lambda {'Other'})
    refute Tpkg::OS::Windows.supported?
  end
  
  def test_sudo_default
    refute @windows.sudo_default?
  end
end
