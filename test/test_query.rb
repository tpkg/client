

#
# Test tpkg's query features
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgQueryTests < Test::Unit::TestCase
  include TpkgTests

  def setup
    Tpkg::set_prompt(false)

    # temp dir that will automatically get deleted at end of test run, can be
    # used for storing packages
    @tempoutdir = Dir.mktmpdir('tempoutdir')

    # Make up our regular test package
    @pkgfile = make_package(:output_directory => @tempoutdir)
  end

  def test_metadata_for_installed_packages
    Dir.mktmpdir('testbase') do |testbase|
      apkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a', 'version' => '2.0' }, :remove => ['operatingsystem', 'architecture'])
      tpkg = Tpkg.new(:base => testbase, :sources => [apkg])
      tpkg.install(['a'], PASSPHRASE)
      metadata = tpkg.metadata_for_installed_packages
      assert_equal(1, metadata.length)
      assert_equal('a', metadata.first[:name])
      FileUtils.rm_f(apkg)
    end
  end

  def test_installed_packages
    Dir.mktmpdir('testbase') do |testbase|
      apkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a', 'version' => '2.0' }, :remove => ['operatingsystem', 'architecture'])
      bpkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'b', 'version' => '2.0' }, :remove => ['operatingsystem', 'architecture'])
      tpkg = Tpkg.new(:base => testbase, :sources => [apkg, bpkg])
      tpkg.install(['a', 'b'], PASSPHRASE)

      instpkgs = tpkg.installed_packages
      assert_equal(2, instpkgs.length)
      assert(instpkgs.any? {|instpkg| instpkg[:metadata][:name] == 'a'})
      assert(instpkgs.any? {|instpkg| instpkg[:metadata][:name] == 'b'})
      assert(instpkgs.all? {|instpkg| instpkg[:source] == :currently_installed})
      assert(instpkgs.all? {|instpkg| instpkg[:prefer] == true})

      instpkgs = tpkg.installed_packages('b')
      assert_equal(1, instpkgs.length)
      assert_equal('b', instpkgs.first[:metadata][:name])

      FileUtils.rm_f(apkg)
      FileUtils.rm_f(bpkg)
    end
  end

  def test_installed_packages_that_meet_requirement
    Dir.mktmpdir('testbase') do |testbase|
      tpkg = Tpkg.new(:base => testbase)
      pkgfiles = []
      ['1.0', '2.0'].each do |ver|
        Dir.mktmpdir('srcdir') do |srcdir|
          FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
          pkg = make_package(:output_directory => @tempoutdir, :change => { 'name' => 'a', 'version' => ver }, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture'])
          tpkg.install([pkg], PASSPHRASE)
          pkgfiles << pkg
        end
      end
      result = tpkg.installed_packages_that_meet_requirement
      assert_equal(2, result.length)
      result = tpkg.installed_packages_that_meet_requirement({:name => 'a'})
      assert_equal(2, result.length)
      result = tpkg.installed_packages_that_meet_requirement({:name => 'a', :minimum_version => '2.0'})
      assert_equal(1, result.length)
      pkgfiles.each { |pkg| FileUtils.rm_f(pkg) }
    end
  end

  def test_files_for_installed_packages
    pkgfiles = []
    # Make up a couple of packages with different files in them so that
    # they don't conflict
    ['a', 'b'].each do |pkgname|
      Dir.mktmpdir('srcdir') do |srcdir|
        FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
        FileUtils.mkdir_p(File.join(srcdir, 'reloc', 'directory'))
        File.open(File.join(srcdir, 'reloc', 'directory', pkgname), 'w') do |file|
          file.puts pkgname
        end
        pkgfiles << make_package(:output_directory => @tempoutdir, :change => {'name' => pkgname}, :source_directory => srcdir, :remove => ['operatingsystem', 'architecture'])
      end
    end

    Dir.mktmpdir('testbase') do |testbase|
      tpkg = Tpkg.new(:base => testbase, :sources => pkgfiles)
      tpkg.install(['a', 'b'], PASSPHRASE)

      files = tpkg.files_for_installed_packages
      assert_equal(2, files.length)
      files.each do |pkgfile, fip|
        assert_equal(0, fip[:root].length)  # Neither package has non-relocatable files
        assert_equal(2, fip[:reloc].length)  # Each package has two relocatable files (a directory and a file)
        pkgname = fip[:metadata][:name]
        assert_equal(File.join('directory', ''), fip[:reloc].first)
        assert_equal(File.join('directory', pkgname), fip[:reloc].last)
        assert_equal(File.join(testbase, 'directory', ''), fip[:normalized].first)
        assert_equal(File.join(testbase, 'directory', pkgname), fip[:normalized].last)
      end

      files = tpkg.files_for_installed_packages(pkgfiles.first)
      assert_equal(1, files.length)
    end

    pkgfiles.each { |pkg| FileUtils.rm_f(pkg) }
  end

  def test_files_in_package
    files = Tpkg::files_in_package(@pkgfile)
    assert_equal(0, files[:root].length)
    pwd = Dir.pwd
    Dir.chdir(File.join(TESTPKGDIR, 'reloc'))
    reloc_expected = Dir.glob('*')
    Dir.chdir(pwd)
    assert_equal(reloc_expected.length, files[:reloc].length)
    reloc_expected.each { |r| assert(files[:reloc].include?(r)) }
    files[:reloc].each { |r| assert(reloc_expected.include?(r)) }
  end

  def teardown
    FileUtils.rm_rf(@tempoutdir)
  end
end

