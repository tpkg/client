

#
# Test tpkg's ability to execute init scripts
#

require File.dirname(__FILE__) + '/tpkgtest'

class TpkgInitScriptsTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    @tempoutdir = Tempdir.new("tempoutdir")  # temp dir that will automatically get deleted at end of test run
                                             # can be used for storing packages
    # Make up a package with both relocatable and non-relocatable
    # directory trees so that we can ensure both types are unpacked
    # properly.
    srcdir = Tempdir.new("srcdir")
    # The stock test package has a reloc directory we can use
    system("#{Tpkg::find_tar} -C #{TESTPKGDIR} --exclude .svn -cf - . | #{Tpkg::find_tar} -C #{srcdir} -xf -")
    # Then add a root directory
    FileUtils.mkdir_p(File.join(srcdir, 'root', 'etc'))
    File.open(File.join(srcdir, 'root', 'etc', 'rootfile'), 'w') do |file|
      file.puts "Hello"
    end
    @pkgfile = make_package(:output_directory => @tempoutdir, :source_directory => srcdir, :files => {'/etc/rootfile' => {'perms' => '0666'}}, :remove => ['posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
  end
  
  # Test init script start/stop init scripts in correct order
  def test_order
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
    tmpfile = Tempfile.new('initscripttest')
    (1..3).each do | i |
      File.open(File.join(srcdir, 'reloc', "myinit#{i}"), 'w') do |file|
        file.puts("#!/bin/sh\necho myinit#{i} >> #{tmpfile.path}")
      end
      File.chmod(0755, File.join(srcdir, 'reloc', "myinit#{i}"))
    end

    pkg  = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'initpkg'  }, :source_directory => srcdir, 
                        :files => { "myinit1" => { 'init' => {'start' => '1' }} , "myinit2" => { 'init' => {'start' => '2' }}, "myinit3" => { 'init' => {'start' => '3' }}}, 
                        :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
    metadata  = Tpkg::metadata_from_package(pkg)
    begin
      tpkg.install([pkg], PASSPHRASE)
      tpkg.init_links(metadata).each do |link, init_script|
        assert(File.symlink?(link))
        assert_equal(init_script, File.readlink(link))
      end

      # check that init scripts are started in correct order
      tpkg.execute_init(["initpkg"], "start")
      lines = File.open(tmpfile.path).readlines
      assert_equal("myinit1", lines[0].chomp)
      assert_equal("myinit2", lines[1].chomp)
      assert_equal("myinit3", lines[2].chomp)

      # clear out the file
      system("cat /dev/null > #{tmpfile.path}")
      # check that init scripts are stopped in correct order
      tpkg.execute_init(["initpkg"], "stop")
      lines = File.open(tmpfile.path).readlines
      assert_equal("myinit3", lines[0].chomp)
      assert_equal("myinit2", lines[1].chomp)
      assert_equal("myinit1", lines[2].chomp)

    rescue RuntimeError => e
      if e.message =~ /No init script support/
        warn "No init script support on this platform, init script handling will not be tested (#{e.message})"
      else
        raise
      end
    end
    FileUtils.rm_rf(testroot)
    FileUtils.rm_f(pkg)
  end
  
  def teardown
    FileUtils.rm_f(@pkgfile)
  end
end

