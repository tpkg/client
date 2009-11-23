#
# Test tpkg's ability to resolve dependencies
#

require File.dirname(__FILE__) + '/tpkgtest'

class TpkgDependencyTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    
    @tempoutdir = Tempdir.new("tempoutdir")  # temp dir that will automatically get deleted at end of test run
                                             # can be used for storing packages
    @pkgfiles = []
    # a depends on b, and c >= 1.1, <= 1.2
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
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
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

    # More complicated test for PS-375
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'version' => '2.3', 'package_version' => '2' }, :remove => ['operatingsystem', 'architecture'])
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
    req = { :name => 'testpkg' }
    # version number is not equal to min or max version. So we don't care if min/max package version satisfied or not
    req[:minimum_version] = '0.5'
    req[:maximum_version] = '3.0'
    req[:minimum_package_version] = '3'
    req[:maximum_package_version] = '3'
    assert(Tpkg::package_meets_requirement?(pkg, req))
    req[:minimum_package_version] = '1'
    req[:maximum_package_version] = '1'
    assert(Tpkg::package_meets_requirement?(pkg, req))
    # version is same as maximum_version, so we have to look at maximum_package_version
    req[:minimum_version] = '0.5'
    req[:maximum_version] = '2.3'
    req[:minimum_package_version] = '1'
    req[:maximum_package_version] = '1'
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    req[:minimum_package_version] = '3'
    req[:maximum_package_version] = '3'
    assert(Tpkg::package_meets_requirement?(pkg, req))
    # version is same as minimum_version, so we have to look at minimum_package_version
    req[:minimum_version] = '2.3'
    req[:maximum_version] = '3.0'
    req[:minimum_package_version] = '3'
    req[:maximum_package_version] = '5'
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    req[:minimum_package_version] = '2'
    req[:maximum_package_version] = '3'
    assert(Tpkg::package_meets_requirement?(pkg, req))

    FileUtils.rm_f(pkgfile)
    
    #
    # Test architecture and operatingsystem handling
    #
    
    req = { :name => 'testpkg' }
    
    # Package with no OS specified
    pkgfile = make_package(:output_directory => @tempoutdir, :remove => ['operatingsystem'], :change => {'architecture' => Facter['hardwaremodel'].value})
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with one matching OS
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => Tpkg::get_os, 'architecture' => Facter['hardwaremodel'].value})
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with a matching OS in a list of OSs
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => "RedHat,CentOS,#{Tpkg::get_os},FreeBSD,Solaris", 'architecture' => Facter['hardwaremodel'].value})
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with one non-matching OS
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => 'bogus_os', 'architecture' => Facter['hardwaremodel'].value})
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with a list of non-matching OSs
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => 'bogus_os1,bogus_os2', 'architecture' => Facter['hardwaremodel'].value})
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with no architecture specified
    pkgfile = make_package(:output_directory => @tempoutdir, :remove => ['architecture'], :change => {'operatingsystem' => Tpkg::get_os })
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with one matching architecture
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => Tpkg::get_os, 'architecture' => Facter['hardwaremodel'].value})
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with a matching architecture in a list of architectures
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => Tpkg::get_os, 'architecture' => "i386,x86_64,#{Facter['hardwaremodel'].value},sparc,powerpc"})
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with one non-matching architecture
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => Tpkg::get_os, 'architecture' => 'bogus_arch'})
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)
    
    # Package with a list of non-matching architectures
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => Tpkg::get_os, 'architecture' => 'bogus_arch1,bogus_arch2'})
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
    assert(!Tpkg::package_meets_requirement?(pkg, req))
    FileUtils.rm_f(pkgfile)

    # Package with operatingsystem and arch specified as regex
    pkgfile = make_package(:output_directory => @tempoutdir, :change => {'operatingsystem' => 'RedHat|CentOS|Fedora|Debian|Ubuntu|Solaris|FreeBSD|Darwin',  'architecture' => "i386|x86_64|#{Facter['hardwaremodel'].value}|sparc|powerpc"})
    metadata_xml = Tpkg::metadata_from_package(pkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    pkg = { :metadata => metadata, :source => pkgfile }
    assert(Tpkg::package_meets_requirement?(pkg, req))
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
      assert(pkg[:metadata][:version].to_f >= 1.2)
    end
    
    req[:minimum_version] = '1.1'
    req[:maximum_version] = '1.2'
    pkgs = tpkg.available_packages_that_meet_requirement(req)
    assert_equal(2, pkgs.length)
    pkgs.each do |pkg|
      assert(pkg[:metadata][:version].to_f >= 1.1)
      assert(pkg[:metadata][:version].to_f <= 1.2)
    end
    
    # Test a package name which has no available packages
    req[:name] = 'otherpkg'
    pkgs = tpkg.available_packages_that_meet_requirement(req)
    assert(pkgs.empty?)

    # PS-478
    pkgfiles << make_package(:output_directory => @tempoutdir, :change => {'version' => '2'}, :remove => ['operatingsystem', 'architecture', 'package_version'])
    pkgfiles << make_package(:output_directory => @tempoutdir, :change => {'version' => '2', 'package_version' => '1'}, :remove => ['operatingsystem', 'architecture'])
    pkgfiles << make_package(:output_directory => @tempoutdir, :change => {'version' => '2', 'package_version' => '112'}, :remove => ['operatingsystem', 'architecture'])
    tpkg = Tpkg.new(:base => testbase, :sources => pkgfiles)

    req = { :name => 'testpkg' }
    
    # Should only match package of version 2 and NO package version
    req[:allowed_versions] = '2'
    pkgs = tpkg.available_packages_that_meet_requirement(req)
    assert_equal(1, pkgs.length)

    # Should match any packages that has a version number that starts with 2
    req[:allowed_versions] = '2*'
    pkgs = tpkg.available_packages_that_meet_requirement(req)
    assert_equal(3, pkgs.length)

    # Should match any packages that is version 2 AND has a package version number
    req[:allowed_versions] = '2-*'
    pkgs = tpkg.available_packages_that_meet_requirement(req)
    assert_equal(2, pkgs.length)

    # Should match any packages that is version 2 AND has a package version number that ends with 2
    req[:allowed_versions] = '2-*2'
    pkgs = tpkg.available_packages_that_meet_requirement(req)
    assert_equal(1, pkgs.length)

    
    pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
    FileUtils.rm_rf(testbase)
  end
  
  def test_best_solution
    # Test that best_solution gives us the right answer using our test
    # package set in a new, clean base
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:base => testbase, :sources => @pkgfiles)
    solution_packages = tpkg.best_solution([{:name => 'a'}], {}, ['a'])
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
    tpkg = Tpkg.new(:base => testbase, :sources => [older_apkg] + @pkgfiles)
    tpkg.install(['a=.9'], PASSPHRASE)
    # Now request 'a' and verify that we get back the currently installed
    # 'a' pkg rather than the newer one that is available from our test
    # packages
    requirements = []
    packages = {}
    tpkg.requirements_for_currently_installed_packages(requirements, packages)
    requirements << {:name => 'a'}
    solution_packages = tpkg.best_solution(requirements, packages, ['a'])
    assert_equal(1, solution_packages.length)
    assert_equal(:currently_installed, solution_packages.first[:source])
    assert_equal('a', solution_packages.first[:metadata][:name])
    assert_equal('.9', solution_packages.first[:metadata][:version])
    FileUtils.rm_f(older_apkg)
    FileUtils.rm_rf(testbase)

    # Test that we don't prefer installed packages if :prefer is false
    testbase = Tempdir.new("testbase")
    #  First install an older version of d
    older_dpkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'd', 'version' => '.9' }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    tpkg = Tpkg.new(:base => testbase, :sources => [older_dpkg] + @pkgfiles)
    tpkg.install(['d=.9'], PASSPHRASE)
    # Now request an update of 'd' and verify that we get back the newer
    # available 'd' pkg rather than the currently installed package.
    requirements = []
    packages = {}
    tpkg.requirements_for_currently_installed_packages(requirements, packages)
    # Remove preference for currently installed package
    packages['d'].each do |pkg|
      if pkg[:source] == :currently_installed
        pkg[:prefer] = false
      end
    end
    solution_packages = tpkg.best_solution(requirements, packages, ['d'])
    assert_equal(1, solution_packages.length)
    assert(solution_packages.first[:source].include?('d-1.3-1.tpkg'))
    FileUtils.rm_f(older_dpkg)
    FileUtils.rm_rf(testbase)

    # Test that we don't prefer installed packages if :prefer is false
    # This is a more complex test than the previous, as the 'a' package
    # in our test @pkgfiles has dependencies, whereas the initial older
    # version we install does not.  The new dependencies could throw off
    # the scoring process.
    testbase = Tempdir.new("testbase")
    #  First install an older version of a
    older_apkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a', 'version' => '.9' }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    tpkg = Tpkg.new(:base => testbase, :sources => [older_apkg] + @pkgfiles)
    tpkg.install(['a=.9'], PASSPHRASE)
    # Now request an update of 'a' and verify that we get back the newer
    # available 'a' pkg rather than the currently installed package.
    requirements = []
    packages = {}
    tpkg.requirements_for_currently_installed_packages(requirements, packages)
    # Remove preference for currently installed package
    packages['a'].each do |pkg|
      if pkg[:source] == :currently_installed
        pkg[:prefer] = false
      end
    end
    solution_packages = tpkg.best_solution(requirements, packages, ['a'])
    # The solution should pull in the newer 'a' and its dependencies
    assert_equal(4, solution_packages.length)
    selectedapkg = solution_packages.find{|pkg| pkg[:metadata][:name] == 'a'}
    assert(selectedapkg[:source].include?('a-1.0-1.tpkg'))
    FileUtils.rm_f(older_apkg)
    FileUtils.rm_rf(testbase)
    
    # Test with no valid solution, ensure it fails
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:base => testbase, :sources => @pkgfiles)
    solution_packages = tpkg.best_solution([{:name => 'a'}, {:name => 'c', :minimum_version => '1.3'}], {}, ['a', 'c'])
    assert_nil(solution_packages)
    FileUtils.rm_rf(testbase)
  end
  
  # best_solution is a thin wrapper of this method, most of the testing
  # is in test_best_solution
  def test_resolve_dependencies
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:base => testbase, :sources => @pkgfiles)
    
    result = tpkg.resolve_dependencies([{:name => 'a'}], {}, ['a'])
    assert(result.has_key?(:solution))
    solution = result[:solution]
    
    # We should end up with a-1.0, b-1.0 (the specific one, not the generic
    # one), c-1.2 and d-1.2
    puts solution.inspect
    assert_equal(4, solution.length)
    good = ['a-1.0-1.tpkg', 'b-1.0-1.tpkg', 'c-1.2-1.tpkg', 'd-1.2-1.tpkg']
    solution.each { |pkg| assert(good.any? { |g| pkg[:source].include?(g) }) }
    
    FileUtils.rm_rf(testbase)
  end
  
  # This method is only used by resolve_dependencies, so the testing
  # here is minimal.
  def test_check_solution
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:base => testbase, :sources => @pkgfiles)
    
    solution = nil
    requirements = [{:name => 'c', :minimum_version => '1.3'}, {:name => 'd', :minimum_version => '1.3'}]
    packages = {}
    requirements.each do |req|
      packages[req[:name]] = tpkg.available_packages_that_meet_requirement(req)
    end
    core_packages = ['c']
    number_of_possible_solutions_checked = 0
    
    result = nil
    # Check a valid solution
    solution = {:pkgs => packages.values.flatten}
    assert_nothing_raised { result = tpkg.check_solution(solution, requirements, packages, core_packages, number_of_possible_solutions_checked) }
    assert(result.has_key?(:solution))
    assert_equal(packages.values.flatten, result[:solution])
    
    # Check an invalid solution
    xpkgfile = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'x' }, :dependencies => {'y' => {}}, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    metadata_xml = Tpkg::metadata_from_package(xpkgfile)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    xpkg = {:metadata => metadata}
    solution[:pkgs] << xpkg
    assert_nothing_raised { result = tpkg.check_solution(solution, requirements, packages, core_packages, number_of_possible_solutions_checked) }
    assert(!result.has_key?(:solution))
    assert(result.has_key?(:number_of_possible_solutions_checked))
    assert(result[:number_of_possible_solutions_checked] > 0)
    FileUtils.rm_f(xpkgfile)
    
    FileUtils.rm_rf(testbase)
  end
  
  def test_requirements_for_currently_installed_package
    pkgfile = make_package(:output_directory => @tempoutdir, :remove => ['operatingsystem', 'architecture'])
    pkgfile2 = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'testpkg2' }, :remove => ['package_version', 'operatingsystem', 'architecture'])
    testbase = Tempdir.new("testbase")
    tpkg = Tpkg.new(:base => testbase, :sources => [pkgfile, pkgfile2])
    tpkg.install('testpkg')
    tpkg.install('testpkg2')
    requirements = nil
    assert_nothing_raised { requirements = tpkg.requirements_for_currently_installed_package('testpkg') }
    assert_equal(1, requirements.length)
    assert_equal('testpkg', requirements.first[:name])
    assert_equal('1.0', requirements.first[:minimum_version])
    assert_equal('1', requirements.first[:minimum_package_version])
    assert_nothing_raised { requirements = tpkg.requirements_for_currently_installed_package('testpkg2') }
    assert_equal(1, requirements.length)
    assert_equal('testpkg2', requirements.first[:name])
    assert_equal('1.0', requirements.first[:minimum_version])
    assert_nil(requirements.first[:minimum_package_version])
    FileUtils.rm_f(pkgfile)
    FileUtils.rm_f(pkgfile2)
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
    
    # Test various package spec requests
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
    
    # Test with a given filename rather than a package spec
    apkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a', 'version' => '2.0' }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    tpkg.parse_requests(apkg, requirements, packages)
    assert_equal(1, requirements.length)
    assert_equal(1, requirements.first.length)   # should this be 5?
    assert_equal('a', requirements.first[:name])
    assert_equal(1, packages['a'].length)
    requirements.clear
    packages.clear
    FileUtils.rm_f(apkg)

    # Test with a filename of a package that has been installed rather than a package spec
    apkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a', 'version' => '2.0' }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    tpkg.install([apkg], PASSPHRASE)
    FileUtils.rm_f(apkg)
    tpkg.parse_requests(File.basename(apkg), requirements, packages)
    assert_equal(1, requirements.length)
    assert_equal(5, requirements.first.length)  # name, min ver, max ver, min package version, max package version
    assert_equal('a', requirements.first[:name])
    assert_equal('2.0', requirements.first[:minimum_version])
    assert_equal('2.0', requirements.first[:maximum_version])
    assert_equal('1', requirements.first[:minimum_package_version])
    assert_equal('1', requirements.first[:maximum_package_version])
    assert_equal(1, packages['a'].length)
    requirements.clear
    packages.clear
 
    # check_requests does some additional checks for requests by
    # filename or URI, test those
    
    # First just check that it properly checks a package with dependencies
    apkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a', 'version' => '2.0' }, :dependencies => {'b' => {}}, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    tpkg.parse_requests(apkg, requirements, packages)
    assert_nothing_raised { tpkg.check_requests(packages) }
    assert_equal(1, requirements.length)
    assert_equal(1, requirements.first.length)
    assert_equal('a', requirements.first[:name])
    assert_equal(1, packages['a'].length)
    requirements.clear
    packages.clear
    FileUtils.rm_f(apkg)

    # PS-465: local package dependencies on install
    # Check that tpkg accept list of local packages where one depends on another
    localapkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'locala', 'version' => '1.0' }, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    localbpkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'localb', 'version' => '1.0' }, :dependencies => {'locala' => {}}, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    localcpkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'localc', 'version' => '1.0' }, :dependencies => {'nonexisting' => {}}, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    tpkg.parse_requests([localapkg, localbpkg], requirements, packages) 
    assert_nothing_raised { tpkg.check_requests(packages) }
    requirements.clear
    packages.clear
    tpkg.parse_requests([localbpkg, localapkg], requirements, packages) 
    assert_nothing_raised { tpkg.check_requests(packages) }
    requirements.clear
    packages.clear
    # Should not be ok since localc depends on nonexisting package
    tpkg.parse_requests([localapkg, localbpkg, localcpkg], requirements, packages) 
    assert_raise(RuntimeError) { tpkg.check_requests(packages) }
    requirements.clear
    packages.clear
    FileUtils.rm_f(localapkg)
    FileUtils.rm_f(localbpkg)
    
    # Verify that it rejects a package that can't be installed on this
    # machine
    apkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a', 'version' => '2.0', 'operatingsystem' => 'bogusos' }, :dependencies => {'b' => {}}, :remove => ['posix_acl', 'windows_acl'])
    tpkg.parse_requests(apkg, requirements, packages) 
    assert_raise(RuntimeError) { tpkg.check_requests(packages) }
    requirements.clear
    packages.clear
    FileUtils.rm_f(apkg)    
    
    # Verify that it rejects a package with an unresolvable dependency
    apkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a', 'version' => '2.0' }, :dependencies => {'x' => {}}, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
    tpkg.parse_requests(apkg, requirements, packages) 
    assert_raise(RuntimeError) { tpkg.check_requests(packages) }
    requirements.clear
    packages.clear
    FileUtils.rm_f(apkg)    

    FileUtils.rm_rf(testbase)
  end
  
  def teardown
    @pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
  end
end
