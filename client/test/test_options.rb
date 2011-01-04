

#
# Test tpkg command line options
#

require File.dirname(__FILE__) + '/tpkgtest'

class TpkgOptionTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
  end
  
  def test_help
    output = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    IO.popen("ruby -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --help") do |pipe|
      output = pipe.readlines
    end
    # Make sure at least something resembling help output is there
    assert(output.any? {|line| line.include?('Usage: tpkg')}, 'help output content')
    # Make sure it fits on the screen
    assert(output.all? {|line| line.length <= 80}, 'help output columns')
    # Too many options for 23 lines
    #assert(output.size <= 23, 'help output lines')
  end
  
  def test_qenv
    output = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    IO.popen("ruby -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --qenv") do |pipe|
      output = pipe.readlines
    end
    # Make sure the expected lines are there
    assert(output.any? {|line| line.include?('Operating System:')})
    assert(output.any? {|line| line.include?('Architecture:')})
  end
  
  def test_qconf
    output = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    IO.popen("ruby -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --qconf") do |pipe|
      output = pipe.readlines
    end
    # Make sure the expected lines are there
    assert(output.any? {|line| line.include?('Base:')})
    assert(output.any? {|line| line.include?('Sources:')})
    assert(output.any? {|line| line.include?('Report server:')})
  end
  
  def test_use_ssh_key
    # Test --use-ssh-key with argument
    # Test --use-ssh-key without argument
  end
  
  def teardown
  end
end

