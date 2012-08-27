#
# Test tpkg's ability to make packages
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgMakeTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    @tar = Tpkg::find_tar
    
    @pkgdir = Dir.mktmpdir('pkgdir')
    system("#{@tar} -C #{TESTPKGDIR} --exclude .svn --exclude tpkg-*.xml --exclude tpkg*.yml -cf - . | #{@tar} -C #{@pkgdir} -xf -")
    # Set special permissions on a file so that we can verify they are
    # preserved
    File.chmod(0400, File.join(@pkgdir, 'reloc', 'file'))
    @srcmode = File.stat(File.join(@pkgdir, 'reloc', 'file')).mode
    @srcmtime = File.stat(File.join(@pkgdir, 'reloc', 'file')).mtime
    # Insert a directory and symlink so that we can verify they are
    # properly included in the package
    Dir.mkdir(File.join(@pkgdir, 'reloc', 'directory'))
    File.symlink('linktarget', File.join(@pkgdir, 'reloc', 'directory', 'link'))
  end
  
  def verify_pkg(pkgfile)
    Dir.mktmpdir('workdir') do |workdir|
      assert(!pkgfile.nil? && pkgfile.kind_of?(String) && !pkgfile.empty?, 'make_package returned package filename')
      assert(File.exist?(pkgfile), 'make_package returned package filename that exists')
      
      # Verify checksum.xml
      #  We test verify_package_checksum in checksum.rb to make sure it works
      assert_nothing_raised('checksum verify') { Tpkg::verify_package_checksum(pkgfile) }
      
      # Unpack the package
      assert(system("#{@tar} -C #{workdir} -xf #{pkgfile}"), 'unpack package')
      unpackdir = File.join(workdir, 'testpkg-1.0-1-os-architecture')
      # Packages consist of directory containing checksum.xml and a tpkg.tar
      # with the rest of the package contents.  Ensure that the package
      # contains the right files and nothing else.
      assert(File.exist?(File.join(unpackdir, 'checksum.xml')), 'checksum.xml in package')
      tpkgfile = File.join(unpackdir, 'tpkg.tar')
      assert(File.exist?(tpkgfile), 'tpkg.tar in package')
      assert_equal(3, Dir.entries(workdir).length, 'nothing else in package top level')
      assert_equal(4, Dir.entries(unpackdir).length, 'nothing else in package directory')
      # Now unpack the tarball with the rest of the package contents
      assert(system("#{@tar} -C #{unpackdir} -xf #{File.join(unpackdir, 'tpkg.tar')}"), 'unpack tpkg.tar')
    
      # Verify that tpkg.xml and our various test files were included in the
      # package
      assert(File.exist?(File.join(unpackdir, 'tpkg', 'tpkg.xml')), 'tpkg.xml in package')
      assert(File.directory?(File.join(unpackdir, 'tpkg', 'reloc')), 'reloc in package')
      assert_equal(5, Dir.entries(File.join(unpackdir, 'tpkg')).length, 'nothing else in tpkg directory') # ., .., reloc|root, tpkg.xml, file_metadata.bin
      assert(File.exist?(File.join(unpackdir, 'tpkg', 'reloc', 'file')), 'generic file in package')
      assert(File.directory?(File.join(unpackdir, 'tpkg', 'reloc', 'directory')), 'directory in package')
      assert(File.symlink?(File.join(unpackdir, 'tpkg', 'reloc', 'directory', 'link')), 'link in package')
      # Verify that permissions and modification timestamps were preserved
      dstmode = File.stat(File.join(unpackdir, 'tpkg', 'reloc', 'file')).mode
      assert_equal(@srcmode, dstmode, 'mode preserved')
      dstmtime = File.stat(File.join(unpackdir, 'tpkg', 'reloc', 'file')).mtime
      assert_equal(@srcmtime, dstmtime, 'mtime preserved')
    
      # Verify that the file we specified should be encrypted was encrypted
      testname = 'encrypted file is encrypted'
      encrypted_contents = IO.read(File.join(unpackdir, 'tpkg', 'reloc', 'encfile'))
      unencrypted_contents = IO.read(File.join(TESTPKGDIR, 'reloc', 'encfile'))
      assert_not_equal(unencrypted_contents, encrypted_contents, testname)
      testname = 'encrypted file can be decrypted'
      Tpkg::decrypt('testpkg', File.join(unpackdir, 'tpkg', 'reloc', 'encfile'), PASSPHRASE)
      decrypted_contents = IO.read(File.join(unpackdir, 'tpkg', 'reloc', 'encfile'))
      assert_equal(unencrypted_contents, decrypted_contents, testname)
      # Verify that the precrypt file can still be decrypted
      testname = 'precrypt file can be decrypted'
      Tpkg::decrypt('testpkg', File.join(unpackdir, 'tpkg', 'reloc', 'precryptfile'), PASSPHRASE)
      decrypted_contents = IO.read(File.join(unpackdir, 'tpkg', 'reloc', 'precryptfile'))
      unencrypted_contents = IO.read(File.join(TESTPKGDIR, 'reloc', 'precryptfile.plaintext'))
      assert_equal(unencrypted_contents, decrypted_contents, testname)
    end
  end
  
  def test_make_required_fields
    # Verify that you can't make a package without one of the required fields
    Metadata::REQUIRED_FIELDS.each do |r|
      testname = "make package without required field #{r}"
      File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
        IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
          if line !~ /^\s*<#{r}>/
            pkgxmlfile.print(line)
          end
        end
      end
      assert_raise(RuntimeError, testname) { Tpkg.make_package(@pkgdir, PASSPHRASE) }
    end
    # Verify that you can't make a package with one of the required fields empty
    Metadata::REQUIRED_FIELDS.each do |r|
      testname = "make package with empty required field #{r}"
      File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
        IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
          line.sub!(/^(\s*<#{r}>).*(<\/#{r}>.*)/, '\1\2')
          pkgxmlfile.print(line)
        end
      end
      assert_raise(RuntimeError, testname) { Tpkg.make_package(@pkgdir, PASSPHRASE) }
    end
  end
  
  def test_make_optional_fields
    # Verify that you can make a package without the optional fields
    testname = 'make package without optional fields'
    pkgfile = nil
    File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
      IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
        if line =~ /^<?xml/ || line =~ /^<!DOCTYPE/ || line =~ /^<\/?tpkg>/
          # XML headers and document root
          pkgxmlfile.print(line)
        elsif Metadata::REQUIRED_FIELDS.any? { |r| line =~ /^\s*<\/?#{r}>/ }
          # Include just the required fields
          pkgxmlfile.print(line)
        end
      end
    end
    assert_nothing_raised(testname) { pkgfile = Tpkg.make_package(@pkgdir, PASSPHRASE) }
    FileUtils.rm_rf(pkgfile)
  end
  
  def test_make_nonexistent_file
    # Insert a non-existent file into tpkg.xml and verify that it throws
    # an exception
    testname = 'make package with non-existent file'
    File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
      IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
        # Insert our files entry right before the end of the file
        if line =~ /^\s*<\/tpkg>/
          pkgxmlfile.puts('<files>')
          pkgxmlfile.puts('  <file>')
          pkgxmlfile.puts('    <path>does-not-exist</path>')
          pkgxmlfile.puts('  </file>')
          pkgxmlfile.puts('</files>')
        end
        pkgxmlfile.print(line)
      end
    end
    assert_raise(RuntimeError, testname) { Tpkg.make_package(@pkgdir, PASSPHRASE) }
  end

  def test_group_owner
    # Ensure a warning given if file owner and group set to non-existing accounts
    FileUtils.cp("#{TESTPKGDIR}/tpkg-bad-ownergroup.xml", "#{@pkgdir}/tpkg.xml")
    out = capture_stdout do 
      Tpkg.make_package(@pkgdir,nil)
    end
    expectederr = "Package requests user baduser, but that user can't be found.  Using UID 0.\nPackage requests group badgroup, but that group can't be found.  Using GID 0.\n"
    assert_equal(expectederr,out.string)
    FileUtils.cp("#{TESTPKGDIR}/tpkg-good-ownergroup.xml", "#{@pkgdir}/tpkg.xml")
    out = capture_stdout do 
      Tpkg.make_package(@pkgdir,nil)
    end
    assert_equal("",out.string)
  end
 
  
  def test_make_nil_passphrase
    # Pass a nil passphrase with a package that requests encryption,
    # verify that it throws an exception
    testname = 'make package with encryption but nil passphrase'
    File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
      IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
        # Insert our files entry right before the end of the file
        if line =~ /^\s*<\/tpkg>/
          pkgxmlfile.puts('<files>')
          pkgxmlfile.puts('  <file>')
          pkgxmlfile.puts('    <path>encfile</path>')
          pkgxmlfile.puts('    <encrypt/>')
          pkgxmlfile.puts('  </file>')
          pkgxmlfile.puts('</files>')
        end
        pkgxmlfile.print(line)
      end
    end
    FileUtils.cp(File.join(TESTPKGDIR, 'reloc', 'encfile'), File.join(@pkgdir, 'reloc'))
    assert_raise(RuntimeError, testname) { Tpkg.make_package(@pkgdir, nil) }
  end
  
  def test_make_bad_precrypt
    # Include an unencrypted file flagged as precrypt=true,
    # verify that it throws an exception
    testname = 'make package with plaintext precrypt'
    File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
      IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
        # Insert our files entry right before the end of the file
        if line =~ /^\s*<\/tpkg>/
          pkgxmlfile.puts('<files>')
          pkgxmlfile.puts('  <file>')
          pkgxmlfile.puts('    <path>precryptfile</path>')
          pkgxmlfile.puts('    <encrypt precrypt="true"/>')
          pkgxmlfile.puts('  </file>')
          pkgxmlfile.puts('</files>')
        end
        pkgxmlfile.print(line)
      end
    end
    FileUtils.cp(File.join(TESTPKGDIR, 'reloc', 'precryptfile.plaintext'), File.join(@pkgdir, 'reloc', 'precryptfile'))
    assert_raise(RuntimeError, testname) { Tpkg.make_package(@pkgdir, nil) }
  end
  
  def test_make_already_exists
    # Try to make a package where the output file already exists, verify that it is overwritten
    pkgfile = File.join(Dir::tmpdir, 'testpkg-1.0-1.tpkg')
    existing_contents = 'Hello world'
    File.open(pkgfile, 'w') do |file|
      file.puts existing_contents
    end
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(@pkgdir, 'tpkg.xml'))
    assert_nothing_raised { Tpkg.make_package(@pkgdir, PASSPHRASE) }
    assert_not_equal(existing_contents, IO.read(pkgfile))
    FileUtils.rm_f(pkgfile)
    # It would be nice to test that if the user is prompted and answers no that the file is not overwritten
  end
  
  def test_make_full_path
    # Test using a full path to the package directory
    pkgfile = nil
    assert_nothing_raised { pkgfile = Tpkg.make_package(@pkgdir, PASSPHRASE) }
    begin
      verify_pkg(pkgfile)
    ensure
      FileUtils.rm_f(pkgfile)
    end
  end
  
  def test_make_relative_path
    # Test using a relative path to the directory
    pkgfile = nil
    pwd = Dir.pwd
    Dir.chdir(File.dirname(@pkgdir))
    assert_nothing_raised { pkgfile = Tpkg.make_package(File.basename(@pkgdir), PASSPHRASE) }
    pkgfile = File.join(Dir.pwd, pkgfile)
    Dir.chdir(pwd)
    begin
      verify_pkg(pkgfile)
    ensure
      FileUtils.rm_f(pkgfile)
    end
  end
  
  def test_make_dot_path
    # Test from within the directory, passing '.' to make_package
    pkgfile = nil
    pwd = Dir.pwd
    Dir.chdir(@pkgdir)
    assert_nothing_raised { pkgfile = Tpkg.make_package('.', PASSPHRASE) }
    pkgfile = File.join(Dir.pwd, pkgfile)
    Dir.chdir(pwd)
    begin
      verify_pkg(pkgfile)
    ensure
      FileUtils.rm_f(pkgfile)
    end
  end
  
  def test_make_passphrase_callback
    # Test using a callback to supply the passphrase
    callback = lambda { |pkgname| PASSPHRASE }
    pkgfile = nil
    assert_nothing_raised { pkgfile = Tpkg.make_package(@pkgdir, callback) }
    begin
      verify_pkg(pkgfile)
    ensure
      FileUtils.rm_f(pkgfile)
    end
  end
  
  def test_make_osarch_names
    # Test that make_package properly names packages that are specific to
    # particular operating systems or architectures.
    pkgfile = nil
    
    # The default tpkg.xml is tied to OS "OS" and architecture "Architecture"
    assert_nothing_raised { pkgfile = Tpkg.make_package(@pkgdir, PASSPHRASE) }
    FileUtils.rm_f(pkgfile)
    assert_match(/testpkg-1.0-1-os-architecture.tpkg/, pkgfile)
    
    # Add another OS
    File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
      IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
        if line =~ /operatingsystem/
          line << "<operatingsystem>otheros</operatingsystem>\n"
        end
        pkgxmlfile.print(line)
      end
    end
    assert_nothing_raised { pkgfile = Tpkg.make_package(@pkgdir, PASSPHRASE) }
    FileUtils.rm_f(pkgfile)
    assert_match(/testpkg-1.0-1-multios-architecture.tpkg/, pkgfile)
    
    # Add another architecture
    File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
      IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
        if line =~ /architecture/
          line << "<architecture>otherarch</architecture>\n"
        end
        pkgxmlfile.print(line)
      end
    end
    assert_nothing_raised { pkgfile = Tpkg.make_package(@pkgdir, PASSPHRASE) }
    FileUtils.rm_f(pkgfile)
    assert_match(/testpkg-1.0-1-os-multiarch.tpkg/, pkgfile)
    
    # Remove the OS
    File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
      IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
        if line !~ /operatingsystem/
          pkgxmlfile.print(line)
        end
      end
    end
    assert_nothing_raised { pkgfile = Tpkg.make_package(@pkgdir, PASSPHRASE) }
    FileUtils.rm_f(pkgfile)
    assert_match(/testpkg-1.0-1-architecture.tpkg/, pkgfile)
    
    # Remove the architecture
    File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
      IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
        if line !~ /architecture/
          pkgxmlfile.print(line)
        end
      end
    end
    assert_nothing_raised { pkgfile = Tpkg.make_package(@pkgdir, PASSPHRASE) }
    FileUtils.rm_f(pkgfile)
    assert_match(/testpkg-1.0-1-os.tpkg/, pkgfile)
    
    # Set OS to a set of Red Hat variants, they get special treatment
    File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
      IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
        if line =~ /operatingsystem/
          line = "<operatingsystem>RedHat-5,CentOS-5</operatingsystem>\n"
        end
        pkgxmlfile.print(line)
      end
    end
    assert_nothing_raised { pkgfile = Tpkg.make_package(@pkgdir, PASSPHRASE) }
    FileUtils.rm_f(pkgfile)
    assert_match(/testpkg-1.0-1-redhat5-architecture.tpkg/, pkgfile)
    
    # Red Hat variants with different versions
    File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
      IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
        if line =~ /operatingsystem/
          line = "<operatingsystem>RedHat-5,CentOS-5,RedHat-4</operatingsystem>\n"
        end
        pkgxmlfile.print(line)
      end
    end
    assert_nothing_raised { pkgfile = Tpkg.make_package(@pkgdir, PASSPHRASE) }
    FileUtils.rm_f(pkgfile)
    assert_match(/testpkg-1.0-1-redhat-architecture.tpkg/, pkgfile)
    
    # Same OS with different versions
    File.open(File.join(@pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
      IO.foreach(File.join(TESTPKGDIR, 'tpkg-nofiles.xml')) do |line|
        if line =~ /operatingsystem/
          line = "<operatingsystem>Solaris-5.8,Solaris-5.9</operatingsystem>\n"
        end
        pkgxmlfile.print(line)
      end
    end
    assert_nothing_raised { pkgfile = Tpkg.make_package(@pkgdir, PASSPHRASE) }
    FileUtils.rm_f(pkgfile)
    assert_match(/testpkg-1.0-1-solaris-architecture.tpkg/, pkgfile)
  end

  def test_make_output_dir
    testname = "Trying to output to a non-existing directory"
    assert_raise(RuntimeError, testname) { Tpkg.make_package(@pkgdir, PASSPHRASE, :out => 'bogus/direc/tory') }

    outdir = Tempfile.new('testfile')
    testname = "Trying to output to something that is not a directory"
    assert_raise(RuntimeError, testname) { Tpkg.make_package(@pkgdir, PASSPHRASE, :out => outdir.path) }

    testname = "Trying to output to a directory that is not writable"
    Dir.mktmpdir('outdir') do |outdir|
      FileUtils.chmod 0555, outdir
      assert_raise(RuntimeError, testname) { Tpkg.make_package(@pkgdir, PASSPHRASE, :out => outdir) }
    end

    # Trying to output to a good directory
    Dir.mktmpdir('outdir') do |outdir|
      pkgfile = Tpkg.make_package(@pkgdir, PASSPHRASE, :out => outdir)
      assert(File.exists?(pkgfile))
    end
  end
  
  def test_make_tpkg_version
    # FIXME
    testname = 'make_package added tpkg_version to metadata'
    # The source directory from which the package is made may not be writeable
    # by the user making the package.  As such attempting to add tpkg_version
    # to the metadata file will fail.  We expect tpkg to warn the user about
    # that fact but not fail.
    testname = 'make_package warned if adding tpkg_version failed due to permissions'
  end
  
  def teardown
    FileUtils.rm_rf(@pkgdir)
  end
end

