#!/usr/bin/ruby -w

#
# Test tpkg's ability to resolve dependencies
#

require 'test/unit'
require 'tpkgtest'
require 'facter'
require 'tempfile'
require 'fileutils'

class TpkgDependencyTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    @tempoutdir = Tempdir.new("tempoutdir")  # temp dir that will automatically get deleted at end of test run
                                             # can be used for storing packages
    @pkgfiles = []
    # a depends on b, and c >= 1.1
    @pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a' }, :remove => ['operatingsystem', 'architecture'], :dependencies => {'b' => {}, 'c' => {'minimum_version' => '1.1', 'maximum_version' => '1.2'}})
    # generic b for all OSs
    # These two b packages will end up with the same filename, so we
    # manually rename this one
    bpkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'b' }, :remove => ['operatingsystem', 'architecture'])
    bpkgnew = bpkg + '.generic'
    File.rename(bpkg, bpkgnew)
    @pkgfiles << bpkgnew
    # b specific to this OS (should prefer this one)
    @pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'b', 'operatingsystem' => Tpkg::get_os }, :remove => ['architecture'])
    # c 1.0 to 1.3, a's dep should result in c-1.2 getting picked
    @pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'c', 'version' => '1.0' }, :remove => ['operatingsystem', 'architecture'], :dependencies => {'d' => {'minimum_version' => '1.0', 'maximum_version' => '1.0'}})
    @pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'c', 'version' => '1.1' }, :remove => ['operatingsystem', 'architecture'], :dependencies => {'d' => {'minimum_version' => '1.1', 'maximum_version' => '1.1'}})
    @pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'c', 'version' => '1.2' }, :remove => ['operatingsystem', 'architecture'], :dependencies => {'d' => {'minimum_version' => '1.2', 'maximum_version' => '1.2'}})
    @pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'c', 'version' => '1.3' }, :remove => ['operatingsystem', 'architecture'], :dependencies => {'d' => {'minimum_version' => '1.3', 'maximum_version' => '1.3'}})
    # d 1.0 to 1.3, c's dep should result in d-1.2 getting picked
    @pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'd', 'version' => '1.0' }, :remove => ['operatingsystem', 'architecture'])
    @pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'd', 'version' => '1.1' }, :remove => ['operatingsystem', 'architecture'])
    @pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'd', 'version' => '1.2' }, :remove => ['operatingsystem', 'architecture'])
    @pkgfiles << make_package(:output_directory => @tempoutdir, :change => { 'name' => 'd', 'version' => '1.3' }, :remove => ['operatingsystem', 'architecture'])
  end
  
  def test_package_meets_requirement
    #
    # Test version handling
    #
    
    pkgfile = make_package(:output_directory => @tempoutdir, :remove => ['operatingsystem', 'architecture'])
    pkg = { :metadata => Tpkg::metadata_from_package(pkgfile), :source => pkgfile }
    req = { :name => 'testpkg' }
    
    # Below minimum version w/o package version
    req[:minimum_version] = '2.0'
    req[:maximum_version] = '3.0'
    req.delete(:minimum_package_version)
    req.delete(:maximum_package_version)
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    # Below minimum version w/ package version
    req[:minimum_package_version] = '1.0'
    req[:maximum_package_version] = '2.0'
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    # At minimum version w/o package version
    req[:minimum_version] = '1.0'
    req[:maximum_version] = '2.0'
    req.delete(:minimum_package_version)
    req.delete(:maximum_package_version)
    assert(Tpkg::package_meets_requirement?(pkg, req))
    # At minimum version w/ package version
    req[:minimum_package_version] = '1.0'
    req[:maximum_package_version] = '2.0'
    assert(Tpkg::package_meets_requirement?(pkg, req))
    # In middle of range w/o package version
    req[:minimum_version] = '0.5'
    req[:maximum_version] = '2.0'
    req.delete(:minimum_package_version)
    req.delete(:maximum_package_version)
    assert(Tpkg::package_meets_requirement?(pkg, req))
    # In middle of range w/ package version
    req[:minimum_version] = '0.5'
    req[:maximum_version] = '2.0'
    req[:minimum_package_version] = '0.5'
    req[:maximum_package_version] = '2.0'
    assert(Tpkg::package_meets_requirement?(pkg, req))
    # At maximum version w/o package version
    req[:minimum_version] = '0.5'
    req[:maximum_version] = '1.0'
    req.delete(:minimum_package_version)
    req.delete(:maximum_package_version)
    assert(Tpkg::package_meets_requirement?(pkg, req))
    # At maximum version w/ package version
    req[:minimum_version] = '0.5'
    req[:maximum_version] = '1.0'
    req[:minimum_package_version] = '0.5'
    req[:maximum_package_version] = '1.0'
    assert(Tpkg::package_meets_requirement?(pkg, req))
    # Above maximum version w/o package version
    req[:minimum_version] = '0.1'
    req[:maximum_version] = '0.5'
    req.delete(:minimum_package_version)
    req.delete(:maximum_package_version)
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    # Above minimum version w/ package version
    req[:minimum_package_version] = '1.0'
    req[:maximum_package_version] = '2.0'
    assert(!Tpkg::package_meets_requirement?(pkg, req))

    FileUtils.rm_f(pkgfile)
    
    #
    # Test architecture and operatingsystem handling
    #
    
    req = { :name => 'testpkg' }
    
    # Package with no OS specified
    pkgfile = make_package(:output_directory => @tempoutdir, :remove => ['operatingsystem'], :change => {'architecture' => Facter['hardwaremodel'].value})
    pkg = { :metadata => Tpkg::metadata_from_package(pkgfile), :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with one matching OS
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => Tpkg::get_os, 'architecture' => Facter['hardwaremodel'].value})
    pkg = { :metadata => Tpkg::metadata_from_package(pkgfile), :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with a matching OS in a list of OSs
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => "RedHat,CentOS,#{Tpkg::get_os},FreeBSD,Solaris", 'architecture' => Facter['hardwaremodel'].value})
    pkg = { :metadata => Tpkg::metadata_from_package(pkgfile), :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with one non-matching OS
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => 'bogus_os', 'architecture' => Facter['hardwaremodel'].value})
    pkg = { :metadata => Tpkg::metadata_from_package(pkgfile), :source => pkgfile }
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with a list of non-matching OSs
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => 'bogus_os1,bogus_os2', 'architecture' => Facter['hardwaremodel'].value})
    pkg = { :metadata => Tpkg::metadata_from_package(pkgfile), :source => pkgfile }
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with no architecture specified
    pkgfile = make_package(:output_directory => @tempoutdir, :remove => ['architecture'], :change => {'operatingsystem' => Tpkg::get_os })
    pkg = { :metadata => Tpkg::metadata_from_package(pkgfile), :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with one matching architecture
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => Tpkg::get_os, 'architecture' => Facter['hardwaremodel'].value})
    pkg = { :metadata => Tpkg::metadata_from_package(pkgfile), :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with a matching architecture in a list of architectures
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => Tpkg::get_os, 'architecture' => "i386,x86_64,#{Facter['hardwaremodel'].value},sparc,powerpc"})
    pkg = { :metadata => Tpkg::metadata_from_package(pkgfile), :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with one non-matching architecture
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => Tpkg::get_os, 'architecture' => 'bogus_arch'})
    pkg = { :metadata => Tpkg::metadata_from_package(pkgfile), :source => pkgfile }
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with a list of non-matching architectures
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => Tpkg::get_os, 'architecture' => 'bogus_arch1,bogus_arch2'})
    pkg = { :metadata => Tpkg::metadata_from_package(pkgfile), :source => pkgfile }
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
  end
  
  def test_available_packages_that_meet_requirement
    pkgfiles = []
    ['1.0', '1.1', '1.2', '1.3'].each do |ver|
      pkgfiles << make_package(:output_directory => @tempoutdir, :change => {'version' => ver}, :remove => ['operatingsystem', 'architecture'])
    end
    
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:base => testbase, :sources => pkgfiles)
    
    pkgs = tpkg.available_packages_that_meet_requirement
    nonnativepkgs = pkgs.select do |pkg|
      pkg[:source] != :native_installed && pkg[:source] != :native_available
    end
    assert_equal(4, nonnativepkgs.length)
    
    req = { :name => 'testpkg' }
    
    req[:minimum_version] = '1.2'
    req[:maximum_version] = '2.0'
    pkgs = tpkg.available_packages_that_meet_requirement(req)
    assert_equal(2, pkgs.length)
    pkgs.each do |pkg|
      assert(pkg[:metadata].elements['/tpkg/version'].text.to_f >= 1.2)
    end
    
    req[:minimum_version] = '1.1'
    req[:maximum_version] = '1.2'
    pkgs = tpkg.available_packages_that_meet_requirement(req)
    assert_equal(2, pkgs.length)
    pkgs.each do |pkg|
      assert(pkg[:metadata].elements['/tpkg/version'].text.to_f >= 1.1)
      assert(pkg[:metadata].elements['/tpkg/version'].text.to_f <= 1.2)
    end
    
    pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
    FileUtils.rm_rf(testbase)
  end
  
  def test_extract_reqs_from_metadata
    pkgfile = make_package(:output_directory => @tempoutdir, :dependencies => {'testpkg2' => {'minimum_version' => '1.0', 'maximum_version' => '3.0', 'minimum_package_version' => '1.5', 'maximum_package_version' => '2.5'}, 'testpkg3' => {}})
    metadata = Tpkg::metadata_from_package(pkgfile)
    reqs = Tpkg::extract_reqs_from_metadata(metadata)
    assert_equal(2, reqs.length)
    reqs.each do |req|
      if req[:name] == 'testpkg2'
        assert_equal('1.0', req[:minimum_version])
        assert_equal('3.0', req[:maximum_version])
        assert_equal('1.5', req[:minimum_package_version])
        assert_equal('2.5', req[:maximum_package_version])
        assert_equal(5, req.length)  # :name and 4 version requirements
      else
        assert_equal('testpkg3', req[:name])
        assert_equal(1, req.length)  # :name only
      end
    end
    FileUtils.rm_f(pkgfile)
  end
  
  def test_solve_dependencies
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:base => testbase, :sources => @pkgfiles)
    
    solutions = tpkg.solve_dependencies([{:name => 'a'}], {})
    
    # Our set of test packages has 4 valid solutions
    assert_equal(4, solutions.length)
    
    FileUtils.rm_rf(testbase)
  end
  
  def test_best_solution
    # Test that best_solution gives us the right answer using our test
    # package set in a new, clean base
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:base => testbase, :sources => @pkgfiles)
    solution_packages = tpkg.best_solution([{:name => 'a'}], {})
    # We should end up with a-1.0, b-1.0 (the specific one, not the generic
    # one), c-1.2 and d-1.2
    assert_equal(4, solution_packages.length)
    good = ['a-1.0-1.tpkg', 'b-1.0-1.tpkg', 'c-1.2-1.tpkg', 'd-1.2-1.tpkg']
    solution_packages.each { |pkg| assert(good.any? { |g| pkg[:source].include?(g) }) }
    FileUtils.rm_rf(testbase)
    
    # Now run a test to verify that we prefer already installed packages
    testbase = Tempdir.new("testbase")
    #  First install an older version of a
    older_apkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a', 'version' => '.9' }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    tpkg = Tpkg.new(:base => testbase, :sources => [older_apkg])
    tpkg.install(['a=.9'], PASSPHRASE)
    # Now request a with our set of test packages and verify that we get
    # back the currently installed 'a' pkg rather than the newer one that
    # is available from our test packages
    tpkg = Tpkg.new(:base => testbase, :sources => @pkgfiles)
    requirements = []
    packages = {}
    tpkg.requirements_for_currently_installed_packages(requirements, packages)
    requirements << {:name => 'a'}
    solution_packages = tpkg.best_solution(requirements, packages)
    assert_equal(1, solution_packages.length)
    assert_equal(:currently_installed, solution_packages.first[:source])
    assert_equal('a', solution_packages.first[:metadata].elements['/tpkg/name'].text)
    assert_equal('.9', solution_packages.first[:metadata].elements['/tpkg/version'].text)
    FileUtils.rm_f(older_apkg)
    FileUtils.rm_rf(testbase)
  end
  
  def test_requirements_for_currently_installed_packages
    testbase = Tempdir.new("testbase")
    apkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a', 'version' => '2.0' }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    tpkg = Tpkg.new(:base => testbase, :sources => [apkg])
    tpkg.install(['a'], PASSPHRASE)
    requirements = []
    packages = {}
    tpkg.requirements_for_currently_installed_packages(requirements, packages)
    assert_equal(1, requirements.length)
    assert_equal('a', requirements.first[:name])
    assert_equal('2.0', requirements.first[:minimum_version])
    # Given the way we set up the tpkg instance we should have two entries
    # in packages, one for the installed copy of the package and one for the
    # uninstalled copy
    assert_equal(2, packages['a'].length)
    assert(packages['a'].any? { |pkg| pkg[:source] == :currently_installed })
    assert(packages['a'].any? { |pkg| pkg[:source].include?('a-2.0-1.tpkg') })
    currently_installed_pkg = packages['a'].find { |pkg| pkg[:source] == :currently_installed }
    assert(currently_installed_pkg[:prefer])
    FileUtils.rm_f(apkg)
    FileUtils.rm_rf(testbase)
  end
  def test_parse_request
    req = Tpkg::parse_request('a')
    assert_equal(1, req.length)
    assert_equal('a', req[:name])
    
    req = Tpkg::parse_request('a=1.0')
    assert_equal(3, req.length)
    assert_equal('a', req[:name])
    assert_equal('1.0', req[:minimum_version])
    assert_equal('1.0', req[:maximum_version])
    
    req = Tpkg::parse_request('a=1.0=1')
    assert_equal(5, req.length)
    assert_equal('a', req[:name])
    assert_equal('1.0', req[:minimum_version])
    assert_equal('1.0', req[:maximum_version])
    assert_equal('1', req[:minimum_package_version])
    assert_equal('1', req[:maximum_package_version])
  end
  def test_parse_requests
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:base => testbase, :sources => @pkgfiles)
    requirements = []
    packages = {}
    
    tpkg.parse_requests('a', requirements, packages)
    assert_equal(1, requirements.length)
    assert_equal(1, requirements.first.length)
    assert_equal('a', requirements.first[:name])
    assert_equal(1, packages['a'].length)
    requirements.clear
    packages.clear
    
    tpkg.parse_requests('a=1.0', requirements, packages)
    assert_equal(1, requirements.length)
    assert_equal(3, requirements.first.length)
    assert_equal('a', requirements.first[:name])
    assert_equal('1.0', requirements.first[:minimum_version])
    assert_equal('1.0', requirements.first[:maximum_version])
    assert_equal(1, packages['a'].length)
    requirements.clear
    packages.clear
    
    tpkg.parse_requests('a=1.0=1', requirements, packages)
    assert_equal(1, requirements.length)
    assert_equal(5, requirements.first.length)
    assert_equal('a', requirements.first[:name])
    assert_equal('1.0', requirements.first[:minimum_version])
    assert_equal('1.0', requirements.first[:maximum_version])
    assert_equal('1', requirements.first[:minimum_package_version])
    assert_equal('1', requirements.first[:maximum_package_version])
    assert_equal(1, packages['a'].length)
    requirements.clear
    packages.clear
    
    apkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a', 'version' => '2.0' }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    tpkg.parse_requests(apkg, requirements, packages)
    assert_equal(1, requirements.length)
    assert_equal(1, requirements.first.length)
    assert_equal('a', requirements.first[:name])
    assert_equal(1, packages['a'].length)
    requirements.clear
    packages.clear
    FileUtils.rm_f(apkg)
    
    FileUtils.rm_rf(testbase)
  end
  
  def teardown
    @pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
  end
end
