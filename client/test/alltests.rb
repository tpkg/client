#!/usr/bin/ruby -w

#
# Run all of the tpkg unit tests
#

require 'test/unit'
Dir.foreach('.') do |entry|
  next unless entry =~ /\.rb$/
  # Skip this file
  next if entry == 'alltests.rb'
  # And the shared file
  next if entry == 'tpkgtest.rb'

  require entry
end

