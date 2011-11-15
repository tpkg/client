# FIXME: should rename this to test_switches, they're properly called switches not options
#
# Test tpkg command line options
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))
require 'open3'
require 'rbconfig'

RUBY = File.join(*RbConfig::CONFIG.values_at("bindir", "ruby_install_name")) +
         RbConfig::CONFIG["EXEEXT"]
TPKG_EXECUTABLE = File.expand_path('../bin/tpkg', File.dirname(__FILE__))

class TpkgOptionTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
    @testroot = Dir.mktmpdir('testroot')
    # Make up our regular test package
    @pkgfile = make_package(:remove => ['operatingsystem', 'architecture'])
  end
  
  def test_help
    output = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    IO.popen("#{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --help") do |pipe|
      output = pipe.readlines
    end
    # Make sure at least something resembling help output is there
    assert(output.any? {|line| line.include?('Usage: tpkg')}, 'help output content')
    # Make sure it fits on the screen
    assert(output.all? {|line| line.length <= 80}, 'help output columns')
    # Too many options for 23 lines
    #assert(output.size <= 23, 'help output lines')
  end
  
  # --query/-q
  def test_query
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        ['-q', '--query'].each do |switch|
          IO.popen("#{RUBY} #{TPKG_EXECUTABLE} #{switch} #{query} --test-root #{testroot}") do |pipe|
            output = pipe.read
            assert_equal(
              "No packages matching '#{query}' installed\n",
              output, "#{switch} #{query}, not installed")
          end
          assert_equal(1, $?.exitstatus, "#{switch} #{query}, not installed, exitstatus")
          # Same query with --quiet should be quiet
          IO.popen("#{RUBY} #{TPKG_EXECUTABLE} #{switch} #{query} --quiet --test-root #{testroot}") do |pipe|
            output = pipe.read
            assert_equal("", output, "#{switch} #{query} --quiet, not installed")
          end
          assert_equal(1, $?.exitstatus, "#{switch} #{query} --quiet, not installed, exitstatus")
        end
      end
      
      pkgfile2 = make_package(:change => {'name' => 'querypkg'},
                              :remove => ['operatingsystem', 'architecture'],
                              :output_directory => File.join(testroot, 'tmp'))
      metadata2 = Tpkg::metadata_from_package(pkgfile2)
      
      # Install packages and try again
      tpkg = Tpkg.new(:file_system_root => testroot, :sources => [@pkgfile, pkgfile2])
      tpkg.install([@pkgfile, pkgfile2], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        ['-q', '--query'].each do |switch|
          IO.popen("#{RUBY} #{TPKG_EXECUTABLE} #{switch} #{query} --test-root #{testroot}") do |pipe|
            output = pipe.read
            assert_equal(File.basename(@pkgfile), output.chomp, "#{switch} #{query}, installed")
          end
          assert_equal(0, $?.exitstatus, "#{switch} #{query}, installed, exitstatus")
          # Same query with --quiet should be quiet
          IO.popen("#{RUBY} #{TPKG_EXECUTABLE} #{switch} #{query} --quiet --test-root #{testroot}") do |pipe|
            output = pipe.read
            assert_equal('', output.chomp, "#{switch} #{query} --quiet, installed")
          end
          assert_equal(0, $?.exitstatus, "#{switch} #{query} --quiet, installed, exitstatus")
        end
      end
      # --query allows multiple arguments, test that functionality
      ["#{File.basename(@pkgfile)},#{File.basename(pkgfile2)}", "#{metadata2[:name]},#{metadata[:name]}"].each do |query|
        ['-q', '--query'].each do |switch|
          IO.popen("#{RUBY} #{TPKG_EXECUTABLE} #{switch} #{query} --test-root #{testroot}") do |pipe|
            output = pipe.read
            assert_equal(
              # Output will be sorted
              "#{File.basename(pkgfile2)}\n#{File.basename(@pkgfile)}",
              output.chomp, "#{switch} #{query}, installed")
          end
          assert_equal(0, $?.exitstatus, "#{switch} #{query}, installed, exitstatus")
          # Same query with --quiet should be quiet
          IO.popen("#{RUBY} #{TPKG_EXECUTABLE} #{switch} #{query} --quiet --test-root #{testroot}") do |pipe|
            output = pipe.read
            assert_equal('', output.chomp, "#{switch} #{query} --quiet, installed")
          end
          assert_equal(0, $?.exitstatus, "#{switch} #{query} --quiet, installed, exitstatus")
        end
      end
    end
  end
  def test_qa
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qa --test-root #{testroot}") do |pipe|
        output = pipe.read
        assert_equal('', output, "--qa, not installed")
      end
      assert_equal(0, $?.exitstatus)
      
      # Make up a few more packages to install so we give --qa a fair test. 
      # Use names that will allow us to make sure the package names are output
      # in sorted order.
      pkgfile2 = make_package(:change => {'name' => 'aqapkg'},
                              :remove => ['operatingsystem', 'architecture'],
                              :output_directory => File.join(testroot, 'tmp'))
      pkgfile3 = make_package(:change => {'name' => 'zqapkg'},
                              :remove => ['operatingsystem', 'architecture'],
                              :output_directory => File.join(testroot, 'tmp'))
      
      # Install packages and try again
      tpkg = Tpkg.new(:file_system_root => testroot, :sources => [@pkgfile, pkgfile2, pkgfile3])
      tpkg.install([@pkgfile, pkgfile2, pkgfile3], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qa --test-root #{testroot}") do |pipe|
        output = pipe.read
        pkgshortnames = [pkgfile2, @pkgfile, pkgfile3].collect {|pkg| File.basename(pkg)}
        assert_equal(pkgshortnames.join("\n"), output.chomp, "--qa, installed")
      end
      assert_equal(0, $?.exitstatus)
    end
  end
  def test_qi
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      # Queries for installed packages should return nothing
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qi #{query} --test-root #{testroot}") do |pipe|
          output = pipe.read
          assert_equal("No packages matching '#{query}' installed\n",
            output, "--qi #{query}, not installed")
        end
        assert_equal(1, $?.exitstatus, "--qi #{query}, not installed, exitstatus")
      end
      # But querying a package file should work
      IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qi #{@pkgfile} --test-root #{testroot}") do |pipe|
        output = pipe.read
        [:name, :version, :package_version, :maintainer, :description, :bugreporting].each do |field|
          assert_match(
            /^#{field}: #{metadata[field]}$/,
            output, "--qi #{@pkgfile}, #{field}, not installed")
        end
        [:operatingsystem, :architecture].each do |field|
          assert_match(
            /^#{field}: any$/,
            output, "--qi #{@pkgfile}, #{field}, not installed")
        end
      end
      assert_equal(0, $?.exitstatus, "--qi #{@pkgfile}, not installed, exitstatus")
      
      # Make up more packages to install so we give --qi a fair test.
      pkgfile2 = make_package(
        :change => {
          'name' => 'qipkg',
          # Note spaces between commas here for just a bit of extra testing.
          # See below when we match this out of the --qi output for further
          # explanation
          'operatingsystem' => "RedHat, CentOS, #{Tpkg::get_os}, FreeBSD, Solaris",
          'architecture' => Facter['hardwaremodel'].value},
        :output_directory => File.join(testroot, 'tmp'))
      pkgfile3 = make_package(
        :change => {'name' => 'qidepspkg'},
        :dependencies => {'qipkg' => {}},
        :remove => ['operatingsystem', 'architecture'],
        :output_directory => File.join(testroot, 'tmp'))
      
      # FIXME: test when multiple versions of same package are installed
      
      # Install a package and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile, pkgfile2, pkgfile3])
      tpkg.install([@pkgfile, pkgfile2, pkgfile3], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      metadata2 = Tpkg::metadata_from_package(pkgfile2)
      
      {@pkgfile => metadata, pkgfile2 => metadata2}.each do |pfile, mdata|
        [File.basename(pfile), mdata[:name]].each do |query|
          IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qi #{query} --test-root #{testroot}") do |pipe|
            output = pipe.read
            [:name, :version, :package_version, :maintainer, :description, :bugreporting].each do |field|
              assert_match(/^#{field}: #{mdata[field]}$/, output, "--qi #{query}, #{field}, installed")
            end
            if mdata[:name] == metadata[:name]
              assert_match(/^operatingsystem: any$/, output,
                "--qi #{query}, operatingsystem, installed")
              assert_match(/^architecture: any$/, output,
                "--qi #{query}, architecture, installed")
            else  # qipkg
              # Note that there are no spaces between the commas here, even
              # though we used spaces between the commas when creating the
              # package.  tpkg splits on commas into an array when parsing the
              # metadata, and the tpkg executable joins the array members back
              # together with a comma but no spaces when displaying --qi
              assert_match(/^operatingsystem: RedHat,CentOS,#{Tpkg::get_os},FreeBSD,Solaris$/,
                output, "--qi #{query}, operatingsystem, installed")
              assert_match(/^architecture: #{Facter['hardwaremodel'].value}$/,
                output, "--qi #{query}, architecture, installed")
            end
            assert_no_match(/This package depends on other packages/,
              output, '--qi package without dependencies')
          end
          assert_equal(0, $?.exitstatus, "--qi #{query}, installed, exitstatus")
        end
      end
      IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qi #{File.basename(pkgfile3)} --test-root #{testroot}") do |pipe|
        output = pipe.read
        assert_match(/This package depends on other packages/,
          output, '--qi package with dependencies')
      end
    end
  end
  def test_ql
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      # Queries for installed packages should return nothing
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --ql #{query} --test-root #{testroot}") do |pipe|
          output = pipe.read
          assert_equal("No packages matching '#{query}' installed\n",
            output, "--ql #{query}, not installed")
        end
        assert_equal(1, $?.exitstatus, "--ql #{query}, not installed, exitstatus")
      end
      # But querying a package file should work
      IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --ql #{@pkgfile} --test-root #{testroot}") do |pipe|
        output = pipe.read
        # Output should start with the filename
        assert_match(/\A#{@pkgfile}:$/, output, "--ql #{@pkgfile}, not installed, header")
        # And then the files, one per file
        oldpwd = Dir.pwd
        Dir.chdir(File.join(TESTPKGDIR, 'reloc'))
        Dir.glob('*').each do |testpkgfile|
          assert_match(/^<relocatable>\/#{testpkgfile}$/,
            output, "--ql #{@pkgfile}, #{testpkgfile}, not installed")
        end
        Dir.chdir(oldpwd)
      end
      assert_equal(0, $?.exitstatus, "--ql #{@pkgfile}, not installed, exitstatus")
      
      # FIXME: test when multiple versions of same package are installed
      
      # Install a package and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile])
      tpkg.install([@pkgfile], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --ql #{query} --test-root #{testroot}") do |pipe|
          output = pipe.read
          # Output should start with the package filename
          assert_match(
            /\A#{File.basename(@pkgfile)}:$/,
            output, "--ql #{@pkgfile}, not installed, header")
          # And then the files, one per file
          oldpwd = Dir.pwd
          Dir.chdir(File.join(TESTPKGDIR, 'reloc'))
          Dir.glob('*').each do |testpkgfile|
            assert_match(
              /^#{File.join(testroot, Tpkg::DEFAULT_BASE, testpkgfile)}$/,
              output, "--ql #{@pkgfile}, #{testpkgfile}, not installed")
          end
          Dir.chdir(oldpwd)
        end
        assert_equal(0, $?.exitstatus, "--ql #{query}, installed, exitstatus")
      end
    end
  end
  def test_qf
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qf #{File.join(testroot, Tpkg::DEFAULT_BASE, 'file')} --test-root #{testroot}") do |pipe|
        output = pipe.read
        assert_match(/^No package owns file/,
          output, "--qf, not installed")
      end
      assert_equal(1, $?.exitstatus, "--qf, not installed, exitstatus")
      
      # FIXME: test when multiple versions of same package are installed
      
      # Install a package and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile])
      tpkg.install([@pkgfile], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qf #{File.join(testroot, Tpkg::DEFAULT_BASE, 'file')} --test-root #{testroot}") do |pipe|
        output = pipe.read
        assert_equal("#{File.join(testroot, Tpkg::DEFAULT_BASE, 'file')}: #{File.basename(@pkgfile)}\n", output, "--qf, installed")
      end
      assert_equal(0, $?.exitstatus, "--qf, installed, exitstatus")
    end
  end
  def test_qv
    # FIXME
  end
  def test_qva
    # FIXME
  end
  def test_qr
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qr #{query} --test-root #{testroot}") do |pipe|
          output = pipe.read
          assert_equal(
            "No packages matching '#{query}' installed\n" +
            "No other package depends on '#{query}'\n",
            output, "--qr #{query}, not installed")
        end
        assert_equal(1, $?.exitstatus, "--qr #{query}, not installed, exitstatus")
      end
      
      pkgfile2 = make_package(
        :change => {'name' => 'qrdepspkg'},
        :dependencies => {metadata[:name] => {}},
        :remove => ['operatingsystem', 'architecture'],
        :output_directory => File.join(testroot, 'tmp'))
      metadata2 = Tpkg::metadata_from_package(pkgfile2)
      
      # Install packages and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile, pkgfile2])
      tpkg.install([@pkgfile, pkgfile2], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qr #{query} --test-root #{testroot}") do |pipe|
          output = pipe.read
          assert_equal(
            "The following package(s) require #{File.basename(@pkgfile)}:\n" +
            "  #{File.basename(pkgfile2)}\n",
            output, "--qr #{query}, installed")
        end
        assert_equal(0, $?.exitstatus, "--qr, #{metadata[:name]}, installed, exitstatus")
      end
      [File.basename(pkgfile2), metadata2[:name]].each do |query|
        IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qr #{query} --test-root #{testroot}") do |pipe|
          output = pipe.read
          assert_equal("No other package depends on '#{query}'\n",
            output, "--qr #{query}, installed")
        end
        assert_equal(1, $?.exitstatus, "--qr #{query}, installed, exitstatus")
      end
    end
  end
  def test_qd
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      pkgfile2 = make_package(
        :change => {'name' => 'qdslavepkg'},
        :remove => ['operatingsystem', 'architecture'],
        :output_directory => File.join(testroot, 'tmp'))
      metadata2 = Tpkg::metadata_from_package(pkgfile2)
      pkgfile3 = make_package(
        :change => {'name' => 'qddepspkg'},
        :dependencies => {metadata[:name] => {}, 'qdslavepkg' => {:minimum_version => '1'}},
        :remove => ['operatingsystem', 'architecture'],
        :output_directory => File.join(testroot, 'tmp'))
      metadata3 = Tpkg::metadata_from_package(pkgfile3)
      
      # Query with no package installed
      # Queries for installed packages should return nothing
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qd #{query} --test-root #{testroot}") do |pipe|
          output = pipe.read
          assert_equal("No packages matching '#{query}' installed\n",
            output, "--qd #{query}, not installed")
        end
        assert_equal(1, $?.exitstatus, "--qd #{query}, not installed, exitstatus")
      end
      # But querying a package file should work
      # This package has no dependencies
      IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qd #{@pkgfile} --test-root #{testroot}") do |pipe|
        output = pipe.read
        assert_equal(
          "Package '#{@pkgfile}' does not depend on other packages\n",
          output, "--qd #{@pkgfile}, not installed")
      end
      assert_equal(0, $?.exitstatus, "--qd #{@pkgfile}, not installed, exitstatus")
      # This package has some dependencies
      IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qd #{pkgfile3} --test-root #{testroot}") do |pipe|
        output = pipe.read
        # Output should start with the filename
        assert_equal("Package #{File.basename(pkgfile3)} depends on:\n" +
          "  name: qdslavepkg\n  type: tpkg\n\n" +
          "  name: #{metadata[:name]}\n  type: tpkg\n",
          output, "--qd #{pkgfile3}, not installed")
      end
      assert_equal(0, $?.exitstatus, "--qd #{pkgfile3}, not installed, exitstatus")
      
      # Install packages and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile, pkgfile2, pkgfile3])
      tpkg.install([@pkgfile, pkgfile2, pkgfile3], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qd #{query} --test-root #{testroot}") do |pipe|
          output = pipe.read
          assert_equal(
            "Package '#{query}' does not depend on other packages\n",
            output, "--qd #{query}, installed")
        end
        assert_equal(0, $?.exitstatus, "--qd #{query}, installed, exitstatus")
      end
      [File.basename(pkgfile3), metadata3[:name]].each do |query|
        IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qd #{query} --test-root #{testroot}") do |pipe|
          output = pipe.read
          assert_equal("Package #{File.basename(pkgfile3)} depends on:\n" +
            "  name: qdslavepkg\n  type: tpkg\n\n" +
            "  name: #{metadata[:name]}\n  type: tpkg\n",
            output, "--qd #{query}, installed")
        end
        assert_equal(0, $?.exitstatus, "--qd #{query}, installed, exitstatus")
      end
    end
  end
  # def test_qld
  # end
  def test_qX
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      # Queries for installed packages should return nothing
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qX #{query} --test-root #{testroot}") do |pipe|
          output = pipe.read
          assert_equal("No packages matching '#{query}' installed\n",
            output, "--qX #{query}, not installed")
        end
        assert_equal(1, $?.exitstatus, "--qX #{query}, not installed, exitstatus")
      end
      # But querying a package file should work
      IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qX #{@pkgfile} --test-root #{testroot}") do |pipe|
        output = pipe.read
        assert_equal(metadata.text, output, "--qX #{@pkgfile}, not installed")
      end
      assert_equal(0, $?.exitstatus, "--qX #{@pkgfile}, not installed, exitstatus")
      
      # Install package and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile])
      tpkg.install([@pkgfile], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        IO.popen("#{RUBY} #{TPKG_EXECUTABLE} --qX #{query} --test-root #{testroot}") do |pipe|
          output = pipe.read
          assert_equal(
            metadata.text,
            output, "--qX #{query}, installed")
        end
        assert_equal(0, $?.exitstatus, "--qX #{query}, installed, exitstatus")
      end
    end
  end
  
  def test_qenv
    output = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    IO.popen("#{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --qenv") do |pipe|
      output = pipe.readlines
    end
    # Make sure the expected lines are there
    assert(output.any? {|line| line.include?('Operating System:')})
    assert(output.any? {|line| line.include?('Architecture:')})
  end
  
  def test_qconf
    output = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    IO.popen("#{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --qconf") do |pipe|
      output = pipe.readlines
    end
    # Make sure the expected lines are there
    assert(output.any? {|line| line.include?('Base:')})
    assert(output.any? {|line| line.include?('Sources:')})
    assert(output.any? {|line| line.include?('Report server:')})
  end
  
  def test_use_ssh_key
    # Test --use-ssh-key with argument
    error = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    Open3.popen3("#{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} -s shell.sourceforge.net --use-ssh-key no_such_file --no-sudo --version") do |stdin, stdout, stderr|
      stdin.close
      error = stderr.readlines
    end
    # Make sure the expected lines are there
    assert(error.any? {|line| line.include?('Unable to read ssh key from no_such_file')})
    
    # Test --use-ssh-key without argument
    output = nil
    error = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    Open3.popen3("#{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} -s shell.sourceforge.net --use-ssh-key --version") do |stdin, stdout, stderr|
      stdin.close
      output = stdout.readlines
      error = stderr.readlines
    end
    # Make sure that tpkg didn't prompt for a password
    assert(!output.any? {|line| line.include?('SSH Password (leave blank if using ssh key):')})
    
    # Just to make sure our previous test is valid, check that we are prompted
    # for a password if we don't specify --use-ssh-key
    output = nil
    error = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    Open3.popen3("#{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} -s shell.sourceforge.net --version") do |stdin, stdout, stderr|
      stdin.close
      output = stdout.readlines
      error = stderr.readlines
    end
    # Make sure that tpkg did prompt for a password this time
    assert(output.any? {|line| line.include?('SSH Password (leave blank if using ssh key):')})
  end
  
  def test_base
    # Test the --base option
    output = nil
    Dir.mktmpdir('clibase') do |clibase|
      # The File.join(blah) is roughly equivalent to '../bin/tpkg'
      parentdir = File.dirname(File.dirname(__FILE__))
      IO.popen("#{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --base #{clibase} --qconf") do |pipe|
        output = pipe.readlines
      end
      # Make sure the expected line is there
      baseline = output.find {|line| line.include?('Base: ')}
      assert_equal("Base: #{clibase}\n", baseline)
    end
  end
    
  def test_base_precedence
    # Test precedence of various methods of setting base directory
    
    # TPKG_HOME ends up set in our environment due to use of the tpkg library
    ENV.delete('TPKG_HOME')
    
    FileUtils.mkdir_p(File.join(@testroot, Tpkg::DEFAULT_CONFIGDIR))
    File.open(File.join(@testroot, Tpkg::DEFAULT_CONFIGDIR, 'tpkg.conf'), 'w') do |file|
      file.puts "base = /confbase"
    end
    
    output = nil
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    # --base, TPKG_HOME and config file all set
    IO.popen("env TPKG_HOME=/envbase #{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --base /clibase --test-root #{@testroot} --qconf") do |pipe|
      output = pipe.readlines
    end
    # Make sure the expected line is there
    baseline = output.find {|line| line.include?('Base: ')}
    assert_equal("Base: #{File.join(@testroot, 'clibase')}\n", baseline)
    
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    # TPKG_HOME and config file all set
    IO.popen("env TPKG_HOME=/envbase #{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --test-root #{@testroot} --qconf") do |pipe|
      output = pipe.readlines
    end
    # Make sure the expected line is there
    baseline = output.find {|line| line.include?('Base: ')}
    assert_equal("Base: #{File.join(@testroot, 'envbase')}\n", baseline)
    
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    # Only config file set
    IO.popen("#{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --test-root #{@testroot} --qconf") do |pipe|
      output = pipe.readlines
    end
    # Make sure the expected line is there
    baseline = output.find {|line| line.include?('Base: ')}
    assert_equal("Base: #{File.join(@testroot, 'confbase')}\n", baseline)
    
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    # Nothing is set
    File.delete(File.join(@testroot, Tpkg::DEFAULT_CONFIGDIR, 'tpkg.conf'))
    IO.popen("#{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --test-root #{@testroot} --qconf") do |pipe|
      output = pipe.readlines
    end
    # Make sure the expected line is there
    baseline = output.find {|line| line.include?('Base: ')}
    assert_equal("Base: #{File.join(@testroot, Tpkg::DEFAULT_BASE)}\n", baseline)
  end
  
  def test_test_root
    # Test the --test-root option
    output = nil
    
    # With --test-root the base directory will be /<testroot>/opt/tpkg
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    IO.popen("#{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --test-root #{@testroot} --qconf") do |pipe|
      output = pipe.readlines
    end
    # Make sure the expected line is there
    baseline = output.find {|line| line.include?('Base: ')}
    assert_equal("Base: #{File.join(@testroot, Tpkg::DEFAULT_BASE)}\n", baseline)
    
    # Without --test-root the base directory will be something else (depending
    # on what config files are on the system)
    # The File.join(blah) is roughly equivalent to '../bin/tpkg'
    parentdir = File.dirname(File.dirname(__FILE__))
    IO.popen("#{RUBY} -I #{File.join(parentdir, 'lib')} #{File.join(parentdir, 'bin', 'tpkg')} --qconf") do |pipe|
      output = pipe.readlines
    end
    # This is a rather lame test, but we don't have any way to know how tpkg
    # is configured on the system on which the tests are running.
    baseline = output.find {|line| line.include?('Base: ')}
    assert_not_equal("Base: #{File.join(@testroot, Tpkg::DEFAULT_BASE)}\n", baseline)
  end
  
  def test_compress
    Dir.mktmpdir('pkgdir') do |pkgdir|
      FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(pkgdir, 'tpkg.xml'))
      
      parentdir = File.dirname(File.dirname(__FILE__))
      
      # The argument to the --compress switch should be optional
      Dir.mktmpdir('outdir') do |outdir|
        system("#{RUBY} #{File.join(parentdir, 'bin', 'tpkg')} --compress --make #{pkgdir} --out #{outdir}")
        pkgfile = Dir.glob(File.join(outdir, '*.tpkg')).first
        assert(['bz2', 'gzip'].include?(Tpkg::get_compression(pkgfile)))
      end
      
      Dir.mktmpdir('outdir') do |outdir|
        system("#{RUBY} #{File.join(parentdir, 'bin', 'tpkg')} --compress gzip --make #{pkgdir} --out #{outdir}")
        pkgfile = Dir.glob(File.join(outdir, '*.tpkg')).first
        assert_equal('gzip', Tpkg::get_compression(pkgfile))
      end
      
      Dir.mktmpdir('outdir') do |outdir|
        system("#{RUBY} #{File.join(parentdir, 'bin', 'tpkg')} --compress bz2 --make #{pkgdir} --out #{outdir}")
        pkgfile = Dir.glob(File.join(outdir, '*.tpkg')).first
        assert_equal('bz2', Tpkg::get_compression(pkgfile))
      end
      
      # Invalid argument rejected
      Dir.mktmpdir('outdir') do |outdir|
        system("#{RUBY} #{File.join(parentdir, 'bin', 'tpkg')} --compress bogus --make #{pkgdir} --out #{outdir}")
        # tpkg should have bailed with an error
        assert_not_equal(0, $?.exitstatus)
        # And not created anything in the output directory
        assert(2, Dir.entries(outdir).length)
      end
    end
  end
  
  def teardown
    FileUtils.rm_rf(@testroot)
  end
end

