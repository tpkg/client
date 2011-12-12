#
# Test tpkg's basic tar functionality
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

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
    oldpath = ENV['PATH']
    ENV['PATH'] = Tempfile.new('tpkgtest').path
    Tpkg.clear_cached_tar
    assert_raise(RuntimeError, 'find tar with bogus path') { Tpkg::find_tar }
    ENV['PATH'] = oldpath

    # Muck with the returned variable and ensure that doesn't stick
    tar = Tpkg::find_tar
    goodtar = tar.dup
    tar << 'junk'
    assert_equal(goodtar, Tpkg::find_tar)

    # Verify that the returned path is wrapped in quotes if it contains spaces
    testdirtmp = Tempfile.new('tpkgtest')
    testdir = testdirtmp.path
    testdirtmp.close
    File.unlink(testdir)
    testsubdir = File.join(testdir, 'a b')
    FileUtils.mkdir_p(testsubdir)
    Tpkg.clear_cached_tar
    tar = Tpkg::find_tar
    tar.sub!(/^"/, '')
    tar.sub!(/"$/, '')
    FileUtils.cp(tar, testsubdir)
    if File.basename(tar) == 'bsdtar.exe'
      # Dir.glob and Windows-style paths with \ seem incompatible, even with
      # File::FNM_NOESCAPE
      tardir = File.dirname(tar).gsub('\\', '/')
      Dir.glob(File.join(tardir, '*.dll')).each do |dll|
        FileUtils.cp(dll, testsubdir)
      end
    end
    Tpkg.clear_cached_tar
    oldpath = ENV['PATH']
    ENV['PATH'] = testsubdir
    assert_equal(
      '"' + testsubdir.gsub('/', '\\') + '\\' + File.basename(tar) + '"',
      Tpkg::find_tar)
    FileUtils.rm_rf(testdir)
    ENV['PATH'] = oldpath
  end
  
  def test_clear_cached_tar
    tar = Tpkg::find_tar
    Tpkg::clear_cached_tar
    Dir.mktmpdir('pathdir') do |pathdir|
      mytar = File.join(pathdir, 'tar')
      File.symlink(tar, mytar)
      oldpath = ENV['PATH']
      ENV['PATH'] = "#{pathdir}:#{oldpath}"
      assert_equal(mytar, Tpkg::find_tar)
      Tpkg::clear_cached_tar
      ENV['PATH'] = oldpath
    end
  end

  def cleanup
    # Given the tests in this file this seems like a good idea so that we
    # don't leave things in a weird state
    Tpkg.clear_cached_tar
  end
end

