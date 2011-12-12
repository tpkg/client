#
# Test tpkg's basic tar functionality
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgTarTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg.set_prompt(false)
  end
  
  def test_find_tar
    # Verify that find_tar finds GNU tar or bsdtar
    good_tar = false
    tar = Tpkg.find_tar
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
    begin
      ENV['PATH'] = Tempfile.new('tpkgtest').path
      Tpkg.clear_cached_tar
      assert_raise(RuntimeError, 'find tar with bogus path') { Tpkg.find_tar }
    ensure
      ENV['PATH'] = oldpath
    end
    
    # Muck with the returned variable and ensure that doesn't stick
    tar = Tpkg.find_tar
    goodtar = tar.dup
    tar << 'junk'
    assert_equal(goodtar, Tpkg.find_tar)
    
    # Verify that the returned path is wrapped in quotes if it contains spaces
    testdirtmp = Tempfile.new('tpkgtest')
    testdir = testdirtmp.path
    testdirtmp.close
    File.unlink(testdir)
    testsubdir = File.join(testdir, 'a b')
    FileUtils.mkdir_p(testsubdir)
    Tpkg.clear_cached_tar
    tar = Tpkg.find_tar
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
    begin
      ENV['PATH'] = testsubdir
      expected_tar_path = nil
      if RUBY_PLATFORM == 'i386-mingw32'
        expected_tar_path =
          testsubdir.gsub('/', '\\') + '\\' + File.basename(tar)
      else
        expected_tar_path = File.join(testsubdir, File.basename(tar))
      end
      assert_equal('"' + expected_tar_path + '"', Tpkg.find_tar)
      FileUtils.rm_rf(testdir)
    ensure
      ENV['PATH'] = oldpath
    end
    Tpkg.clear_cached_tar
  end
  
  def test_clear_cached_tar
    tar = Tpkg.find_tar
    Tpkg.clear_cached_tar
    Dir.mktmpdir('pathdir') do |pathdir|
      mytar = File.join(pathdir, 'tar')
      File.symlink(tar, mytar)
      oldpath = ENV['PATH']
      begin
        ENV['PATH'] = "#{pathdir}:#{oldpath}"
        assert_equal(mytar, Tpkg.find_tar)
      ensure
        ENV['PATH'] = oldpath
      end
    end
    Tpkg.clear_cached_tar
  end
end

