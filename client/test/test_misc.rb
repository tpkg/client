#
# Tests for various methods that don't fit in anywhere else
#

require File.dirname(__FILE__) + '/tpkgtest'
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
    
    @testroot = Tempdir.new("testroot")
  end
  
  def test_package_toplevel_directory
    # Verify normal operation
    assert_equal('testpkg-1.0-1-os-architecture', Tpkg::package_toplevel_directory(@pkgfile))
    # Verify that it fails on a bogus package due to the unexpected
    # directory structure
    boguspkg = Tempfile.new('tpkgtest')
    bogusdir = Tempdir.new("bogusdir")
    Dir.mkdir(File.join(bogusdir, 'bogus'))
    system("#{Tpkg::find_tar} -cf #{boguspkg.path} #{File.join(bogusdir, 'bogus')}")
    FileUtils.rm_rf(bogusdir)
    assert_raise(RuntimeError) { Tpkg::package_toplevel_directory(boguspkg.path) }
  end
  
  def test_source_to_local_directory
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:base => testbase)
    
    srca = 'http://example.com/pkgs'
    srca_as_ld = tpkg.source_to_local_directory(srca)
    
    srcb = 'http://www.example.com/pkgs'
    srcb_as_ld = tpkg.source_to_local_directory(srcb)
    
    assert_not_equal(srca_as_ld, srcb_as_ld)
    
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
    
    # This is necessary to ensure that any SSL configuration in /etc/tpkg
    # doesn't throw us off
    tpkg = Tpkg.new(:file_system_root => @testroot)
    
    assert_kind_of(Net::HTTP, tpkg.gethttp(URI.parse('http://localhost:3500/pkgs')))
    assert_kind_of(Net::HTTP, tpkg.gethttp(URI.parse('https://localhost:3501/pkgs')))
    
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
  
  def test_clean_for_filename
    assert_equal('redhat5', Metadata.clean_for_filename('RedHat-5'))
    assert_equal('i386', Metadata.clean_for_filename('i386'))
    assert_equal('x86_64', Metadata.clean_for_filename('x86_64'))
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
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.cp(File.join(TESTPKGDIR, 'reloc', 'file'), File.join(srcdir, 'root', 'home', 'tpkg'))
    rootpkg = make_package(:output_directory => @tempoutdir, :change => { 'version' => '4.0' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    conflicts = tpkg.conflicting_files(rootpkg)
    assert(!conflicts.empty?)
    FileUtils.rm_rf(srcdir)
    FileUtils.rm_f(rootpkg)
    
    FileUtils.rm_rf(testbase)
  end

  def test_predict_file_permissions_and_ownership
    testbase = Tempdir.new("testbase")
    FileUtils.mkdir_p(File.join(testbase, 'home', 'tpkg'))
    tpkg = Tpkg.new(:file_system_root => testbase, :base => File.join('home', 'tpkg'))

    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
    file_contents = 'Hello world'
    File.open(File.join(srcdir, 'reloc', 'myfile'), 'w') do |file|
      file.puts(file_contents)
    end

    File.chmod(0623, File.join(srcdir, 'reloc', 'myfile'))

    # TODO: change ownership
    # no file_defaults settings, no file posix defined, then use whatever the current 
    # perms and ownership of the file
    pkg1 = make_package(:output_directory => @tempoutdir, :source_directory => srcdir, :change => { 'name' => 'pkg1' }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    metadata = Tpkg::metadata_from_package(pkg1)
    data = {:actual_file => File.join(srcdir, 'reloc', 'myfile')}
    predicted_perms, predicted_uid, predicted_gid = Tpkg::predict_file_perms_and_ownership(data)
    tpkg.install(pkg1)
    assert_equal(predicted_perms.to_i, File.stat(File.join(testbase, 'home', 'tpkg', 'myfile')).mode & predicted_perms.to_i)
    # Can't test these because unit test are not run as sudo. The default file ownership wont be correct
    # assert(File.stat(File.join(testbase, 'home', 'tpkg', 'myfile')).uid, predicted_uid)
    # assert(File.stat(File.join(testbase, 'home', 'tpkg', 'myfile')).gid, predicted_gid)
    tpkg.remove('pkg1')

    # if metadata has file_defaults settings and nothing else, then use that
    pkg2 = make_package(:output_directory => @tempoutdir, :source_directory => srcdir, :change => { 'name' => 'pkg2' }, :file_defaults => { 'perms' => '0654', 'owner' => Etc.getlogin, 'group' => Etc.getpwnam(Etc.getlogin).gid}, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    metadata = Tpkg::metadata_from_package(pkg2)
    data = {:actual_file => File.join(srcdir, 'reloc', 'myfile'), :metadata => metadata}
    predicted_perms, predicted_uid, predicted_gid = Tpkg::predict_file_perms_and_ownership(data)
    tpkg.install(pkg2)
    assert_equal(File.stat(File.join(testbase, 'home', 'tpkg', 'myfile')).mode & predicted_perms.to_i, predicted_perms.to_i)
    assert_equal(File.stat(File.join(testbase, 'home', 'tpkg', 'myfile')).uid, predicted_uid)
    assert_equal(File.stat(File.join(testbase, 'home', 'tpkg', 'myfile')).gid, predicted_gid)
    tpkg.remove('pkg2')

    # if metadata has the file perms & ownership explicitly defined, then that override everything
    pkg3 = make_package(:output_directory => @tempoutdir, :source_directory => srcdir, :change => { 'name' => 'pkg3' }, :file_defaults => { 'perms' => '0654', 'owner' => Etc.getlogin, 'group' => Etc.getpwnam(Etc.getlogin).gid}, :files => { 'myfile' => {'perms' => '0733'}}, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    metadata = Tpkg::metadata_from_package(pkg3)
    file_metadata = {:posix => { :perms => 0733}}
    data = {:actual_file => File.join(srcdir, 'reloc', 'myfile'), :metadata => metadata, :file_metadata => file_metadata}
    predicted_perms, predicted_uid, predicted_gid = Tpkg::predict_file_perms_and_ownership(data)
    tpkg.install(pkg3)
    assert_equal(File.stat(File.join(testbase, 'home', 'tpkg', 'myfile')).mode & predicted_perms.to_i, predicted_perms.to_i)
    assert_equal(File.stat(File.join(testbase, 'home', 'tpkg', 'myfile')).uid, predicted_uid)
    assert_equal(File.stat(File.join(testbase, 'home', 'tpkg', 'myfile')).gid, predicted_gid)
    tpkg.remove('pkg3')
  end

  def test_prompt_for_conflicting_files
    # Not quite sure how to test this method
  end

  def test_prompt_for_install
    # Not quite sure how to test this method
  end

  def test_valid_pkg_filename
    # we currently accepts all string for filename as long as it
    # doesn't begin with a do, t
    valid_filenames = ['a.tpkg', 'pkg_with_no_extension', '_valid_pkg', './path/to/package.tpkg']
    invalid_filenames = ['.invalid_pkg', '..invalid_pkg']

    valid_filenames.each do |filename|
      assert(Tpkg::valid_pkg_filename?(filename))
    end
    invalid_filenames.each do |filename|
      assert(!Tpkg::valid_pkg_filename?(filename))
    end
  end
  
  def test_run_external
    extname = 'testext'
    extdata = "This is a test of an external hook\nwith multiple lines\nof data"
    testroot = Tempdir.new("testroot")
    relative_base = File.join('home', 'tpkg')
    testbase = File.join(testroot, relative_base)
    FileUtils.mkdir_p(testbase)
    # Make an external script which writes the arguments and data it receives
    # to a temporary file, so that we can verify the external script received
    # them properly.
    exttmpfile = Tempfile.new('tpkgtest_external')
    externalsdir = File.join(testroot, 'usr', 'lib', 'tpkg', 'externals')
    FileUtils.mkdir_p(externalsdir)
    extscript = File.join(externalsdir, extname)
    File.open(extscript, 'w') do |file|
      file.puts('#!/bin/sh')
      # Package filename
      file.puts("echo $1 > #{exttmpfile.path}")
      # Operation (install/remove)
      file.puts("echo $2 >> #{exttmpfile.path}")
      # TPKG_HOME environment variable
      file.puts("echo $TPKG_HOME >> #{exttmpfile.path}")
      # Data
      file.puts("cat >> #{exttmpfile.path}")
    end
    File.chmod(0755, extscript)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => relative_base)
    
    # Test install
    assert_nothing_raised { tpkg.run_external('pkgfile', :install, extname, extdata) }
    assert_equal("pkgfile\ninstall\n#{testbase}\n#{extdata}", IO.read(exttmpfile.path))
    # Test remove
    assert_nothing_raised { tpkg.run_external('pkgfile', :remove, extname, extdata) }
    assert_equal("pkgfile\nremove\n#{testbase}\n#{extdata}", IO.read(exttmpfile.path))
    
    # A non-existent external raises an exception
    File.delete(extscript)
    assert_raise(RuntimeError) { tpkg.run_external('pkgfile', :install, extname, extdata) }
    # A non-executable external raises an exception
    File.open(extscript, 'w') do |file|
      file.puts('#!/bin/sh')
      file.puts("exit 0")
    end
    File.chmod(0644, extscript)
    assert_raise(RuntimeError) { tpkg.run_external('pkgfile', :install, extname, extdata) }
    # An external that exits non-zero should raise an exception
    File.open(extscript, 'w') do |file|
      file.puts('#!/bin/sh')
      file.puts("exit 1")
    end
    File.chmod(0755, extscript)
    assert_raise(RuntimeError) { tpkg.run_external('pkgfile', :install, extname, extdata) }
    # An invalid operation should raise an exception
    assert_raise(RuntimeError) { tpkg.run_external('pkgfile', :bogus, extname, extdata) }
    # An invalid external name should raise an exception
    assert_raise(RuntimeError) { tpkg.run_external('pkgfile', :install, 'bogus', extdata) }
    FileUtils.rm_rf(testroot)
  end
  
  def test_wrap_exception
    original_message = 'original message'
    original_backtrace = ['a', 'b']
    e = StandardError.new(original_message)
    e.set_backtrace(original_backtrace)
    new_message = 'new message'
    eprime = Tpkg.wrap_exception(e, new_message)
    assert_equal(StandardError, eprime.class)
    assert_equal(new_message, eprime.message)
    assert_equal(original_backtrace, eprime.backtrace)
  end
  
  def teardown
    FileUtils.rm_f(@pkgfile)
  end
end
