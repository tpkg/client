#!/usr/bin/ruby -w

#
# Test tpkg's ability to handle package metadata
#

require 'test/unit'
require 'tpkgtest'
require 'fileutils'
require 'tempfile'
require 'webrick'

# Give ourself access to Tpkg's @metadata variable
class Tpkg
  attr_reader :metadata
end

class TpkgMetadataTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    # Make up our regular test package
    @pkgfile = make_package
    
    # Copy the package into a directory to test directory-related operations
    @pkgdir = Tempdir.new("pkgdir")
    FileUtils.cp(@pkgfile, @pkgdir)
    
    # Make a test repository
    @testbase = Tempdir.new("testbase")
  end
  
  def test_metadata_from_package
    metadata = Tpkg::metadata_from_package(@pkgfile)
    assert_equal('testpkg', metadata.elements['/tpkg/name'].text, 'metadata_from_package name')
    assert_equal('1.0', metadata.elements['/tpkg/version'].text, 'metadata_from_package version')
    assert_equal(File.basename(@pkgfile), metadata.root.attributes['filename'], 'metadata_from_package filename attribute')
  end
  
  def test_metadata_from_directory
    metadatas = Tpkg::metadata_from_directory(@pkgdir)
    assert_equal(1, metadatas.length, 'metadata_from_directory number of results')
    assert_equal('testpkg', metadatas.first.elements['/tpkg/name'].text, 'metadata_from_directory name')
    assert_equal('1.0', metadatas.first.elements['/tpkg/version'].text, 'metadata_from_directory version')
    assert_equal(File.basename(@pkgfile), metadatas.first.root.attributes['filename'], 'metadata_from_directory filename attribute')
  end
  
  def test_extract_metadata
    assert_nothing_raised('extract_metadata') { Tpkg::extract_metadata(@pkgdir) }
    assert(File.file?(File.join(@pkgdir, 'metadata.xml')), 'extract_metadata metadata file')
    metadata_xml = nil
    assert_nothing_raised('extract_metadata metadata load') { metadata_xml = REXML::Document.new(File.open(File.join(@pkgdir, 'metadata.xml'))) }
    assert_equal(1, metadata_xml.elements.to_a('/tpkg_metadata/tpkg/name').size, 'extract_metadata name count')
    assert_equal('testpkg', metadata_xml.elements['/tpkg_metadata/tpkg/name'].text, 'extract_metadata name')
    assert_equal(File.basename(@pkgfile), metadata_xml.elements['/tpkg_metadata/tpkg'].attributes['filename'], 'extract_metadata filename attribute')
  end
  
  def test_refresh_metadata
    Tpkg::extract_metadata(@pkgdir)
    
    s = WEBrick::HTTPServer.new(:Port => 3500, :DocumentRoot => @pkgdir)
    # There may be an easier way to push WEBrick into the background, but
    # the WEBrick docs are mostly non-existent so I'm taking the quick and
    # dirty route.
    t = Thread.new { s.start }
    
    testbase = Tempdir.new("testbase")
    source = 'http://localhost:3500/'
    tpkg = Tpkg.new(:base => testbase, :sources => [source])
    assert_nothing_raised('refresh_metadata') { tpkg.refresh_metadata }
    pkgs = tpkg.metadata
    nonnativepkgs = pkgs.select do |pkg|
      pkg[:source] != :native_installed && pkg[:source] != :native_available
    end
    assert_equal(1, nonnativepkgs.length, 'refresh_metadata length')
    
    # Add another package in the package directory, re-extract the metadata,
    # and re-run the refresh to verify that the change is picked up
    pkgfile2 = make_package(:change => {'name' => 'testpkg2', 'version' => '2.0'})
    FileUtils.mv(pkgfile2, @pkgdir)
    Tpkg::extract_metadata(@pkgdir)
    # Pause for a second, otherwise webrick seems to occasionally return
    # the old file
    sleep(1)
    assert_nothing_raised('refresh_metadata second time') { tpkg.refresh_metadata }
    pkgs = tpkg.metadata
    nonnativepkgs = pkgs.select do |pkg|
      pkg[:source] != :native_installed && pkg[:source] != :native_available
    end
    assert_equal(2, nonnativepkgs.length, 'refresh_metadata length second time')
    
    FileUtils.rm_rf(testbase)
    s.shutdown
    t.kill
  end
  
  def test_extract_operatingsystem_from_metadata
    os = ['os1', 'os2', 'os3']
    pkgfile = make_package(:change => {'name' => 'ostest', 'operatingsystem' => os.join(',')})
    metadata = Tpkg::metadata_from_package(pkgfile)
    extractedos = Tpkg::extract_operatingsystem_from_metadata(metadata)
    assert_equal(os, extractedos, 'extract_operatingsystem_from_metadata')
    FileUtils.rm_f(pkgfile)
  end
  def test_extract_architecture_from_metadata
    arch = ['arch1', 'arch2', 'arch3']
    pkgfile = make_package(:change => {'name' => 'archtest', 'architecture' => arch.join(',')})
    metadata = Tpkg::metadata_from_package(pkgfile)
    extractedarch = Tpkg::extract_architecture_from_metadata(metadata)
    assert_equal(arch, extractedarch, 'extract_architecture_from_metadata')
    FileUtils.rm_f(pkgfile)
  end
  
  def test_pkg_for_native_package
    tpkg = Tpkg.new(:base => @testbase)
    name = 'testpkg'
    version = '1.0.1'
    package_version = '5.6'
    source = :native_installed
    pkg = nil
    
    # Test with everything specified
    assert_nothing_raised { pkg = tpkg.pkg_for_native_package(name, version, package_version, source) }
    assert_equal(name, pkg[:metadata].elements['/tpkg/name'].text)
    assert_equal(version, pkg[:metadata].elements['/tpkg/version'].text)
    assert_equal(package_version, pkg[:metadata].elements['/tpkg/package_version'].text)
    assert_equal(source, pkg[:source])
    # If source == :native_installed the :prefer flag should be set
    assert_equal(true, pkg[:prefer])
    
    # Test with package_version not specified, it should be optional
    assert_nothing_raised { pkg = tpkg.pkg_for_native_package(name, version, nil, source) }
    assert_equal(name, pkg[:metadata].elements['/tpkg/name'].text)
    assert_equal(version, pkg[:metadata].elements['/tpkg/version'].text)
    assert_equal(nil, pkg[:metadata].elements['/tpkg/package_version'])
    assert_equal(source, pkg[:source])
    assert_equal(true, pkg[:prefer])
    
    # Test with source == :native_available, :prefer flag should not be set
    assert_nothing_raised { pkg = tpkg.pkg_for_native_package(name, version, package_version, :native_available) }
    assert_equal(name, pkg[:metadata].elements['/tpkg/name'].text)
    assert_equal(version, pkg[:metadata].elements['/tpkg/version'].text)
    assert_equal(package_version, pkg[:metadata].elements['/tpkg/package_version'].text)
    assert_equal(:native_available, pkg[:source])
    assert_equal(nil, pkg[:prefer])
  end
  
  def test_init_links
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join('testpkg', 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
    File.open(File.join(srcdir, 'reloc', 'myinit'), 'w') do |file|
      file.puts('init script')
    end
    pkg = make_package(:change => { 'name' => 'a' }, :source_directory => srcdir, :files => { 'myinit' => { 'init' => true } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
    metadata = Tpkg::metadata_from_package(pkg)
    begin
      links = tpkg.init_links(metadata)
      assert(links.length >= 1)
      links.each do |link, init_script|
        # Not quite sure how to verify that link is valid without
        # reproducing all of the code of init_links here
        assert_equal(File.join(testroot, 'home', 'tpkg', 'myinit'), init_script)
      end
    rescue RuntimeError
      warn "No init script support on this platform, init_links will not be tested"
    end
    FileUtils.rm_f(pkg)
    FileUtils.rm_rf(testroot)
  end
  
  def test_crontab_destinations
    srcdir = Tempdir.new("srcdir")
    FileUtils.cp(File.join('testpkg', 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
    FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
    File.open(File.join(srcdir, 'reloc', 'mycrontab'), 'w') do |file|
      file.puts('crontab')
    end
    pkg = make_package(:change => { 'name' => 'a' }, :source_directory => srcdir, :files => { 'mycrontab' => { 'crontab' => {'user' => 'root'} } }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    FileUtils.rm_rf(srcdir)
    testroot = Tempdir.new("testroot")
    testbase = File.join(testroot, 'home', 'tpkg')
    FileUtils.mkdir_p(testbase)
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
    metadata = Tpkg::metadata_from_package(pkg)
    begin
      destinations = tpkg.crontab_destinations(metadata)
      assert(destinations.length >= 1)
      destinations.each do |crontab, destination|
        # Not quite sure how to verify that the file or link is valid
        # without reproducing all of the code of crontab_destinations
        # here.
        assert(destination.has_key?(:file) || destination.has_key?(:link))
      end
    rescue RuntimeError
      warn "No crontab support on this platform, crontab_destinations will not be tested"
    end
    FileUtils.rm_f(pkg)
    FileUtils.rm_rf(testroot)
  end
  
  def teardown
    FileUtils.rm_f(@pkgfile)
    FileUtils.rm_rf(@pkgdir)
    FileUtils.rm_rf(@testbase)
  end
end
