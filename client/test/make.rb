#!/usr/bin/ruby -w

#
# Test tpkg's ability to make packages
#

require 'test/unit'
require 'tpkgtest'
require 'tempfile'
require 'fileutils'

class TpkgMakeTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    @tar = Tpkg::find_tar
  end
  
  def make_pkgdir
    pkgdir = Tempdir.new("pkgdir")
    system("#{@tar} -C testpkg --exclude .svn --exclude tpkg-nofiles.xml -cf - . | #{@tar} -C #{pkgdir} -xf -")
    # Set special permissions on a file so that we can verify they are
    # preserved
    File.chmod(0400, File.join(pkgdir, 'reloc', 'file'))
    @srcmode = File.stat(File.join(pkgdir, 'reloc', 'file')).mode
    @srcmtime = File.stat(File.join(pkgdir, 'reloc', 'file')).mtime
    # Insert a directory and symlink so that we can verify they are
    # properly included in the package
    Dir.mkdir(File.join(pkgdir, 'reloc', 'directory'))
    File.symlink('linktarget', File.join(pkgdir, 'reloc', 'directory', 'link'))
    pkgdir
  end

  # This method now takes in a cleanup block. This is necessary
  # because before calling this method, we create package file and dir, which
  # might not get clean up if there exceptions raised in this method. Therefore,
  # we need to catch the exception here (if there is any), and then always do
  # the clean up job
  def verify_pkg(pkgfile)
    begin
      assert(!pkgfile.nil? && pkgfile.kind_of?(String) && !pkgfile.empty?, 'make_package returned package filename')
      assert(File.exist?(pkgfile), 'make_package returned package filename that exists')
      
      # Verify checksum.xml
      #  We test verify_package_checksum in checksum.rb to make sure it works
      assert_nothing_raised('checksum verify') { Tpkg::verify_package_checksum(pkgfile) }
    
      # Unpack the package
      workdir = Tempdir.new("workdir")
      assert(system("#{@tar} -C #{workdir} -xf #{pkgfile}"), 'unpack package')
      # Packages consist of directory containing checksum.xml and a tpkg.tar
      # with the rest of the package contents.  Ensure that the package
      # contains the right files and nothing else.
      assert(File.exist?(File.join(workdir, 'testpkg-1.0-1', 'checksum.xml')), 'checksum.xml in package')
      tpkgfile = File.join(workdir, 'testpkg-1.0-1', 'tpkg.tar')
      assert(File.exist?(tpkgfile), 'tpkg.tar in package')
      assert_equal(3, Dir.entries(workdir).length, 'nothing else in package top level')
      assert_equal(4, Dir.entries(File.join(workdir, 'testpkg-1.0-1')).length, 'nothing else in package directory')
      # Now unpack the tarball with the rest of the package contents
      assert(system("#{@tar} -C #{File.join(workdir, 'testpkg-1.0-1')} -xf #{File.join(workdir, 'testpkg-1.0-1', 'tpkg.tar')}"), 'unpack tpkg.tar')
    
      # Verify that tpkg.xml and our various test files were included in the
      # package
      assert(File.exist?(File.join(workdir, 'testpkg-1.0-1', 'tpkg', 'tpkg.xml')), 'tpkg.xml in package')
      assert(File.directory?(File.join(workdir, 'testpkg-1.0-1', 'tpkg', 'reloc')), 'reloc in package')
      assert_equal(5, Dir.entries(File.join(workdir, 'testpkg-1.0-1', 'tpkg')).length, 'nothing else in tpkg directory') # ., .., reloc|root, tpkg.xml, file_metadata.xml
      assert(File.exist?(File.join(workdir, 'testpkg-1.0-1', 'tpkg', 'reloc', 'file')), 'generic file in package')
      assert(File.directory?(File.join(workdir, 'testpkg-1.0-1', 'tpkg', 'reloc', 'directory')), 'directory in package')
      assert(File.symlink?(File.join(workdir, 'testpkg-1.0-1', 'tpkg', 'reloc', 'directory', 'link')), 'link in package')
      # Verify that permissions and modification timestamps were preserved
      dstmode = File.stat(File.join(workdir, 'testpkg-1.0-1', 'tpkg', 'reloc', 'file')).mode
      assert_equal(@srcmode, dstmode, 'mode preserved')
      dstmtime = File.stat(File.join(workdir, 'testpkg-1.0-1', 'tpkg', 'reloc', 'file')).mtime
      assert_equal(@srcmtime, dstmtime, 'mtime preserved')
    
      # Verify that the file we specified should be encrypted was encrypted
      testname = 'encrypted file is encrypted'
      encrypted_contents = IO.read(File.join(workdir, 'testpkg-1.0-1', 'tpkg', 'reloc', 'encfile'))
      unencrypted_contents = IO.read(File.join('testpkg', 'reloc', 'encfile'))
      assert_not_equal(unencrypted_contents, encrypted_contents, testname)
      testname = 'encrypted file can be decrypted'
      Tpkg::decrypt('testpkg', File.join(workdir, 'testpkg-1.0-1', 'tpkg', 'reloc', 'encfile'), PASSPHRASE)
      decrypted_contents = IO.read(File.join(workdir, 'testpkg-1.0-1', 'tpkg', 'reloc', 'encfile'))
      assert_equal(unencrypted_contents, decrypted_contents, testname)
      # Verify that the precrypt file can still be decrypted
      testname = 'precrypt file can be decrypted'
      Tpkg::decrypt('testpkg', File.join(workdir, 'testpkg-1.0-1', 'tpkg', 'reloc', 'precryptfile'), PASSPHRASE)
      decrypted_contents = IO.read(File.join(workdir, 'testpkg-1.0-1', 'tpkg', 'reloc', 'precryptfile'))
      unencrypted_contents = IO.read(File.join('testpkg', 'reloc', 'precryptfile.plaintext'))
      assert_equal(unencrypted_contents, decrypted_contents, testname)
    rescue  => e
      raise e
    ensure
      # Cleanup
      FileUtils.rm_rf(workdir)
    end
  end
  
  def test_make
    begin
      # Verify that you can't make a package without one of the required fields
      required = ['name', 'version', 'maintainer']
      required.each do |r|
        testname = "make package without required field #{r}"
        pkgdir = Tempdir.new("pkgdir")
        File.open(File.join(pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
          IO.foreach(File.join('testpkg', 'tpkg-nofiles.xml')) do |line|
            if line !~ /^\s*<#{r}>/
              pkgxmlfile.print(line)
            end
          end
        end
        assert_raise(RuntimeError, testname) { Tpkg.make_package(pkgdir, PASSPHRASE) }
        FileUtils.rm_rf(pkgdir)
      end
      # Verify that you can't make a package with one of the required fields empty
      required.each do |r|
        testname = "make package with empty required field #{r}"
        pkgdir = Tempdir.new("pkgdir")
        File.open(File.join(pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
          IO.foreach(File.join('testpkg', 'tpkg-nofiles.xml')) do |line|
            line.sub!(/^(\s*<#{r}>).*(<\/#{r}>.*)/, '\1\2')
            pkgxmlfile.print(line)
          end
        end
        assert_raise(RuntimeError, testname) { Tpkg.make_package(pkgdir, PASSPHRASE) }
        FileUtils.rm_rf(pkgdir)
      end
    
      # Verify that you can make a package without the optional fields
      testname = 'make package without optional fields'
      pkgfile = nil
      pkgdir = Tempdir.new("pkgdir")
      File.open(File.join(pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
        IO.foreach(File.join('testpkg', 'tpkg-nofiles.xml')) do |line|
          if line =~ /^<?xml/ || line =~ /^<!DOCTYPE/ || line =~ /^<\/?tpkg>/
            # XML headers and document root
            pkgxmlfile.print(line)
          elsif required.any? { |r| line =~ /^\s*<\/?#{r}>/ }
            # Include just the required fields
            pkgxmlfile.print(line)
          end
        end
      end
      assert_nothing_raised(testname) { pkgfile = Tpkg.make_package(pkgdir, PASSPHRASE) }
      FileUtils.rm_rf(pkgdir)
      FileUtils.rm_rf(pkgfile)
      
      # Insert a non-existent file into tpkg.xml and verify that it throws
      # an exception
      testname = 'make package with non-existent file'
      pkgdir = Tempdir.new("pkgdir")
      File.open(File.join(pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
        IO.foreach(File.join('testpkg', 'tpkg-nofiles.xml')) do |line|
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
      assert_raise(RuntimeError, testname) { Tpkg.make_package(pkgdir, PASSPHRASE) }
      FileUtils.rm_rf(pkgdir)
    
      # Pass a nil passphrase with a package that requests encryption,
      # verify that it throws an exception
      testname = 'make package with encryption but nil passphrase'
      pkgdir = Tempdir.new("pkgdir")
      File.open(File.join(pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
        IO.foreach(File.join('testpkg', 'tpkg-nofiles.xml')) do |line|
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
      Dir.mkdir(File.join(pkgdir, 'reloc'))
      FileUtils.cp(File.join('testpkg', 'reloc', 'encfile'), File.join(pkgdir, 'reloc'))
      assert_raise(RuntimeError, testname) { Tpkg.make_package(pkgdir, nil) }
      FileUtils.rm_rf(pkgdir)
      
      # Include an unencrypted file flagged as precrypt=true,
      # verify that it throws an exception
      testname = 'make package with plaintext precrypt'
      pkgdir = Tempdir.new("pkgdir")
      File.open(File.join(pkgdir, 'tpkg.xml'), 'w') do |pkgxmlfile|
        IO.foreach(File.join('testpkg', 'tpkg-nofiles.xml')) do |line|
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
      Dir.mkdir(File.join(pkgdir, 'reloc'))
      FileUtils.cp(File.join('testpkg', 'reloc', 'precryptfile.plaintext'), File.join(pkgdir, 'reloc', 'precryptfile'))
      assert_raise(RuntimeError, testname) { Tpkg.make_package(pkgdir, nil) }
      FileUtils.rm_rf(pkgdir)
      
      # Try to make a package where the output file already exists, verify that it is overwritten
      pkgfile = File.join(Dir::tmpdir, 'testpkg-1.0-1.tpkg')
      existing_contents = 'Hello world'
      File.open(pkgfile, 'w') do |file|
        file.puts existing_contents
      end
      pkgdir = Tempdir.new("pkgdir")
      FileUtils.cp(File.join('testpkg', 'tpkg-nofiles.xml'), File.join(pkgdir, 'tpkg.xml'))
      assert_nothing_raised { Tpkg.make_package(pkgdir, PASSPHRASE) }
      assert_not_equal(existing_contents, IO.read(pkgfile))
      FileUtils.rm_f(pkgfile)
      FileUtils.rm_rf(pkgdir)
      # It would be nice to test that if the user is prompted and answers no that the file is not overwritten
      
      # Test using a full path to the package directory
      pkgfile = nil
      pkgdir = make_pkgdir
      assert_nothing_raised { pkgfile = Tpkg.make_package(pkgdir, PASSPHRASE) }
      verify_pkg(pkgfile)
      FileUtils.rm_rf(pkgdir)
      FileUtils.rm_f(pkgfile)
    
      # Test using a relative path to the directory
      pkgfile = nil
      pkgdir = make_pkgdir
      pwd = Dir.pwd
      Dir.chdir(File.dirname(pkgdir))
      assert_nothing_raised { pkgfile = Tpkg.make_package(File.basename(pkgdir), PASSPHRASE) }
      pkgfile = File.join(Dir.pwd, pkgfile)
      Dir.chdir(pwd)
      verify_pkg(pkgfile)
      FileUtils.rm_rf(pkgdir)
      FileUtils.rm_f(pkgfile)
      
      # Test from within the directory, passing '.' to make_package
      pkgfile = nil
      pkgdir = make_pkgdir
      pwd = Dir.pwd
      Dir.chdir(pkgdir)
      assert_nothing_raised { pkgfile = Tpkg.make_package('.', PASSPHRASE) }
      pkgfile = File.join(Dir.pwd, pkgfile)
      Dir.chdir(pwd)
      verify_pkg(pkgfile)
      FileUtils.rm_rf(pkgdir)
      FileUtils.rm_f(pkgfile)
      
      # Test using a callback to supply the passphrase
      callback = lambda { PASSPHRASE }
      pkgfile = nil
      pkgdir = make_pkgdir
      assert_nothing_raised { pkgfile = Tpkg.make_package(pkgdir, callback) }
      verify_pkg(pkgfile)
      FileUtils.rm_rf(pkgdir)
      FileUtils.rm_f(pkgfile)
    ensure
      FileUtils.rm_rf(pkgdir) if defined?pkgdir
      FileUtils.rm_f(pkgfile) if defined?pkgfile
    end
  end
  
  def teardown
  end
end

