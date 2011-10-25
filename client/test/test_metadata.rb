#
# Test tpkg's ability to handle package metadata
#

require "./#{File.dirname(__FILE__)}/tpkgtest"
require 'webrick'

# Give ourself access to some Tpkg variables
class Tpkg
  attr_reader :metadata
  attr_reader :available_packages
  attr_reader :available_native_packages
end

class TpkgMetadataTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    # temp dir that will automatically get deleted at end of test run, can be
    # used for storing packages
    @tempoutdir = Dir.mktmpdir('tempoutdir')
    
    # Make up our regular test package
    @pkgfile = make_package
    
    # Copy the package into a directory to test directory-related operations
    @pkgdir = Dir.mktmpdir('pkgdir')
    FileUtils.cp(@pkgfile, @pkgdir)
    
    # Make a test repository
    @testbase = Dir.mktmpdir('testbase')
  end
  
  def test_metadata_from_package
    metadata = Tpkg::metadata_from_package(@pkgfile)
    assert_equal('testpkg', metadata[:name], 'metadata_from_package name')
    assert_equal('1.0', metadata[:version], 'metadata_from_package version')
    assert_equal(File.basename(@pkgfile), metadata[:filename], 'metadata_from_package filename attribute')
  end
  
  # FIXME: Seems a bit odd that this never directly calls
  # metadata_xml_to_hash. Some of this should be moved to
  # test_metadata_from_package and then this converted to test
  # metadata_xml_to_hash directly.
  def test_metadata_xml_to_hash
    pkgfile = make_package(:output_directory => @tempoutdir, :dependencies => {'testpkg2' => {'minimum_version' => '1.0', 'maximum_version' => '3.0', 'minimum_package_version' => '1.5', 'maximum_package_version' => '2.5'}, 'testpkg3' => {}})
    metadata = nil
    assert_nothing_raised { metadata = Tpkg::metadata_from_package(pkgfile)}
    assert_equal('testpkg', metadata[:name])
    assert_equal('1.0', metadata[:version])
    assert_equal('1', metadata[:package_version])
    assert_equal(2, metadata[:dependencies].length)
    metadata[:dependencies].each do |depreq|
      if depreq[:name] == 'testpkg2'
        assert_equal('1.0', depreq[:minimum_version])
        assert_equal('3.0', depreq[:maximum_version])
        assert_equal('1.5', depreq[:minimum_package_version])
        assert_equal('2.5', depreq[:maximum_package_version])
        assert_equal(:tpkg, depreq[:type])
        assert_equal(6, depreq.length)  # :name, :type and 4 version requirements
      else
        assert_equal('testpkg3', depreq[:name])
        assert_equal(:tpkg, depreq[:type])
        assert_equal(2, depreq.length)  # :name and :type only
      end
    end
    FileUtils.rm_f(pkgfile)
    
    # FIXME
    # Confirm an exception is thrown if a required field is missing
    # Confirm no problem if an optional field is missing
    
    # Check that the array fields are handled properly
    os = ['os1', 'os2', 'os3']
    pkgfile = make_package(:change => {'name' => 'ostest', 'operatingsystem' => os.join(',')})
    metadata = Tpkg::metadata_from_package(pkgfile)
    assert_equal(os, metadata[:operatingsystem])
    FileUtils.rm_f(pkgfile)
    
    arch = ['arch1', 'arch2', 'arch3']
    pkgfile = make_package(:change => {'name' => 'archtest', 'architecture' => arch.join(',')})
    metadata = Tpkg::metadata_from_package(pkgfile)
    assert_equal(arch, metadata[:architecture])
    FileUtils.rm_f(pkgfile)
    
    # FIXME: files
    
    extname = 'testext'
    extdata = "This is a test of parsing an external\nwith multiple lines\nof data"
    pkgfile = make_package(:change => { 'name' => 'externalpkg' }, :externals => { extname => { 'data' => extdata } })
    metadata = Tpkg::metadata_from_package(pkgfile)
    assert_equal(extname, metadata[:externals].first[:name])
    assert_equal(extdata, metadata[:externals].first[:data])
    FileUtils.rm_f(pkgfile)
    
    extname = 'testext'
    extdata = "<element>Test external</element>\n<other>with XML data</other>"
    pkgfile = make_package(:change => { 'name' => 'externalpkg' }, :externals => { extname => { 'data' => extdata } })
    metadata = Tpkg::metadata_from_package(pkgfile)
    assert_equal(extname, metadata[:externals].first[:name])
    assert_equal(extdata, metadata[:externals].first[:data])
    FileUtils.rm_f(pkgfile)
  end
  
  def test_metadata_from_directory
    metadata = Tpkg::metadata_from_directory(@pkgdir)
    assert_equal(1, metadata.length, 'metadata_from_directory number of results')
    assert_equal('testpkg', metadata.first[:name], 'metadata_from_directory name')
    assert_equal('1.0', metadata.first[:version], 'metadata_from_directory version')
    assert_equal(File.basename(@pkgfile), metadata.first[:filename], 'metadata_from_directory filename attribute')
  end
  
  def test_extract_metadata
    assert_nothing_raised('extract_metadata') { Tpkg::extract_metadata(@pkgdir) }
    # we don't generate metadata.xml anymore
