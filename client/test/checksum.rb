require File.dirname(__FILE__) + '/tpkgtest'

#
# Test tpkg's ability to handle package checksums
#

class TpkgChecksumTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    # Make up our regular test package
    @pkgfile = make_package(:remove => ['operatingsystem', 'architecture'])
  end
  
  # The processing of creating and storing checksums during the package
  # creation process is tested in make.rb
  
  def test_verify_package_checksum
    assert_nothing_raised('verify good checksum') { Tpkg::verify_package_checksum(@pkgfile) }
    
    # Add a few characters to the inner checksummed tarball and test that
    # it now fails the checksum verification
    workdir = Tempdir.new("workdir")
    tar = Tpkg::find_tar
    system("#{tar} -C #{workdir} -xf #{@pkgfile}") || abort
    File.open(File.join(workdir, 'testpkg-1.0-1', 'tpkg.tar'), 'a') do |file|
      file.write('xxxxxx')
    end
    badpkg = Tempfile.new('tpkgtest')
    system("#{tar} -C #{workdir} -cf #{badpkg.path} testpkg-1.0-1") || abort
    FileUtils.rm_rf(workdir)
    assert_raise(RuntimeError, 'verify bad checksum') { Tpkg::verify_package_checksum(badpkg.path) }
    
    # Confirm that checksum verification also fails on something that isn't a valid package
    puts '#'
    puts '# Errors expected here'
    puts '#'
    boguspkg = Tempfile.new('tpkgtest')
    boguspkg.puts('xxxxxx')
    boguspkg.close
    assert_raise(RuntimeError, NoMethodError, 'verify bogus non-tarball') { Tpkg::verify_package_checksum(boguspkg.path) }
    # And for completeness how about something that is a tarball but not a valid package
    boguspkg2 = Tempfile.new('tpkgtest')
    system("#{tar} -cf #{boguspkg2.path} #{boguspkg.path}")
    assert_raise(RuntimeError, NoMethodError, 'verify bogus tarball') { Tpkg::verify_package_checksum(boguspkg2.path) }
  end
  
  def teardown
    FileUtils.rm_f(@pkgfile)
  end
end
