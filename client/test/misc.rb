#!/usr/bin/ruby -w

#
# Tests for various methods that don't fit in anywhere else
#

require 'test/unit'
require 'tpkgtest'
require 'tempfile'
require 'fileutils'
require 'etc'
require 'webrick'
require 'webrick/https'

class TpkgMiscTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    @tempoutdir = Tempdir.new("tempoutdir")
    # Make up our regular test package
    @pkgfile = make_package(:output_directory => @tempoutdir)
  end
  
  def test_package_toplevel_directory
    # Verify normal operation
    assert_equal('testpkg-1.0-1', Tpkg::package_toplevel_directory(@pkgfile))
    # Verify that it fails on a bogus package due to the unexpected
    # directory structure
    boguspkg = Tempfile.new('tpkgtest')
    bogusdir = Tempdir.new("bogusdir")
    Dir.mkdir(File.join(bogusdir, 'bogus'))
    system("#{Tpkg::find_tar} -cf #{boguspkg.path} #{File.join(bogusdir, 'bogus')}")
    FileUtils.rm_rf(bogusdir)
    assert_raise(RuntimeError) { Tpkg::package_toplevel_directory(boguspkg.path) }
  end
  
  def test_source_to_local_path
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:base => testbase)
    
    srca = 'http://example.com/pkgs'
    srca_as_lp = tpkg.source_to_local_path(srca)
    assert(File.directory?(srca_as_lp))
    
    srcb = 'http://www.example.com/pkgs'
    srcb_as_lp = tpkg.source_to_local_path(srcb)
    assert(File.directory?(srcb_as_lp))
    
    assert_not_equal(srca_as_lp, srcb_as_lp)
    
    FileUtils.rm_rf(testbase)
  end
  
  def test_gethttp
    serverdir = Tempdir.new("serverdir")
    http_server = WEBrick::HTTPServer.new(:Port => 3500, :DocumentRoot => serverdir)
    https_server = WEBrick::HTTPServer.new(
                    :Port => 3501,
                    :DocumentRoot => serverdir,
                    :SSLEnable => true,
                    :SSLVerifyClient => ::OpenSSL::SSL::VERIFY_NONE,
                    :SSLCertName => [ ["CN", "localhost"] ]
                    )
    # There may be an easier way to push WEBrick into the background, but
    # the WEBrick docs are mostly non-existent so I'm taking the quick and
    # dirty route.
    t1 = Thread.new { http_server.start }
    t2 = Thread.new { https_server.start }
    
    assert_kind_of(Net::HTTP, Tpkg::gethttp(URI.parse('http://localhost:3500/pkgs')))
    assert_kind_of(Net::HTTP, Tpkg::gethttp(URI.parse('https://localhost:3501/pkgs')))
    
    http_server.shutdown
    t1.kill
    https_server.shutdown
    t2.kill
    FileUtils.rm_rf(serverdir)
  end
  
  def test_lookup_uid
    assert_equal(0, Tpkg::lookup_uid('0'))
    assert_equal(Process.uid, Tpkg::lookup_uid(Etc.getlogin))
    # Should return 0 if it can't find the specified user
    assert_equal(0, Tpkg::lookup_uid('bogususer'))
  end
  
  def test_lookup_gid
    assert_equal(0, Tpkg::lookup_gid('0'))
    assert_equal(Process.gid, Tpkg::lookup_gid(Etc.getgrgid(Process.gid).name))
    # Should return 0 if it can't find the specified group
    assert_equal(0, Tpkg::lookup_gid('bogusgroup'))
  end
  
  def test_get_os
    # Not quite sure how to test this method
    puts "Tpkg::get_os returns '#{Tpkg::get_os}'"

    # Muck with the returned variable and ensure that doesn't stick
    os = Tpkg::get_os
    goodos = os.dup
    os << 'junk'
    assert_equal(goodos, Tpkg::get_os)
  end
  
  def test_normalize_paths
    testroot = Tempdir.new("testroot")
    FileUtils.mkdir_p(File.join(testroot, 'home', 'tpkg'))
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'))
    files = Tpkg::files_in_package(@pkgfile)
    tpkg.normalize_paths(files)
    assert_equal(files[:root].length + files[:reloc].length, files[:normalized].length)
    assert(files[:normalized].include?(File.join(testroot, 'home', 'tpkg', 'file')))
    FileUtils.rm_rf(testroot)
  end
  
  def test_conflicting_files
    testbase = Tempdir.new("testbase")
    FileUtils.mkdir_p(File.join(testbase, 'home', 'tpkg'))
    tpkg = Tpkg.new(:file_system_root => testbase, :base => File.join('home', 'tpkg'))
    
    pkg1 = make_package(:output_directory => @tempoutdir, :change => { 'version' => '2.0' }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    pkg2 = make_package(:output_directory => @tempoutdir, :change => { 'version' => '3.0' }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    # The check for conflicting files shouldn't complain when nothing
    # else is installed
    conflicts = tpkg.conflicting_files(pkg1)
    assert(conflicts.empty?)
    tpkg.install(pkg1)
    # The test package has a few files in it.  Since we made two copies of
    # that package the second one should fail the conflict test
    conflicts = tpkg.conflicting_files(pkg2)
    assert(!conflicts.empty?)
    FileUtils.rm_f(pkg1)
    FileUtils.rm_f(pkg2)
    
    # Make a package with non-relocatable files that end up in the same
    # place as relocatable files in an installed package.  That should
    # also raise an error.
    srcdir = Tempdir.new("srcdir")
    FileUtils.mkdir_p(File.join(srcdir, 'root', 'home', 'tpkg'))
    FileUtils.cp(File.join('testpkg', 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.cp(File.join('testpkg', 'reloc', 'file'), File.join(srcdir, 'root', 'home', 'tpkg'))
    rootpkg = make_package(:output_directory => @tempoutdir, :change => { 'version' => '4.0' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    conflicts = tpkg.conflicting_files(rootpkg)
    assert(!conflicts.empty?)
    FileUtils.rm_rf(srcdir)
    FileUtils.rm_f(rootpkg)
    
    FileUtils.rm_rf(testbase)
  end
  def test_prompt_for_conflicting_files
    # Not quite sure how to test this method
  end
  
  def teardown
    FileUtils.rm_f(@pkgfile)
  end
end