#    assert(File.file?(File.join(@pkgdir, 'metadata.xml')), 'extract_metadata metadata file')
#    assert_equal(0644, File.stat(File.join(@pkgdir, 'metadata.xml')).mode & 07777, 'extract_metadata metadata file permissions')
#    metadata_xml = nil
#    assert_nothing_raised('extract_metadata metadata load') { metadata_xml = REXML::Document.new(File.open(File.join(@pkgdir, 'metadata.xml'))) }
#    assert_equal(1, metadata_xml.elements.to_a('/tpkg_metadata/tpkg/name').size, 'extract_metadata name count')
#    assert_equal('testpkg', metadata_xml.elements['/tpkg_metadata/tpkg/name'].text, 'extract_metadata name')
#    assert_equal(File.basename(@pkgfile), metadata_xml.elements['/tpkg_metadata/tpkg'].attributes['filename'], 'extract_metadata filename attribute')

    # YAML stuff
    assert(File.file?(File.join(@pkgdir, 'metadata.yml')), 'extract_metadata metadata file')
    assert_equal(0644, File.stat(File.join(@pkgdir, 'metadata.yml')).mode & 07777, 'extract_metadata metadata file permissions')
    metadata_contents = File.read(File.join(@pkgdir, 'metadata.yml'))
    metadata = Metadata::get_pkgs_metadata_from_yml_doc(metadata_contents)
    assert_equal(1, metadata['testpkg'].size, 'extract_metadata name and count')
    assert_equal(File.basename(@pkgfile), metadata['testpkg'].first[:filename], 'extract_metadata filename attribute')
  end
  
  def test_prep_metadata
    # Add another package in the package directory to make the test a
    # little more realistic
    pkgfile2 = make_package(:change => {'name' => 'testpkg2', 'version' => '2.0'})
    FileUtils.mv(pkgfile2, @pkgdir)
    pkgfile2 = File.join(@pkgdir, File.basename(pkgfile2))
    
    Tpkg::extract_metadata(@pkgdir)
    
    # Source as filename
    tpkg = Tpkg.new(:base => testbase, :sources => [pkgfile])
    assert_nothing_raised { tpkg.prep_metadata }
    
    # Source as directory
    tpkg = Tpkg.new(:base => testbase, :sources => [@pkgdir])
    assert_nothing_raised { tpkg.prep_metadata }
    
    # Source as URI
    
    s = WEBrick::HTTPServer.new(:Port => 3500, :DocumentRoot => @pkgdir)
    # There may be an easier way to push WEBrick into the background, but
    # the WEBrick docs are mostly non-existent so I'm taking the quick and
    # dirty route.
    t = Thread.new { s.start }
    
    source = 'http://localhost:3500/'
    
    Dir.mktmpdir('testbase') do |testbase|
      tpkg = Tpkg.new(:base => testbase, :sources => [source])
      
      assert_nothing_raised { tpkg.prep_metadata }
      assert_equal(1, tpkg.metadata['testpkg'].length)
      # The two XML documents ought to be identical, but the one that gets
      # extracted, packed into metadata.xml and then unpacked into
      # @metadata is missing the XML headers (XML version and DTD).
      # Someday we should fix that, in the meantime check that they look
      # similar by checking the name element.
      puts "metadata_from_package:"
      p Tpkg::metadata_from_package(@pkgfile)
      puts "tpkg.metadata:"
      p tpkg.metadata['testpkg'].first
      assert_equal(Tpkg::metadata_from_package(@pkgfile)[:name], tpkg.metadata['testpkg'].first[:name])
      assert_equal(1, tpkg.metadata['testpkg2'].length)
      assert_equal(Tpkg::metadata_from_package(pkgfile2)[:name], tpkg.metadata['testpkg2'].first[:name])
      pkgs = tpkg.metadata.collect {|m| m[1]}.flatten
      assert_equal(2, pkgs.length)
    end
    
    # Test when the package directory isn't at the root of the web
    # server hierarchy
    Dir.mkdir(File.join(@pkgdir, 'testdir'))
    FileUtils.mv(File.join(@pkgdir, 'metadata.yml'), File.join(@pkgdir, 'testdir', 'metadata.yml'))
    
    Dir.mktmpdir('testbase') do |testbase|
      # With a trailing / on the URL
      tpkg = Tpkg.new(:base => testbase, :sources => [source + 'testdir/'])
      assert_nothing_raised { tpkg.prep_metadata }
      assert_equal(1, tpkg.metadata['testpkg'].length)
      assert_equal(1, tpkg.metadata['testpkg2'].length)
      pkgs = tpkg.metadata.collect {|m| m[1]}.flatten
      nonnativepkgs = pkgs.select do |pkg|
        pkg[:source] != :native_installed && pkg[:source] != :native_available
      end
      assert_equal(2, nonnativepkgs.length)
    end
    
    Dir.mktmpdir('testbase') do |testbase|
      # Without a trailing / on the URL
      tpkg = Tpkg.new(:base => testbase, :sources => [source + 'testdir'])
      assert_nothing_raised { tpkg.prep_metadata }
      assert_equal(1, tpkg.metadata['testpkg'].length)
      assert_equal(1, tpkg.metadata['testpkg2'].length)
      pkgs = tpkg.metadata.collect {|m| m[1]}.flatten
      nonnativepkgs = pkgs.select do |pkg|
        pkg[:source] != :native_installed && pkg[:source] != :native_available
      end
      assert_equal(2, nonnativepkgs.length)
    end
    
    s.shutdown
    t.kill
    
    # No exception thrown if source is a non-existent directory
    # FIXME: check stderr for warning
    tpkg = Tpkg.new(:base => testbase, :sources => ['/path/does/not/exist'])
    assert_nothing_raised { tpkg.prep_metadata }
    # No exception thrown if source is a relative URI
    # FIXME: check stderr for warning
    tpkg = Tpkg.new(:base => testbase, :sources => ['relative/uri'])
    assert_nothing_raised { tpkg.prep_metadata }
  end
  
  def test_load_available_packages
    # Add another package in the package directory to make the test a
    # little more realistic
    pkgfile2 = make_package(:change => {'name' => 'testpkg2', 'version' => '2.0'})
    FileUtils.mv(pkgfile2, @pkgdir)
    pkgfile2 = File.join(@pkgdir, File.basename(pkgfile2))

    Tpkg::extract_metadata(@pkgdir)
    
    s = WEBrick::HTTPServer.new(:Port => 3500, :DocumentRoot => @pkgdir)
    # There may be an easier way to push WEBrick into the background, but
    # the WEBrick docs are mostly non-existent so I'm taking the quick and
    # dirty route.
    t = Thread.new { s.start }
    
    Dir.mktmpdir('testbase') do |testbase|
      source = 'http://localhost:3500/'
      tpkg = Tpkg.new(:base => testbase, :sources => [source])
      
      assert_nothing_raised { tpkg.load_available_packages('testpkg') }
      assert_equal(1, tpkg.available_packages['testpkg'].length)
      expected = Tpkg::metadata_from_package(@pkgfile)
      actual = tpkg.available_packages['testpkg'].first[:metadata]
      assert_equal(expected.to_hash, actual.to_hash)
      pkgs = tpkg.available_packages.collect {|m| m[1]}.flatten
      assert_equal(1, pkgs.length)
      
      assert_nothing_raised { tpkg.load_available_packages('testpkg2') }
      assert_equal(1, tpkg.available_packages['testpkg2'].length)
      expected = Tpkg::metadata_from_package(pkgfile2)
      actual = tpkg.available_packages['testpkg2'].first[:metadata]
      assert_equal(expected.to_hash, actual.to_hash)
      pkgs = tpkg.available_packages.collect {|m| m[1]}.flatten
      assert_equal(2, pkgs.length)
      
      # Test with a package that isn't available
      assert_nothing_raised { tpkg.load_available_packages('otherpkg') }
      assert_equal(0, tpkg.available_packages['otherpkg'].length)
    end
    
    s.shutdown
    t.kill
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
    assert_equal(name, pkg[:metadata][:name])
    assert_equal(version, pkg[:metadata][:version])
    assert_equal(package_version, pkg[:metadata][:package_version])
    assert_equal(source, pkg[:source])
    # If source == :native_installed the :prefer flag should be set
    assert_equal(true, pkg[:prefer])
    
    # Test with package_version not specified, it should be optional
    assert_nothing_raised { pkg = tpkg.pkg_for_native_package(name, version, nil, source) }
    assert_equal(name, pkg[:metadata][:name])
    assert_equal(version, pkg[:metadata][:version])
    assert_equal(nil, pkg[:metadata][:package_version])
    assert_equal(source, pkg[:source])
    assert_equal(true, pkg[:prefer])
    
    # Test with source == :native_available, :prefer flag should not be set
    assert_nothing_raised { pkg = tpkg.pkg_for_native_package(name, version, package_version, :native_available) }
    assert_equal(name, pkg[:metadata][:name])
    assert_equal(version, pkg[:metadata][:version])
    assert_equal(package_version, pkg[:metadata][:package_version])
    assert_equal(:native_available, pkg[:source])
    assert_equal(nil, pkg[:prefer])
  end
  
  def test_load_available_native_packages
    # FIXME: I've added some basic dpkg testing but we still need Red
    # Hat, Solaris, Mac OS X and FreeBSD.  And the dpkg stuff could
    # probably use some expansion.
    if Tpkg.get_os =~ /Debian|Ubuntu/
      Dir.mktmpdir('testbase') do |testbase|
        tpkg = Tpkg.new(:base => testbase)
        system('sudo apt-get install curl')
        tpkg.load_available_native_packages('curl')
        curl_installed = tpkg.available_native_packages['curl'].select{|pkg| pkg[:source] == :native_installed}
        curl_available = tpkg.available_native_packages['curl'].select{|pkg| pkg[:source] == :native_available}
        assert_equal(1, curl_installed.length)
      end
      
      Dir.mktmpdir('testbase') do |testbase|
        tpkg = Tpkg.new(:base => testbase)
        system('sudo dpkg -r curl')
        tpkg.load_available_native_packages('curl')
        curl_installed = tpkg.available_native_packages['curl'].select{|pkg| pkg[:source] == :native_installed}
        curl_available = tpkg.available_native_packages['curl'].select{|pkg| pkg[:source] == :native_available}
        assert_equal(0, curl_installed.length)
        assert(curl_available.length >= 1)
      end
      
      # Make sure we leave the user with curl installed in case they had
      # it installed before we started.  (We probably should be fancier
      # and check beforehand if curl was installed and leave things in
      # the same state.  Or get even fancier and make our own package to
      # install so we don't mess with a real package, which might have
      # dependencies on it that prevent us from messing with it.  Or at
      # least use something less common than curl.)
      system('sudo apt-get install curl')
    end
  end

  def test_init_links
    pkg = nil
    pkg2 = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
      File.open(File.join(srcdir, 'reloc', 'myinit'), 'w') do |file|
        file.puts('init script')
      end
      pkg  = make_package(:change => { 'name' => 'a' }, :source_directory => srcdir, :files => { 'myinit' => { 'init' => {} } }, :remove => ['operatingsystem', 'architecture'])
      pkg2 = make_package(:change => { 'name' => 'b' }, :source_directory => srcdir, :files => { 'myinit' => { 'init' => { 'levels' => '' } } }, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
      metadata  = Tpkg::metadata_from_package(pkg)
      metadata2 = Tpkg::metadata_from_package(pkg2)
      links = tpkg.init_links(metadata)
      links.each do |link, init_script|
        # Not quite sure how to verify that link is valid without
        # reproducing all of the code of init_links here
        assert_equal(File.join(testroot, 'home', 'tpkg', 'myinit'), init_script)
      end
      # Test a package with an empty set of runlevels specified
      assert(tpkg.init_links(metadata2).empty?)
    end
    FileUtils.rm_f(pkg)
    FileUtils.rm_f(pkg2)
  end
  
  def test_crontab_destinations
    pkg = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir_p(File.join(srcdir, 'reloc'))
      File.open(File.join(srcdir, 'reloc', 'mycrontab'), 'w') do |file|
        file.puts('crontab')
      end
      pkg = make_package(:change => { 'name' => 'a' }, :source_directory => srcdir, :files => { 'mycrontab' => { 'crontab' => {'user' => 'root'} } }, :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      testbase = File.join(testroot, 'home', 'tpkg')
      FileUtils.mkdir_p(testbase)
      tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => [pkg])
      metadata = Tpkg::metadata_from_package(pkg)
      destinations = tpkg.crontab_destinations(metadata)
      destinations.each do |crontab, destination|
        # Not quite sure how to verify that the file or link is valid
        # without reproducing all of the code of crontab_destinations
        # here.
        assert(destination.has_key?(:file) || destination.has_key?(:link))
      end
    end
    FileUtils.rm_f(pkg)
  end
  
  def test_get_pkgs_metadata_from_yml_doc
    metadatayaml = <<YAML
---
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
---
name: pkgone
version: 2
maintainer: newuser@example.com
description: Updated package
---
name: pkgtwo
version: 1
maintainer: otheruser@example.com
description: Package two
YAML
    
    metadata = Metadata.get_pkgs_metadata_from_yml_doc(metadatayaml)
    # Right overall data structure?
    assert_kind_of(Hash, metadata)
    # Both pkgone entries in the same hash key?
    assert_equal(2, metadata['pkgone'].length)
    # YAML parsed into right object?
    firstpkgone = metadata['pkgone'].shift
    assert_kind_of(Metadata, firstpkgone)
    # Parsing looks reasonable?
    assert_equal('pkgone', firstpkgone[:name])
    # Just one pkgtwo entry in that hash key?
    assert_equal(1, metadata['pkgtwo'].length)
    # Object type and parsing looks reasonable?
    pkgtwo = metadata['pkgtwo'].shift
    assert_kind_of(Metadata, pkgtwo)
    assert_equal('pkgtwo', pkgtwo[:name])
    
    # Test the side-effect use case
    metadata = {}
    boguskey = 'Some bogus junk'
    bogusvalue = ['a', 'b']
    bogusvalue2 = ['1', '2']
    metadata[boguskey] = bogusvalue.dup
    metadata['pkgtwo'] = bogusvalue2.dup
    Metadata.get_pkgs_metadata_from_yml_doc(metadatayaml, metadata)
    # Make sure our boguskey hash entry was unchanged
    assert_equal(bogusvalue, metadata[boguskey])
    # Ensure the bogus entries we added to the pkgtwo entry were unchanged
    assert_equal(bogusvalue2, metadata['pkgtwo'].shift(2))
    # Metadata for pkgtwo was appended to our array?
    pkgtwo = metadata['pkgtwo'].shift
    assert_kind_of(Metadata, pkgtwo)
    assert_equal('pkgtwo', pkgtwo[:name])
  end
  
  def test_instantiate_from_dir
    Dir.mktmpdir('pkgdir') do |pkgdir|
      yaml = <<YAML
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
YAML
      File.open(File.join(pkgdir, 'tpkg.yml'), 'w') do |file|
        file.write yaml
      end
      metadata = Metadata.instantiate_from_dir(pkgdir)
      assert_kind_of(Metadata, metadata)
      assert_equal('pkgone', metadata[:name])
    end
    
    Dir.mktmpdir('pkgdir') do |pkgdir|
      xml = <<XML
<tpkg>
  <name>pkgone</name>
  <version>1</version>
  <maintainer>test@example.com</maintainer>
  <description>Package one</description>
</tpkg>
XML
      File.open(File.join(pkgdir, 'tpkg.xml'), 'w') do |file|
        file.write xml
      end
      metadata = Metadata.instantiate_from_dir(pkgdir)
      assert_kind_of(Metadata, metadata)
      assert_equal('pkgone', metadata[:name])
    end
  end
  
  def test_initialize
    yaml = <<YAML
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
YAML
    
    metadata = Metadata.new(yaml, 'yml')
    assert_equal(yaml, metadata.text)
    assert_equal('yml', metadata.format)
    assert_equal(nil, metadata.file)
    assert_equal(nil, metadata.source)
    
    file = Tempfile.new('metadata').path
    metadata = Metadata.new(yaml, 'yml', file)
    assert_equal(yaml, metadata.text)
    assert_equal('yml', metadata.format)
    assert_equal(file, metadata.file)
    assert_equal(nil, metadata.source)
    
    source = 'http://example.com/tpkg/'
    metadata = Metadata.new(yaml, 'yml', file, source)
    assert_equal(yaml, metadata.text)
    assert_equal('yml', metadata.format)
    assert_equal(file, metadata.file)
    assert_equal(source, metadata.source)
  end
  
  def test_square_brackets
    # This method is just a convenience proxy for to_hash, so only minimal
    # testing is called for here
    yaml = <<YAML
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
dependencies:
- name: dep1
- name: dep2
YAML
    
    metadata = Metadata.new(yaml, 'yml')
    assert_equal('pkgone', metadata[:name])
    assert_equal(1, metadata[:version])
    assert_equal([{'name'=>'dep1', 'type'=>:tpkg},
                  {'name'=>'dep2', 'type'=>:tpkg}],
                 metadata[:dependencies])
  end
  
  def test_square_brackets_assign
    # This method is just a convenience proxy for to_hash, so only minimal
    # testing is called for here
    yaml = <<YAML
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
YAML
    
    metadata = Metadata.new(yaml, 'yml')
    metadata[:name] = 'pkgtwo'
    assert_equal('pkgtwo', metadata[:name])
    metadata[:version] = 2
    assert_equal(2, metadata[:version])
    metadata[:dependencies] = [{'name'=>'dep1', 'type'=>:tpkg},
                               {'name'=>'dep2', 'type'=>:tpkg}]
    assert_equal([{'name'=>'dep1', 'type'=>:tpkg},
                  {'name'=>'dep2', 'type'=>:tpkg}],
                 metadata[:dependencies])
  end
  
  def test_to_hash
    # FIXME
  end
  
  def test_write
    Dir.mktmpdir('outputdir') do |outputdir|
      yaml = <<YAML
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
YAML
      metadata = Metadata.new(yaml, 'yml')
      metadata.write(outputdir)
      # tpkg.yml there?
      assert(File.file?(File.join(outputdir, 'tpkg.yml')))
      # and nothing else?
      assert_equal(3, Dir.entries(outputdir).length)
      # tpkg.yml contains the right stuff?
      filelines = File.readlines(File.join(outputdir, 'tpkg.yml'))
      filelines.each {|line| line.chomp!}
      assert(filelines.include?('--- '))
      assert(filelines.include?('name: pkgone'))
      assert(filelines.include?('version: 1'))
      assert(filelines.include?('maintainer: test@example.com'))
      assert(filelines.include?('description: Package one'))
      assert_equal(5, filelines.length)
    end
    
    Dir.mktmpdir('outputdir') do |outputdir|
      xml = <<XML
<tpkg>
  <name>pkgone</name>
  <version>1</version>
  <maintainer>test@example.com</maintainer>
  <description>Package one</description>
</tpkg>
XML
      metadata = Metadata.new(xml, 'xml')
      metadata.write(outputdir)
      # tpkg.yml there?
      assert(File.file?(File.join(outputdir, 'tpkg.yml')))
      # and nothing else?
      assert_equal(3, Dir.entries(outputdir).length)
      # tpkg.yml contains the right stuff?
      filelines = File.readlines(File.join(outputdir, 'tpkg.yml'))
      filelines.each {|line| line.chomp!}
      # The xml to yaml conversion yields slightly different but semantically
      # equivalent results to a direct dump of yaml
      filelines.delete('')
      assert(filelines.include?('--- '))
      assert(filelines.include?('name: pkgone'))
      assert(filelines.include?('version: "1"'))
      assert(filelines.include?('maintainer: test@example.com'))
      assert(filelines.include?('description: Package one'))
      assert(filelines.include?('files: {}'))
      assert_equal(6, filelines.length)
    end
  end
  
  def test_add_tpkg_version
    # yaml, no version, from file
    yaml = <<YAML
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
YAML
    Dir.mktmpdir('pkgdir') do |pkgdir|
      File.open(File.join(pkgdir, 'tpkg.yml'), 'w') do |file|
        file.write yaml
      end
      metadata = Metadata.instantiate_from_dir(pkgdir)
      metadata.add_tpkg_version(Tpkg::VERSION)
      
      # Added to in-memory data
      assert_equal(Tpkg::VERSION, metadata[:tpkg_version])
      # File updated
      new_metadata = Metadata.instantiate_from_dir(pkgdir)
      assert_equal(Tpkg::VERSION, new_metadata[:tpkg_version])
    end
    
    # yaml, correct version, from file
    yaml_with_correct_version = <<YAML
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
tpkg_version: #{Tpkg::VERSION}
YAML
    Dir.mktmpdir('pkgdir') do |pkgdir|
      File.open(File.join(pkgdir, 'tpkg.yml'), 'w') do |file|
        file.write yaml_with_correct_version
      end
      metadata = Metadata.instantiate_from_dir(pkgdir)
      metadata.add_tpkg_version(Tpkg::VERSION)
      
      # In-memory data still correct
      assert_equal(Tpkg::VERSION, metadata[:tpkg_version])
      # File still correct
      new_metadata = Metadata.instantiate_from_dir(pkgdir)
      assert_equal(Tpkg::VERSION, new_metadata[:tpkg_version])
    end
    
    # yaml, incorrect version, from file
    yaml_with_incorrect_version = <<YAML
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
tpkg_version: 0
YAML
    Dir.mktmpdir('pkgdir') do |pkgdir|
      File.open(File.join(pkgdir, 'tpkg.yml'), 'w') do |file|
        file.write yaml_with_incorrect_version
      end
      metadata = Metadata.instantiate_from_dir(pkgdir)
      metadata.add_tpkg_version(Tpkg::VERSION)
      
      # Version mismatch results in warning
      # FIXME, how to check for warning?
      # In-memory data remains incorrect
      assert_equal(0, metadata[:tpkg_version])
      # File remains incorrect
      new_metadata = Metadata.instantiate_from_dir(pkgdir)
      assert_equal(0, new_metadata[:tpkg_version])
    end
    
    # yaml, no version, from string
    metadata = Metadata.new(yaml, 'yml')
    metadata.add_tpkg_version(Tpkg::VERSION)
    # Added to in-memory data
    assert_equal(Tpkg::VERSION, metadata[:tpkg_version])
    
    # xml, no version, from file
    xml = <<XML
<tpkg>
  <name>pkgone</name>
  <version>1</version>
  <maintainer>test@example.com</maintainer>
  <description>Package one</description>
</tpkg>
XML
    Dir.mktmpdir('pkgdir') do |pkgdir|
      File.open(File.join(pkgdir, 'tpkg.xml'), 'w') do |file|
        file.write xml
      end
      metadata = Metadata.instantiate_from_dir(pkgdir)
      metadata.add_tpkg_version(Tpkg::VERSION)
      
      # Added to in-memory data
      assert_equal(Tpkg::VERSION, metadata[:tpkg_version])
      # File updated
      new_metadata = Metadata.instantiate_from_dir(pkgdir)
      assert_equal(Tpkg::VERSION, new_metadata[:tpkg_version])
      # FIXME: verify still complies with DTD?
    end
    
    # xml, correct version, from file
    xml_with_correct_version = <<XML
<tpkg>
  <name>pkgone</name>
  <version>1</version>
  <maintainer>test@example.com</maintainer>
  <description>Package one</description>
  <tpkg_version>#{Tpkg::VERSION}</tpkg_version>
</tpkg>
XML
    Dir.mktmpdir('pkgdir') do |pkgdir|
      File.open(File.join(pkgdir, 'tpkg.xml'), 'w') do |file|
        file.write xml_with_correct_version
      end
      metadata = Metadata.instantiate_from_dir(pkgdir)
      metadata.add_tpkg_version(Tpkg::VERSION)
      
      # In-memory data still correct
      assert_equal(Tpkg::VERSION, metadata[:tpkg_version])
      # File still correct
      new_metadata = Metadata.instantiate_from_dir(pkgdir)
      assert_equal(Tpkg::VERSION, new_metadata[:tpkg_version])
      # FIXME: verify still complies with DTD?
    end
    
    # xml, incorrect version, from file
    xml_with_incorrect_version = <<XML
<tpkg>
  <name>pkgone</name>
  <version>1</version>
  <maintainer>test@example.com</maintainer>
  <description>Package one</description>
  <tpkg_version>0</tpkg_version>
</tpkg>
XML
    Dir.mktmpdir('pkgdir') do |pkgdir|
      File.open(File.join(pkgdir, 'tpkg.xml'), 'w') do |file|
        file.write xml_with_incorrect_version
      end
      metadata = Metadata.instantiate_from_dir(pkgdir)
      metadata.add_tpkg_version(Tpkg::VERSION)
      
      # Version mismatch results in warning
      # FIXME, how to check for warning?
      # In-memory data remains incorrect
      assert_equal('0', metadata[:tpkg_version])
      # File remains incorrect
      new_metadata = Metadata.instantiate_from_dir(pkgdir)
      assert_equal('0', new_metadata[:tpkg_version])
    end
    
    # xml, no version, from string
    metadata = Metadata.new(xml, 'xml')
    metadata.add_tpkg_version(Tpkg::VERSION)
    # Added to in-memory data
    assert_equal(Tpkg::VERSION, metadata[:tpkg_version])
  end
  
  def test_generate_package_filename
    # FIXME
  end
  
  def test_validate
    # FIXME
  end
  
  def test_verify_yaml
    # FIXME
  end
  
  def test_verify_required_fields
    # FIXME
  end
  
  def test_get_native_deps
    # Metadata with no dependencies
    yaml = <<YAML
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
YAML
    metadata = Metadata.new(yaml, 'yml')
    assert_equal([], metadata.get_native_deps)
    # Metadata with empty dependencies
    yaml = <<YAML
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
dependencies:
YAML
    metadata = Metadata.new(yaml, 'yml')
    assert_equal([], metadata.get_native_deps)
    # Metadata with dependencies but none native
    yaml = <<YAML
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
dependencies:
- name: dep1
- name: dep2
YAML
    metadata = Metadata.new(yaml, 'yml')
    assert_equal([], metadata.get_native_deps)
    # Metadata with native dependencies
    yaml = <<YAML
name: pkgone
version: 1
maintainer: test@example.com
description: Package one
dependencies:
- name: dep1
- name: nativedep1
  native: true
- name: nativedep2
  native: true
YAML
        metadata = Metadata.new(yaml, 'yml')
        assert_equal([{'name'=>'nativedep1', 'native'=>true, 'type'=>:native},
                      {'name'=>'nativedep2', 'native'=>true, 'type'=>:native}],
                     metadata.get_native_deps)
  end
  
  def teardown
    FileUtils.rm_f(@pkgfile)
    FileUtils.rm_rf(@pkgdir)
    FileUtils.rm_rf(@testbase)
    FileUtils.rm_rf(@tempoutdir)
  end
end
