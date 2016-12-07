#
# Test tpkg's crontab handling methods
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgCrontabTests < Test::Unit::TestCase
  include TpkgTests

  def setup
    Tpkg::set_prompt(false)

    # Pretend to be an OS with cron.d support
    fact = Facter::Util::Fact.new('operatingsystem')
    fact.stubs(:value).returns('RedHat')
    Facter.stubs(:[]).returns(fact)
  end

  def test_crontabs
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(
        File.join(srcdir, 'tpkg.xml'),
        :change => { 'name' => 'cronpkg' },
        :files => {
          'etc/crontab_user' => { 'crontab' => {'user' => 'nobody'} },
          'etc/cron.d/crontab' => { 'crontab' => {} } })
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot)
      assert_equal(
        {
          "#{testroot}/opt/tpkg/etc/crontab_user" =>
            {'path'=>'etc/crontab_user', 'crontab'=>{'user'=>'nobody'}},
          "#{testroot}/opt/tpkg/etc/cron.d/crontab" =>
            {'path'=>'etc/cron.d/crontab', 'crontab'=>{}}
        },
        tpkg.crontabs(metadata))

      assert_equal({}, tpkg.crontabs({}))
      assert_equal({}, tpkg.crontabs({:files => {}}))
      assert_equal({}, tpkg.crontabs({:files => {:files => {}}}))
    end
  end
  def test_crontab_destinations
    pkg = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir_p("#{srcdir}/reloc/etc/cron.d")
      File.open("#{srcdir}/reloc/etc/crontab_user", 'w') do |file|
        file.puts('user crontab')
      end
      File.open("#{srcdir}/reloc/etc/cron.d/crontab", 'w') do |file|
        file.puts('cron.d crontab')
      end
      pkg = make_package(
        :change => { 'name' => 'cronpkg' },
        :source_directory => srcdir,
        :files => {
          'etc/crontab_user' => { 'crontab' => {'user' => 'nobody'} },
          'etc/cron.d/crontab' => { 'crontab' => {} } },
        :remove => ['operatingsystem', 'architecture'])
    end
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot, :sources => [pkg])
      metadata = Tpkg::metadata_from_package(pkg)
      assert_equal(
        {
          "#{testroot}/opt/tpkg/etc/crontab_user" => {:type=>:file, :user=>'nobody'},
          "#{testroot}/opt/tpkg/etc/cron.d/crontab" => {:type=>:link, :path=>'/etc/cron.d/crontab'},
        },
        tpkg.crontab_destinations(metadata))
    end
    FileUtils.rm_f(pkg)
  end
  def test_crontab_destination
    tpkg = Tpkg.new
    assert_equal(
      {:type=>:file, :user=>'nobody'},
      tpkg.crontab_destination(
        '/opt/tpkg/etc/crontab_user', {:crontab => {:user => 'nobody'}}))
    assert_equal(
      {:type=>:link, :path=>'/etc/cron.d/crontab'},
      tpkg.crontab_destination(
        '/opt/tpkg/etc/cron.d/crontab', {:crontab => {}}))
  end

  def test_install_crontabs
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(
        File.join(srcdir, 'tpkg.xml'),
        :change => { 'name' => 'cronpkg' },
        :files => {
          'etc/crontab_user' => { 'crontab' => {'user' => 'nobody'} },
          'etc/cron.d/crontab' => { 'crontab' => {} } })
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot)
      tpkg.expects(:install_crontab_link).with(metadata, "#{testroot}/opt/tpkg/etc/cron.d/crontab", '/etc/cron.d/crontab')
      tpkg.expects(:install_crontab_file).with(metadata, "#{testroot}/opt/tpkg/etc/crontab_user", 'nobody')
      tpkg.install_crontabs(metadata)
    end
  end
  def test_install_crontab_link
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(
        File.join(srcdir, 'tpkg.xml'),
        :change => { 'name' => 'cronpkg'  },
        :files => { 'etc/cron.d/crontab' => { 'crontab' => {} } })
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot)
      crontab = "#{testroot}/opt/tpkg/etc/cron.d/crontab"
      destination = "#{testroot}/etc/cron.d/crontab"

      # Directory for link doesn't exist, directory and link are created
      tpkg.install_crontab_link(metadata, crontab, destination)
      assert(File.symlink?(destination))
      assert_equal(crontab, File.readlink(destination))

      # Link already exists, nothing is done
      sleep 2
      beforetime = File.lstat(destination).mtime
      tpkg.install_crontab_link(metadata, crontab, destination)
      assert(File.symlink?(destination))
      assert_equal(crontab, File.readlink(destination))
      assert_equal(beforetime, File.lstat(destination).mtime)

      # Existing files or links up to 8 already exist, link created with appropriate suffix
      File.delete(destination)
      File.symlink('somethingelse', destination)
      0.upto(8) do |i|
        File.delete(destination + i.to_s) if (i != 0)
        File.symlink('somethingelse', destination + i.to_s)
        tpkg.install_crontab_link(metadata, crontab, destination)
        assert(File.symlink?(destination + (i + 1).to_s))
        assert_equal(crontab, File.readlink(destination + (i + 1).to_s))
      end

      # Existing files or links up to 9 already exist, exception raised
      File.delete(destination + '9')
      File.symlink('somethingelse', destination + '9')
      assert_raise(RuntimeError) { tpkg.install_crontab_link(metadata, crontab, destination) }
    end
  end
  def test_crontab_uoption
    current_user = Etc.getpwuid.name
    tpkg = Tpkg.new
    assert_equal '', tpkg.crontab_uoption('ANY')
    assert_equal '', tpkg.crontab_uoption(current_user)
    assert_equal '-u nobody', tpkg.crontab_uoption('nobody')
  end
  # Test that install_crontab_file calls the crontab command with the -u
  # option if the package request that the crontab be installed for a user
  # other than the current user
  def test_install_crontab_file_with_uoption
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(
        File.join(srcdir, 'tpkg.xml'),
        :change => { 'name' => 'cronpkg' },
        :files => {
          'etc/crontab_user' => { 'crontab' => {'user' => 'BoguS'} }})
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end
    tpkg = Tpkg.new
    tpkg.expects(:`).with('crontab -u nobody -l').returns('')
    crontab = Tempfile.new('tpkgtest_cron')
    tpkg.expects(:system).with(regexp_matches(/\Acrontab -u nobody [^-]/))
    tpkg.install_crontab_file(metadata, crontab, 'nobody')
  end
  # And test that it omits the -u option if the crontab is for the current
  # user
  def test_install_crontab_file_without_uoption
    current_user = Etc.getpwuid.name
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(
        File.join(srcdir, 'tpkg.xml'),
        :change => { 'name' => 'cronpkg' },
        :files => {
          'etc/crontab_user' => { 'crontab' => {'user' => current_user} }})
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end
    tpkg = Tpkg.new
    tpkg.expects(:`).with('crontab  -l').returns('')
    crontab = Tempfile.new('tpkgtest_cron')
    tpkg.expects(:system).with(regexp_matches(/\Acrontab [^-]/))
    tpkg.install_crontab_file(metadata, crontab, current_user)
  end
  # And finally, test that it properly adds the given crontab to the user's
  # crontab
  def test_install_crontab_file_operation
    current_user = Etc.getpwuid.name
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(
        File.join(srcdir, 'tpkg.xml'),
        :change => { 'name' => 'cronpkg' },
        :files => {
          'etc/crontab_user' => { 'crontab' => {'user' => 'BoguS'} }})
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end
    fake_filename = '/path/to/cronpkg-1.0.tpkg'
    metadata[:filename] = fake_filename
    Dir.mktmpdir('testroot') do |testroot|
      existing_contents = "* * * * *  /existing/job\n"
      user_crontab = Tempfile.new('tpkgtest_cron')
      user_crontab.write existing_contents
      user_crontab.close
      package_crontab = "#{testroot}/opt/tpkg/etc/crontab_user"
      FileUtils.mkdir_p(File.dirname(package_crontab))
      new_contents = "1 2 * * *  /new/job\n"
      File.open(package_crontab, 'w') do |file|
        file.write new_contents
      end
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :cmd_crontab => File.join(TESTCMDDIR, "crontab -f #{user_crontab.path}"))
      tpkg.install_crontab_file(metadata, package_crontab, current_user)
      user_crontab.open
      assert_equal(
        existing_contents +
          "### TPKG START - #{testroot}/opt/tpkg - #{File.basename(fake_filename)}\n" +
          new_contents +
          "### TPKG END - #{testroot}/opt/tpkg - #{File.basename(fake_filename)}\n",
        user_crontab.read)
    end
  end
  def test_remove_crontabs
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(
        File.join(srcdir, 'tpkg.xml'),
        :change => { 'name' => 'cronpkg' },
        :files => {
          'etc/crontab_user' => { 'crontab' => {'user' => 'nobody'} },
          'etc/cron.d/crontab' => { 'crontab' => {} } })
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot)
      tpkg.expects(:remove_crontab_file).with(metadata, 'nobody')
      tpkg.expects(:remove_crontab_link).with(metadata, "#{testroot}/opt/tpkg/etc/cron.d/crontab", '/etc/cron.d/crontab')
      tpkg.remove_crontabs(metadata)
    end
  end
  def test_remove_crontab_link
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(
        File.join(srcdir, 'tpkg.xml'),
        :change => { 'name' => 'cronpkg' },
        :files => { 'etc/cron.d/crontab' => { 'crontab' => {} } })
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end
    Dir.mktmpdir('testroot') do |testroot|
      tpkg = Tpkg.new(:file_system_root => testroot)
      crontab = File.join(testroot, '/opt/tpkg/etc/cron.d/crontab')
      destination = File.join(testroot, '/etc/cron.d/crontab')

      # Standard symlink using the base name is removed
      FileUtils.mkdir_p(File.dirname(destination))
      File.symlink(crontab, destination)
      tpkg.remove_crontab_link(metadata, crontab, destination)
      refute File.symlink?(destination)
      refute File.exist?(destination)

      # Links with suffixes from 1..9 are removed
      1.upto(9) do |i|
        FileUtils.rm(Dir.glob(destination + '*'))
        File.symlink(crontab, destination + i.to_s)
        File.symlink(crontab, destination + '1') if (i != 1)
        2.upto(i-1) do |j|
          File.symlink('somethingelse', destination + j.to_s)
        end
        tpkg.remove_crontab_link(metadata, crontab, destination)
        refute File.exist?(destination)
        refute File.symlink?(destination)
        refute File.exist?(destination + '1')
        refute File.symlink?(destination + '1')
        2.upto(i-1) do |j|
          assert(File.symlink?(destination + j.to_s))
          assert_equal('somethingelse', File.readlink(destination + j.to_s))
        end
      end

      # Links with suffixes of 0 or 10 are left alone
      File.symlink(crontab, destination + '0')
      File.symlink(crontab, destination + '10')
      tpkg.remove_crontab_link(metadata, crontab, destination)
      assert File.symlink?(destination + '0')
      assert_equal crontab, File.readlink(destination + '0')
      assert File.symlink?(destination + '10')
      assert_equal crontab, File.readlink(destination + '10')
    end
  end
  def test_remove_crontab_file_with_uoption
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(
        File.join(srcdir, 'tpkg.xml'),
        :change => { 'name' => 'cronpkg' },
        :files => {
          'etc/crontab_user' => { 'crontab' => {'user' => 'BoguS'} }})
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end
    tpkg = Tpkg.new
    tpkg.expects(:`).with('crontab -u nobody -l').returns('')
    crontab = Tempfile.new('tpkgtest_cron')
    tpkg.expects(:system).with(regexp_matches(/\Acrontab -u nobody [^-]/))
    tpkg.remove_crontab_file(metadata, 'nobody')
  end
  def test_remove_crontab_file_without_uoption
    current_user = Etc.getpwuid.name
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(
        File.join(srcdir, 'tpkg.xml'),
        :change => { 'name' => 'cronpkg' },
        :files => {
          'etc/crontab_user' => { 'crontab' => {'user' => current_user} }})
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end
    tpkg = Tpkg.new
    tpkg.expects(:`).with('crontab  -l').returns('')
    crontab = Tempfile.new('tpkgtest_cron')
    tpkg.expects(:system).with(regexp_matches(/\Acrontab [^-]/))
    tpkg.remove_crontab_file(metadata, current_user)
  end
  def test_remove_crontab_file_operation
    current_user = Etc.getpwuid.name
    metadata = nil
    Dir.mktmpdir('srcdir') do |srcdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      create_metadata_file(
        File.join(srcdir, 'tpkg.xml'),
        :change => { 'name' => 'cronpkg' },
        :files => {
          'etc/crontab_user' => { 'crontab' => {'user' => 'BoguS'} }})
      metadata = Metadata.new(File.read(File.join(srcdir, 'tpkg.xml')), 'xml')
    end
    fake_filename = '/path/to/cronpkg-1.0.tpkg'
    metadata[:filename] = fake_filename
    Dir.mktmpdir('testroot') do |testroot|
      testbase = "#{testroot}/opt/tpkg"
      not_my_part_one = <<-EOF.gsub(/^\s+/, '')
        * * * * * /this/is/not/a/tpkg/cronjob
        EOF
      my_part_one = <<-EOF.gsub(/^\s+/, '')
        ### TPKG START - #{testbase} - #{File.basename(metadata[:filename])}
        * * * * * /this/is/my/crontab
        ### TPKG END - #{testbase} - #{File.basename(metadata[:filename])}
        EOF
      not_my_part_two = <<-EOF.gsub(/^\s+/, '')
        ### TPKG START - #{testbase} - someotherpkg-2.34.tpkg
        * * * * * /this/is/not/my/crontab
        ### TPKG END - #{testbase} - someotherpkg-2.34.tpkg
        ### TPKG START - /path/to/other/base - #{File.basename(metadata[:filename])}
        * * * * * /this/is/not/my/crontab
        ### TPKG END - /path/to/other/base - #{File.basename(metadata[:filename])}
        EOF
      my_part_two = <<-EOF.gsub(/^\s+/, '')
        ### TPKG START - #{testbase} - #{File.basename(metadata[:filename])}
        * * * * * /this/is/my/crontab
        ### TPKG END - #{testbase} - #{File.basename(metadata[:filename])}
        EOF
      user_crontab = Tempfile.new('tpkgtest_cron')
      user_crontab.write not_my_part_one + my_part_one + not_my_part_two + my_part_two
      user_crontab.close
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :cmd_crontab => File.join(TESTCMDDIR, "crontab -f #{user_crontab.path}"))
      tpkg.remove_crontab_file(metadata, current_user)
      user_crontab.open
      assert_equal(not_my_part_one + not_my_part_two, user_crontab.read)
    end
  end

  def teardown
    Facter.unstub(:[])
  end
end
