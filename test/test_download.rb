#
# Test tpkg's ability to download packages
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))
require 'webrick'

class TpkgDownloadTests < Test::Unit::TestCase
  include TpkgTests

  def setup
    Tpkg::set_prompt(false)

    # Make up our regular test package
    @pkgfile = make_package

    # Copy the package into a directory to test directory-related operations
    @pkgdir = Dir.mktmpdir('pkgdir')
    FileUtils.cp(@pkgfile, @pkgdir)
  end

  def test_download
    Tpkg::extract_metadata(@pkgdir)

    s = WEBrick::HTTPServer.new(:Port => 3500, :DocumentRoot => @pkgdir)
    # There may be an easier way to push WEBrick into the background, but
    # the WEBrick docs are mostly non-existent so I'm taking the quick and
    # dirty route.
    t = Thread.new { s.start }

    Dir.mktmpdir('testbase') do |testbase|
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
    end

    s.shutdown
    t.kill
  end

  def test_download_pkgs
    # set up multiple packages
    ['pkga', 'pkgb'].each do |name|
      pkgfile = make_package(:change => {'name' => name}, :remove => ['operatingsystem', 'architecture'])
      FileUtils.cp(pkgfile, @pkgdir)
    end

    Tpkg::extract_metadata(@pkgdir)

    s = WEBrick::HTTPServer.new(:Port => 3500, :DocumentRoot => @pkgdir)
    # There may be an easier way to push WEBrick into the background, but
    # the WEBrick docs are mostly non-existent so I'm taking the quick and
    # dirty route.
    t = Thread.new { s.start }

    Dir.mktmpdir('testbase') do |testbase|
      Dir.mktmpdir('destdir') do |destdir|
        source = 'http://localhost:3500/'
        tpkg = Tpkg.new(:base => testbase, :sources => [source])

        # Try to request a download of a non-existing package
        result = tpkg.download_pkgs(['non-existing'], {:out => destdir})
        assert_equal(Tpkg::GENERIC_ERR, result)

        # Try to request a download of existing packages
        result = tpkg.download_pkgs(['pkga', 'pkgb'], {:out => destdir})
        assert_equal(0, result)
        assert_equal(2, Dir.glob(File.join(destdir, '*')).size)  # we have downloaded 2 packages
      end
    end

    s.shutdown
    t.kill
  end

  def teardown
    FileUtils.rm_f(@pkgfile)
    FileUtils.rm_rf(@pkgdir)
  end
end
