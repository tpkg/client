require "./#{File.dirname(__FILE__)}/tpkgtest"

class TpkgFileMetadataTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    # Make up our regular test package
    @pkgfile = make_package(:remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'], :files => {'file' => {'perms' => '0641'}})
  end
  
  def test_file_metadata
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])

    assert_nothing_raised { tpkg.install([@pkgfile], PASSPHRASE) }
   
    # check that we can get read file_metadata for the newly installed package
    assert_nothing_raised { @file_metadata = tpkg.file_metadata_for_installed_packages[File.basename(@pkgfile)]}

    # checking content of file_metadata
    assert_equal(@file_metadata[:package_file], File.basename(@pkgfile))

    # check file's ownership and permissions are ok
    assert_nothing_raised { @errors = tpkg.verify_file_metadata("testpkg") }
    puts @errors.inspect
    @errors.each do | file, error |
      assert(error.empty?)
    end

    # modify a file's perms and verify that tpkg can detect it
    File.chmod(07777, File.join(testroot, 'home','tpkg','file'))
    assert_nothing_raised { @errors = tpkg.verify_file_metadata("testpkg")}
    @errors.each do | file, error |
      if File.basename(file) == "file"
        assert(!error.empty?)
      else
        assert(error.empty?)
      end
    end

    # modify a file content and verify that tpkg can detect it
    File.open(File.join(testroot, 'home','tpkg','file'), 'w') do |file|
      file.puts "Hello"
    end
    assert_nothing_raised { @errors = tpkg.verify_file_metadata("testpkg")}
    @errors.each do | file, error |
      if File.basename(file) == "file"
        assert(!error.empty?)
        assert(error.length == 2) # error 1 is for bad perm, error 2 is for bad checksum
      else
        assert(error.empty?)
      end
    end
 
    # remove a file and verify that tpkg can detect it
    FileUtils.rm(File.join(testroot, 'home','tpkg','file'))
    assert_nothing_raised { @errors = tpkg.verify_file_metadata("testpkg")}
    @errors.each do | file, error |
      if File.basename(file) == "file"
        assert(!error.empty?)
      else
        assert(error.empty?)
      end
    end

    FileUtils.rm_f(testroot)

    # TODO: modify a file owner, group and verify that tpkg can detect it
#    testroot = Tempdir.new("testroot")
#    testbase = File.join(testroot, 'home', 'tpkg')
#    FileUtils.mkdir_p(testbase)
#    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])
#    assert_nothing_raised { tpkg.install([@pkgfile], PASSPHRASE) }
#    uid = Tpkg::lookup_uid("bogus")
#    gid = Tpkg::lookup_gid("bogus")
#    File.chown(uid, gid, File.join(testroot, 'home','tpkg','file'))
#    assert_nothing_raised { @errors = tpkg.verify_file_metadata("testpkg")}
#    @errors.each do | file, error |
#      if File.basename(file) == "file"
#        assert(!error.empty?)
#        assert(error.length == 2) # 2 errors: 1 for gid and 1 for uid
#      else
#        assert(error.empty?) 
#      end   
#    end
#
#    FileUtils.rm_f(testroot)
  end

  def test_backward_compatibility
    # Test that tpkg doesn't break when user wants to verify old installed packages 
    # that were created without file_metadata.xml
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [@pkgfile])

    assert_nothing_raised { tpkg.install([@pkgfile], PASSPHRASE) }

    # remove file_metadata
    pkgname = File.basename(@pkgfile, File.extname(@pkgfile))
    FileUtils.rm(File.join(testroot, 'home','tpkg', 'var', 'tpkg', 'installed', 'metadata', pkgname, 'file_metadata.bin'))

    # verify nothing bad when user try to run -V
    assert_nothing_raised { @errors = tpkg.verify_file_metadata("testpkg")}

    # remove metadata directory and check the verify method doesn't break
    FileUtils.rm_r(File.join(testroot, 'home','tpkg', 'var', 'tpkg', 'installed', 'metadata', pkgname))
    assert_nothing_raised { @errors = tpkg.verify_file_metadata("testpkg")}

    # Test that tpkg doesn't break when user try to install old packages that were created without file_metadata.xml 
    pkg_without_file_metadata = File.join(File.dirname(__FILE__), 'premadetestpkg', 'pkg_without_file_metadata-1.0-1.tpkg')
    assert_nothing_raised { tpkg.install([pkg_without_file_metadata], PASSPHRASE) }
    # Check that the files from the package ended up in the right place
    assert(File.exist?(File.join(testbase, 'file')))
    assert_equal(IO.read(File.join(TESTPKGDIR, 'reloc', 'file')), IO.read(File.join(testbase, 'file')))
    assert(File.exist?(File.join(testbase, 'encfile')))
    assert_equal(IO.read(File.join(TESTPKGDIR, 'reloc', 'encfile')), IO.read(File.join(testbase, 'encfile')))
    
    # verify nothing bad when user try to run -V
    assert_nothing_raised { @errors = tpkg.verify_file_metadata("pkg_without_file_metadata")}
  end
  
  def teardown
    FileUtils.rm_f(@pkgfile)
  end
end

