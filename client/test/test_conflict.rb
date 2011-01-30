#
# Test tpkg's ability to resolve dependencies
#

require "./#{File.dirname(__FILE__)}/tpkgtest"

class TpkgConflictTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    @testroot = Tempdir.new("testroot")
  end

  def test_conflict
    srcdir = Tempdir.new("srcdir")
    @pkgfiles = []
    FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))

    @pkgfiles <<  make_package(:change => { 'name' => 'pkgA', 'version' => '1.0' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'], :conflicts => {'pkgB' => {}})
    @pkgfiles <<  make_package(:change => { 'name' => 'pkgB', 'version' => '1.0' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    @pkgfiles <<  make_package(:change => { 'name' => 'pkgC', 'version' => '1.0' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    @pkgfiles <<  make_package(:change => { 'name' => 'pkgC', 'version' => '2.0' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'], :conflicts => {'pkgD' => {}})
    @pkgfiles <<  make_package(:change => { 'name' => 'pkgD', 'version' => '1.0' }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])

    # Should not be able to install both pkgA and B since A conflicts with B
    tpkg = Tpkg.new(:file_system_root => @testroot, :base => File.join('home', 'tpkg'), :sources => @pkgfiles)
    assert_raise(RuntimeError) { tpkg.install(['pkgA', 'pkgB'], PASSPHRASE) }
    assert_nothing_raised { tpkg.install(['pkgA'], PASSPHRASE)}
    assert(!tpkg.install(['pkgB'], PASSPHRASE))
    assert(tpkg.install(['pkgB'], PASSPHRASE, {:force_replace => true}))
    assert_nothing_raised { tpkg.install(['pkgC=1.0', 'pkgD'], PASSPHRASE)}
    # Should not be able to upgrade pgkC because new version
    # of pkgC conflicts with pkgD
    assert(!tpkg.upgrade(['pkgC'], PASSPHRASE))
    assert(tpkg.upgrade(['pkgC'], PASSPHRASE, {:force_replace => true}))

    FileUtils.rm_rf(srcdir)
  end
  
end
