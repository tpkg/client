#!/usr/bin/ruby -w

#
# Test tpkg's basic tar functionality
#

require 'test/unit'
require File.dirname(__FILE__) + '/tpkgtest'

class TpkgTarTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
  end
  
  def test_find_tar
    # Verify that find_tar finds GNU tar or bsdtar
    good_tar = false
    tar = Tpkg::find_tar
    IO.popen("#{tar} --version") do |pipe|
      pipe.each_line do |line|
        if line.include?('GNU tar') || line.include?('bsdtar')
          good_tar = true
        end
      end
    end
    assert(good_tar, 'find_tar returns GNU tar or bsdtar')    
    
    # Muck with ENV['PATH'] and verify that find_tar throws an exception
    Tpkg.clear_cached_tar
    oldpath = ENV['PATH']
    ENV['PATH'] = Tempfile.new('tpkgtest').path
    assert_raise(RuntimeError, 'find tar with bogus path') { Tpkg::find_tar }
    ENV['PATH'] = oldpath

    # Muck with the returned variable and ensure that doesn't stick
    tar = Tpkg::find_tar
    goodtar = tar.dup
    tar << 'junk'
    assert_equal(goodtar, Tpkg::find_tar)
  end
  
  def test_clear_cached_tar
    tar = Tpkg::find_tar
    Tpkg::clear_cached_tar
    pathdir = Tempdir.new("pathdir")
    mytar = File.join(pathdir, 'tar')
    File.symlink(tar, mytar)
    oldpath = ENV['PATH']
    ENV['PATH'] = "#{pathdir}:#{oldpath}"
    assert_equal(mytar, Tpkg::find_tar)
    Tpkg::clear_cached_tar
    ENV['PATH'] = oldpath
    FileUtils.rm_rf(pathdir)
  end
end

