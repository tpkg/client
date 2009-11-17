#!/usr/bin/ruby -w

#
# Test tpkg command line options
#

require 'test/unit'
require 'tpkgtest'
require 'fileutils'

class TpkgOptionTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
  end
  
  def test_help
    output = nil
    IO.popen("ruby ../tpkg --help") do |pipe|
      output = pipe.readlines
    end
    # Make sure at least something resembling help output is there
    assert(output.any? {|line| line.include?('Usage: tpkg')}, 'help output content')
    # Make sure it fits on the screen
    assert(output.all? {|line| line.length <= 80}, 'help output columns')
    # Too many options for 23 lines
    #assert(output.size <= 23, 'help output lines')
  end
  
  def teardown
  end
end

