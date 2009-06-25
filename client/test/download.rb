#!/usr/bin/ruby -w

#
# Test tpkg's ability to download packages
#

require 'test/unit'
require 'tpkgtest'
require 'tempfile'
require 'webrick'

class TpkgDownloadTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    # Make up our regular test package
    @pkgfile = make_package
    
    # Copy the package into a directory to test directory-related operations
    @pkgdir = Tempdir.new("pkgdir")
    FileUtils.cp(@pkgfile, @pkgdir)
  end
  
  def test_download
    Tpkg::extract_metadata(@pkgdir)
    
    s = WEBrick::HTTPServer.new(:Port => 3500, :DocumentRoot => @pkgdir)
    # There may be an easier way to push WEBrick into the background, but
    # the WEBrick docs are mostly non-existent so I'm taking the quick and
    # dirty route.
    t = Thread.new { s.start }
    
    testbase = Tempdir.new("testbase")
    source = 'http://localhost:3500/'
    tpkg = Tpkg.new(:base => testbase, :sources => [source])
    # Download and verify
    assert_nothing_raised { tpkg.download(source, File.basename(@pkgfile)) }
    localpath = File.join(tpkg.source_to_local_directory(source), File.basename(@pkgfile))
    assert(File.exist?(localpath))
    assert_equal(0644, File.stat(localpath).mode & 07777)
    assert(Tpkg::verify_package_checksum(localpath))
    
    # Mess with the package so that it doesn't verify, then confirm that
    # calling download again re-downloads it
    File.open(localpath, 'w') do |file|
      file.puts "Bogus package now"
    end
    assert_raise(RuntimeError, NoMethodError) { Tpkg::verify_package_checksum(localpath) }
    assert_nothing_raised { tpkg.download(source, File.basename(@pkgfile)) }
    assert(File.exist?(localpath))
    assert(Tpkg::verify_package_checksum(localpath))
    
    FileUtils.rm_rf(testbase)
    s.shutdown
    t.kill
  end
  
  def teardown
    FileUtils.rm_f(@pkgfile)
    FileUtils.rm_rf(@pkgdir)
  end
end
