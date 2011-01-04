#
# Test tpkg command line options
#

require File.dirname(__FILE__) + '/tpkgtest'
require 'open3'

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
    error = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    Open3.popen3("ruby -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} -s shell.sourceforge.net --use-ssh-key no_such_file --no-sudo --version") do |stdin, stdout, stderr|
      stdin.close
      error = stderr.readlines
    end
    # Make sure the expected lines are there
    assert(error.any? {|line| line.include?('Unable to read ssh key from no_such_file')})
    
    # Test --use-ssh-key without argument
    output = nil
    error = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    Open3.popen3("ruby -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} -s shell.sourceforge.net --use-ssh-key --version") do |stdin, stdout, stderr|
      stdin.close
      output = stdout.readlines
      error = stderr.readlines
    end
    # Make sure that tpkg didn't prompt for a password
    assert(!output.any? {|line| line.include?('SSH Password (leave blank if using ssh key):')})
    
    # Just to make sure our previous test is valid, check that we are prompted
    # for a password if we don't specify --use-ssh-key
    output = nil
    error = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    Open3.popen3("ruby -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} -s shell.sourceforge.net --version") do |stdin, stdout, stderr|
      stdin.close
      output = stdout.readlines
      error = stderr.readlines
    end
    # Make sure that tpkg did prompt for a password this time
    assert(output.any? {|line| line.include?('SSH Password (leave blank if using ssh key):')})
  end
  
  def teardown
  end
end

