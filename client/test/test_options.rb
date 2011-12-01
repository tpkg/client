#
# Test tpkg command line options
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))
require 'rubygems'
require 'open4'
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
          status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} #{switch} #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
            stdin.close
            assert_equal(
              "", stdout.read, "#{switch} #{query}, not installed, stdout")
            assert_equal(
              "No packages matching '#{query}' installed\n", stderr.read,
              "#{switch} #{query}, not installed, stderr")
          end
          assert_equal(1, status.exitstatus, "#{switch} #{query}, not installed, exitstatus")
          # Same query with --quiet should be quiet
          status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} #{switch} #{query} --quiet --test-root #{testroot}") do |pid, stdin, stdout, stderr|
            stdin.close
            assert_equal("", stdout.read, "#{switch} #{query} --quiet, not installed, stdout")
            assert_equal("", stderr.read, "#{switch} #{query} --quiet, not installed, stderr")
          end
          assert_equal(1, status.exitstatus, "#{switch} #{query} --quiet, not installed, exitstatus")
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
          status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} #{switch} #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
            stdin.close
            assert_equal("#{File.basename(@pkgfile)}\n", stdout.read, "#{switch} #{query}, installed, stdout")
            assert_equal("", stderr.read, "#{switch} #{query}, installed, stderr")
          end
          assert_equal(0, status.exitstatus, "#{switch} #{query}, installed, exitstatus")
          # Same query with --quiet should be quiet
          status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} #{switch} #{query} --quiet --test-root #{testroot}") do |pid, stdin, stdout, stderr|
            stdin.close
            assert_equal('', stdout.read, "#{switch} #{query} --quiet, installed, stdout")
            assert_equal('', stderr.read, "#{switch} #{query} --quiet, installed, stderr")
          end
          assert_equal(0, status.exitstatus, "#{switch} #{query} --quiet, installed, exitstatus")
        end
      end
      # --query allows multiple arguments, test that functionality
      ["#{File.basename(@pkgfile)},#{File.basename(pkgfile2)}", "#{metadata2[:name]},#{metadata[:name]}"].each do |query|
        ['-q', '--query'].each do |switch|
          status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} #{switch} #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
            stdin.close
            assert_equal(
              # Output will be sorted
              "#{File.basename(pkgfile2)}\n#{File.basename(@pkgfile)}\n",
              stdout.read, "#{switch} #{query}, installed, stdout")
            assert_equal(
              "", stderr.read, "#{switch} #{query}, installed, stderr")
          end
          assert_equal(0, status.exitstatus, "#{switch} #{query}, installed, exitstatus")
          # Same query with --quiet should be quiet
          status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} #{switch} #{query} --quiet --test-root #{testroot}") do |pid, stdin, stdout, stderr|
            stdin.close
            assert_equal('', stdout.read, "#{switch} #{query} --quiet, installed, stdout")
            assert_equal('', stderr.read, "#{switch} #{query} --quiet, installed, stderr")
          end
          assert_equal(0, status.exitstatus, "#{switch} #{query} --quiet, installed, exitstatus")
        end
      end
    end
  end
  def test_qa
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qa --test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal("", stdout.read, "--qa, not installed, stdout")
        assert_equal("No packages installed\n", stderr.read, "--qa, not installed, stderr")
      end
      assert_equal(1, status.exitstatus)
      
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
      
      status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qa --test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        pkgshortnames = [pkgfile2, @pkgfile, pkgfile3].collect {|pkg| File.basename(pkg)}
        assert_equal(pkgshortnames.join("\n")+"\n", stdout.read, "--qa, installed, stdout")
        assert_equal('', stderr.read, "--qa, installed, stderr")
      end
      assert_equal(0, status.exitstatus)
    end
  end
  def test_qi
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      # Queries for installed packages should return nothing
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qi #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "", stdout.read, "--qi #{query}, not installed, stdout")
          assert_equal("No packages matching '#{query}' installed\n",
            stderr.read, "--qi #{query}, not installed, stderr")
        end
        assert_equal(1, status.exitstatus, "--qi #{query}, not installed, exitstatus")
      end
      # But querying a package file should work
      status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qi #{@pkgfile} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        output = stdout.read
        [:name, :version, :package_version, :maintainer, :description, :bugreporting].each do |field|
          assert_match(
            /^#{field}: #{metadata[field]}$/,
            output, "--qi #{@pkgfile}, #{field}, not installed, stdout")
        end
        [:operatingsystem, :architecture].each do |field|
          assert_match(
            /^#{field}: any$/,
            output, "--qi #{@pkgfile}, #{field}, not installed, stdout")
        end
        assert_equal("", stderr.read, "--qi #{@pkgfile}, not installed, stderr")
      end
      assert_equal(0, status.exitstatus, "--qi #{@pkgfile}, not installed, exitstatus")
      
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
      
      # Install packages and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile, pkgfile2, pkgfile3])
      tpkg.install([@pkgfile, pkgfile2, pkgfile3], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      metadata2 = Tpkg::metadata_from_package(pkgfile2)
      
      {@pkgfile => metadata, pkgfile2 => metadata2}.each do |pfile, mdata|
        [File.basename(pfile), mdata[:name]].each do |query|
          status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qi #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
            stdin.close
            output = stdout.read
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
            assert_equal("", stderr.read, "--qi package without dependencies, stderr")
          end
          assert_equal(0, status.exitstatus, "--qi #{query}, installed, exitstatus")
        end
      end
      status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qi #{File.basename(pkgfile3)} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_match(/This package depends on other packages/,
          stdout.read, '--qi package with dependencies')
        assert_equal("", stderr.read, "--qi package with dependencies, stderr")
      end
    end
  end
  def test_qis
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      # Make up more packages to install so we give --qis a fair test.
      pkgfile2 = make_package(
        :change => {
          'name' => 'qispkg',
          # Note spaces between commas here for just a bit of extra testing.
          # See below when we match this out of the --qis output for further
          # explanation
          'operatingsystem' => "RedHat, CentOS, #{Tpkg::get_os}, FreeBSD, Solaris",
          'architecture' => Facter['hardwaremodel'].value},
        :output_directory => File.join(testroot, 'tmp'))
      metadata2 = Tpkg::metadata_from_package(pkgfile2)
      pkgfile3 = make_package(
        :change => {'name' => 'qisdepspkg'},
        :dependencies => {'qispkg' => {}},
        :remove => ['operatingsystem', 'architecture'],
        :output_directory => File.join(testroot, 'tmp'))
      metadata3 = Tpkg::metadata_from_package(pkgfile3)
      
      # Query a package that is not available, should get nothing
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qis #{query} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "", stdout.read,
            "--qis #{query}, not available or installed, stdout")
          assert_equal(
            "No packages matching '#{query}' available\n", stderr.read,
            "--qis #{query}, not available or installed, stderr")
        end
        assert_equal(
          1, status.exitstatus,
          "--qis #{query}, not available or installed, exitstatus")
      end
      
      # Query packages that are available but not installed, should get data
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qis #{query} " +
          "--source #{[@pkgfile,pkgfile2,pkgfile3].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          output = stdout.read
          [:name, :version, :package_version,
           :maintainer, :description, :bugreporting].each do |field|
            assert_match(
              /^#{field}: #{metadata[field]}$/, output,
              "--qis #{query}, #{field}, available, not installed, stdout")
          end
          [:operatingsystem, :architecture].each do |field|
            assert_match(
              /^#{field}: any$/, output,
              "--qis #{query}, #{field}, available, not installed, stdout")
          end
          assert_equal(
            "", stderr.read,
            "--qis #{query}, available, not installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qis #{query}, available, not installed, exitstatus")
      end
      {@pkgfile => metadata, pkgfile2 => metadata2}.each do |pfile, mdata|
        [File.basename(pfile), mdata[:name]].each do |query|
          status = Open4.popen4(
            "#{RUBY} #{TPKG_EXECUTABLE} --qis #{query} " +
            "--source #{[@pkgfile,pkgfile2,pkgfile3].join(',')} " +
            "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
            stdin.close
            output = stdout.read
            [:name, :version, :package_version,
             :maintainer, :description, :bugreporting].each do |field|
              assert_match(
                /^#{field}: #{mdata[field]}$/, output,
                "--qis #{query}, #{field}, available, not installed")
            end
            if mdata[:name] == metadata[:name]
              assert_match(/^operatingsystem: any$/, output,
                "--qis #{query}, operatingsystem, available, not installed")
              assert_match(/^architecture: any$/, output,
                "--qis #{query}, architecture, available, not installed")
            else  # qispkg
              # Note that there are no spaces between the commas here, even
              # though we used spaces between the commas when creating the
              # package.  tpkg splits on commas into an array when parsing the
              # metadata, and the tpkg executable joins the array members back
              # together with a comma but no spaces when displaying --qi
              assert_match(
                /^operatingsystem: RedHat,CentOS,#{Tpkg::get_os},FreeBSD,Solaris$/,
                output, "--qis #{query}, operatingsystem, installed")
              assert_match(
                /^architecture: #{Facter['hardwaremodel'].value}$/,
                output, "--qis #{query}, architecture, installed")
            end
            assert_no_match(
              /This package depends on other packages/, output,
              '--qis package without dependencies')
            assert_equal(
              "", stderr.read,
              "--qis package without dependencies, stderr")
          end
          assert_equal(
            0, status.exitstatus,
            "--qis #{query}, available, not installed, exitstatus")
        end
      end
      status = Open4.popen4(
        "#{RUBY} #{TPKG_EXECUTABLE} --qis #{File.basename(pkgfile3)} " +
        "--source #{[@pkgfile,pkgfile2,pkgfile3].join(',')} " +
        "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_match(
          /This package depends on other packages/, stdout.read,
          '--qis package with dependencies')
        assert_equal(
          "", stderr.read,
          "--qis package with dependencies, stderr")
      end
      
      # Install packages and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile, pkgfile2, pkgfile3])
      tpkg.install([@pkgfile, pkgfile2, pkgfile3], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg
      # library
      ENV.delete('TPKG_HOME')
      
      # Query a package that is installed but not available, should get
      # nothing
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qis #{query} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "", stdout.read,
            "--qis #{query}, installed, not available, stdout")
          assert_equal(
            "No packages matching '#{query}' available\n", stderr.read,
            "--qis #{query}, installed, not available, stderr")
        end
        assert_equal(
          1, status.exitstatus,
          "--qis #{query}, installed, not available, exitstatus")
      end
      
      # Query a package that is installed and available, should get the data
      # for the available package
      # pkgfile2 and pkgfile4 have the same name but other differences
      pkgfile4 = make_package(
        :change => {
          'name' => 'qispkg',
          'version' => '42',
          # Note spaces between commas here for just a bit of extra testing.
          # See below when we match this out of the --qis output for further
          # explanation
          'operatingsystem' => "RedHat, CentOS, #{Tpkg::get_os}",
          'architecture' => "#{Facter['hardwaremodel'].value}, bogusarch"},
        :output_directory => File.join(testroot, 'tmp'))
      metadata4 = Tpkg::metadata_from_package(pkgfile4)
      [metadata2[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qis #{query} " +
          "--source #{[@pkgfile,pkgfile3,pkgfile4].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          output = stdout.read
          assert_match(
            /^version: #{metadata4['version']}$/, output,
            "--qis #{query}, version, available and installed, stdout")
          assert_match(
            /^operatingsystem: RedHat,CentOS,#{Tpkg::get_os}$/,
            output,
            "--qis #{query}, operatingsystem, available and installed, stdout")
          assert_match(
            /^architecture: #{Facter['hardwaremodel'].value},bogusarch$/,
            output,
            "--qis #{query}, architecture, available and installed, stdout")
          assert_equal(
            "", stderr.read,
            "--qis #{query}, available and installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qis #{query}, available and installed, exitstatus")
      end
    end
  end
  def test_ql
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      # Queries for installed packages should return nothing
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --ql #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "", stdout.read, "--ql #{query}, not installed, stdout")
          assert_equal("No packages matching '#{query}' installed\n",
            stderr.read, "--ql #{query}, not installed, stderr")
        end
        assert_equal(1, status.exitstatus, "--ql #{query}, not installed, exitstatus")
      end
      # But querying a package file should work
      status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --ql #{@pkgfile} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        output = stdout.read
        # Output should start with the filename
        assert_match(/\A#{@pkgfile}:$/, output, "--ql #{@pkgfile}, not installed, header")
        # And then the files, one per file
        oldpwd = Dir.pwd
        Dir.chdir(File.join(TESTPKGDIR, 'reloc'))
        Dir.glob('*').each do |testpkgfile|
          assert_match(/^<relocatable>\/#{testpkgfile}$/,
            output, "--ql #{@pkgfile}, #{testpkgfile}, not installed")
        end
        assert_equal("", stderr.read, "--ql #{@pkgfile}, not installed, stderr")
        Dir.chdir(oldpwd)
      end
      assert_equal(0, status.exitstatus, "--ql #{@pkgfile}, not installed, exitstatus")
      
      # FIXME: test when multiple versions of same package are installed
      
      # Install a package and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile])
      tpkg.install([@pkgfile], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --ql #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          output = stdout.read
          # Output should start with the package filename
          assert_match(
            /\A#{File.basename(@pkgfile)}:$/,
            output, "--ql #{@pkgfile}, installed, header")
          # And then the files, one per file
          oldpwd = Dir.pwd
          Dir.chdir(File.join(TESTPKGDIR, 'reloc'))
          Dir.glob('*').each do |testpkgfile|
            assert_match(
              /^#{File.join(testroot, Tpkg::DEFAULT_BASE, testpkgfile)}$/,
              output, "--ql #{@pkgfile}, #{testpkgfile}, installed")
          end
          assert_equal("", stderr.read, "--ql #{@pkgfile}, installed, stderr")
          Dir.chdir(oldpwd)
        end
        assert_equal(0, status.exitstatus, "--ql #{query}, installed, exitstatus")
      end
    end
  end
  def test_qls
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      pkgfile2 = make_package(
        :change => {'name' => 'qlspkg'},
        :remove => ['operatingsystem', 'architecture'],
        :output_directory => File.join(testroot, 'tmp'))
      metadata2 = Tpkg::metadata_from_package(pkgfile2)
      
      # Query a package that is not available, should get nothing
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qls #{query} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "", stdout.read,
            "--qls #{query}, not available or installed, stdout")
          assert_equal(
            "No packages matching '#{query}' available\n", stderr.read,
            "--qls #{query}, not available or installed, stderr")
        end
        assert_equal(
          1, status.exitstatus,
          "--qls #{query}, not available or installed, exitstatus")
      end
      
      # Query package that is available but not installed, should get data
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qls #{query} " +
          "--source #{[@pkgfile,pkgfile2].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          output = stdout.read
          # Output should start with the filename
          assert_match(/\A#{File.basename(@pkgfile)}:$/, output, "--qls #{@pkgfile}, available, not installed, header")
          # And then the files, one per file
          oldpwd = Dir.pwd
          Dir.chdir(File.join(TESTPKGDIR, 'reloc'))
          Dir.glob('*').each do |testpkgfile|
            assert_match(/^<relocatable>\/#{testpkgfile}$/,
              output, "--qls #{@pkgfile}, #{testpkgfile}, available, not installed")
          end
          Dir.chdir(oldpwd)
          assert_equal(
            "", stderr.read,
            "--qls #{query}, available, not installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qls #{query}, available, not installed, exitstatus")
      end
      
      # Install packages and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile, pkgfile2])
      tpkg.install([@pkgfile, pkgfile2], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg
      # library
      ENV.delete('TPKG_HOME')
      
      # Query a package that is installed but not available, should get
      # nothing
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qls #{query} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "", stdout.read,
            "--qls #{query}, installed, not available, stdout")
          assert_equal(
            "No packages matching '#{query}' available\n", stderr.read,
            "--qls #{query}, installed, not available, stderr")
        end
        assert_equal(
          1, status.exitstatus,
          "--qls #{query}, installed, not available, exitstatus")
      end
      
      # Query a package that is installed and available, should get the data
      # for the available package
      # pkgfile2 and pkgfile4 have the same name but other differences
      pkgfile4 = nil
      Dir.mktmpdir('pkg4') do |pkg4src|
        FileUtils.cp(File.join(TESTPKGDIR, 'tpkg-nofiles.xml'), File.join(pkg4src, 'tpkg.xml'))
        Dir.mkdir(File.join(pkg4src, 'reloc'))
        File.open(File.join(pkg4src, 'reloc', 'pkg4file'), 'w') {}
        pkgfile4 = make_package(
          :change => {
            'name' => 'qlspkg',
            'version' => '42'},
          :remove => ['operatingsystem', 'architecture'],
          :source_directory => pkg4src,
          :output_directory => File.join(testroot, 'tmp'))
      end
      metadata4 = Tpkg::metadata_from_package(pkgfile4)
      [metadata2[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qls #{query} " +
          "--source #{[@pkgfile,pkgfile4].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          output = stdout.read
          assert_equal(
            "#{File.basename(pkgfile4)}:\n<relocatable>/pkg4file\n", output,
            "--qls #{query}, available and installed, stdout")
          assert_equal(
            "", stderr.read,
            "--qls #{query}, available and installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qls #{query}, available and installed, exitstatus")
      end
    end
  end
  def test_qf
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      queryfile = File.join(testroot, Tpkg::DEFAULT_BASE, 'file')
      status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qf #{queryfile} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal("", stdout.read, "--qf, not installed, stdout")
        assert_equal("No package owns file '#{queryfile}'\n",
          stderr.read, "--qf, not installed, stderr")
      end
      assert_equal(1, status.exitstatus, "--qf, not installed, exitstatus")
      
      # FIXME: test when multiple versions of same package are installed
      
      # Install a package and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile])
      tpkg.install([@pkgfile], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qf #{queryfile} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal("#{queryfile}: #{File.basename(@pkgfile)}\n", stdout.read, "--qf, installed, stdout")
        assert_equal("", stderr.read, "--qf, installed, stderr")
      end
      assert_equal(0, status.exitstatus, "--qf, installed, exitstatus")
    end
  end
  # I've shelved the --qfs option for now because we don't currently keep a
  # record of the files in the packages on the server.  I.e. metadata.yml
  # doesn't have a complete list of files.  So implementing --qfs today would
  # require downloading all of the packages.
  # def test_qfs
  #   # FIXME: ways to improve this:
  #   # - Multiple packages available with the queried file
  #   # - Some available packages don't contain the queried file (need to make a package with no files)
  #   # - For the "Installed and available" case make the installed and available packages different to make sure that we're getting the data for the available package instead of the installed package
  #   
  #   Dir.mktmpdir('testroot') do |testroot|
  #     # Neither available nor installed
  #     queryfile = File.join(testroot, Tpkg::DEFAULT_BASE, 'file')
  #     status = Open4.popen4(
  #       "#{RUBY} #{TPKG_EXECUTABLE} --qfs #{queryfile} " +
  #       "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
  #       stdin.close
  #       assert_equal(
  #         "", stdout.read, "--qfs, not available, not installed, stdout")
  #       assert_equal("No package on server owns file '#{queryfile}'\n",
  #         stderr.read, "--qfs, not available, not installed, stderr")
  #     end
  #     assert_equal(
  #       1, status.exitstatus,
  #       "--qfs, not available, not installed, exitstatus")
  #     
  #     # Available but not installed
  #     status = Open4.popen4(
  #       "#{RUBY} #{TPKG_EXECUTABLE} --qfs #{queryfile} " +
  #       "--source #{@pkgfile} " +
  #       "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
  #       stdin.close
  #       assert_equal(
  #         "#{queryfile}: #{File.basename(@pkgfile)}\n", stdout.read,
  #         "--qfs, available, not installed, stdout")
  #       assert_equal(
  #         "", stderr.read, "--qfs, available, not installed, stderr")
  #     end
  #     assert_equal(
  #       0, status.exitstatus, "--qfs, available, not installed, exitstatus")
  #     
  #     # Install a package and try again
  #     tpkg = Tpkg.new(
  #       :file_system_root => testroot,
  #       :sources => [@pkgfile])
  #     tpkg.install([@pkgfile], PASSPHRASE)
  #     
  #     # TPKG_HOME ends up set in our environment due to use of the tpkg library
  #     ENV.delete('TPKG_HOME')
  #     
  #     # Installed and available
  #     status = Open4.popen4(
  #       "#{RUBY} #{TPKG_EXECUTABLE} --qfs #{queryfile} " +
  #       "--source #{@pkgfile} " +
  #       "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
  #       stdin.close
  #       assert_equal(
  #         "#{queryfile}: #{File.basename(@pkgfile)}\n", stdout.read,
  #         "--qfs, installed and available, stdout")
  #       assert_equal(
  #         "", stderr.read, "--qfs, installed and available, stderr")
  #     end
  #     assert_equal(0, status.exitstatus, "--qfs, installed, exitstatus")
  #     
  #     # Installed but not available
  #     queryfile = File.join(testroot, Tpkg::DEFAULT_BASE, 'file')
  #     status = Open4.popen4(
  #       "#{RUBY} #{TPKG_EXECUTABLE} --qfs #{queryfile} " +
  #       "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
  #       stdin.close
  #       assert_equal(
  #         "", stdout.read, "--qfs, not available, installed, stdout")
  #       assert_equal("No package on server owns file '#{queryfile}'\n",
  #         stderr.read, "--qfs, not available, installed, stderr")
  #     end
  #     assert_equal(
  #       1, status.exitstatus,
  #       "--qfs, not available, installed, exitstatus")
  #   end
  # end
  def test_qs
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      pkgfile2 = make_package(:change => {'name' => 'qvpkg'},
                              :remove => ['operatingsystem', 'architecture'],
                              :output_directory => File.join(testroot, 'tmp'))
      metadata2 = Tpkg::metadata_from_package(pkgfile2)
      
      # Query with no package installed
      # Query for an available package
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qs #{query} " +
          "--source #{[@pkgfile,pkgfile2].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "#{File.basename(@pkgfile)} (#{@pkgfile})\n", stdout.read,
            "--qs #{query}, not installed, stdout")
          assert_equal(
            '', stderr.read,
            "--qs #{query}, not installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qs #{query}, not installed, exitstatus")
        # Same query with --quiet should be quiet
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qs #{query} " +
          "--source #{[@pkgfile,pkgfile2].join(',')} " +
          "--quiet --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            '', stdout.read,
            "--qs #{query} --quiet, not installed, stdout")
            assert_equal(
              '', stderr.read,
              "--qs #{query} --quiet, not installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qs #{query} --quiet, not installed, exitstatus")
      end
      # Query for an unavailable package
      ['bogus-1.0-1.tpkg', 'bogus'].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qs #{query} " +
          "--source #{[@pkgfile,pkgfile2].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            '', stdout.read,
            "--qs #{query}, not installed, stdout")
          assert_equal(
            "No packages matching '#{query}' available\n",
            stderr.read, "--qs #{query}, not installed, stderr")
        end
        assert_equal(1, status.exitstatus, "--qs #{query}, not installed, exitstatus")
        # Same query with --quiet should be quiet
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qs #{query} " +
          "--source #{[@pkgfile,pkgfile2].join(',')} " +
          "--quiet --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            '', stdout.read,
            "--qs #{query} --quiet, not installed, stdout")
          assert_equal(
            '', stderr.read,
            "--qs #{query} --quiet, not installed, stderr")
        end
        assert_equal(
          1, status.exitstatus,
          "--qs #{query} --quiet, not installed, exitstatus")
      end
      
      # Install package and try again
      tpkg = Tpkg.new(:file_system_root => testroot, :sources => [@pkgfile])
      tpkg.install([@pkgfile], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      # Query package that's installed (should still be available)
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qs #{query} " +
          "--source #{[@pkgfile,pkgfile2].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "#{File.basename(@pkgfile)} (#{@pkgfile})\n", stdout.read,
            "--qs #{query}, installed, stdout")
          assert_equal(
            '', stderr.read,
            "--qs #{query}, installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qs #{query}, installed, exitstatus")
        # Same query with --quiet should be quiet
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qs #{query} " +
          "--source #{[@pkgfile,pkgfile2].join(',')} " +
          "--quiet --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            '', stdout.read,
            "--qs #{query} --quiet, installed, stdout")
            assert_equal(
              '', stderr.read,
              "--qs #{query} --quiet, installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qs #{query} --quiet, installed, exitstatus")
      end
      
      # Query package that's available but not installed
      [File.basename(pkgfile2), metadata2[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qs #{query} " +
          "--source #{[@pkgfile,pkgfile2].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "#{File.basename(pkgfile2)} (#{pkgfile2})\n",
            stdout.read, "--qs #{query}, installed, stdout")
          assert_equal(
            '',
            stderr.read, "--qs #{query}, installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qs #{query}, installed, exitstatus")
        # Same query with --quiet should be quiet
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qs #{query} " +
          "--source #{[@pkgfile,pkgfile2].join(',')} " +
          "--quiet --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            '', stdout.read,
            "--qs #{query} --quiet, installed, stdout")
          assert_equal(
            '', stderr.read,
            "--qs #{query} --quiet, installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qs #{query} --quiet, installed, exitstatus")
      end
      
      # Query package that's installed but no longer available
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qs #{query} " +
          "--source #{[pkgfile2].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            '', stdout.read,
            "--qs #{query}, installed but not available, stdout")
          assert_equal(
            "No packages matching '#{query}' available\n", stderr.read,
            "--qs #{query}, installed but not available, stderr")
        end
        assert_equal(
          1, status.exitstatus,
          "--qs #{query}, installed but not available, exitstatus")
        # Same query with --quiet should be quiet
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qs #{query} " +
          "--source #{[pkgfile2].join(',')} " +
          "--quiet --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            '', stdout.read,
            "--qs #{query} --quiet, installed but not available, stdout")
          assert_equal(
            '', stderr.read,
            "--qs #{query} --quiet, installed but not available, stderr")
        end
        assert_equal(
          1, status.exitstatus,
          "--qs #{query} --quiet, installed but not available, exitstatus")
      end
    end
  end
  def test_qas
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      # Names chosen so as to test sorting of output
      pkgfile2 = make_package(:change => {'name' => 'aqvapkg'},
                              :remove => ['operatingsystem', 'architecture'],
                              :output_directory => File.join(testroot, 'tmp'))
      metadata2 = Tpkg::metadata_from_package(pkgfile2)
      pkgfile3 = make_package(:change => {'name' => 'zqvapkg'},
                              :remove => ['operatingsystem', 'architecture'],
                              :output_directory => File.join(testroot, 'tmp'))
      metadata3 = Tpkg::metadata_from_package(pkgfile3)
      
      # Query with no package installed or available
      status = Open4.popen4(
        "#{RUBY} #{TPKG_EXECUTABLE} --qas " +
        "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal(
          '', stdout.read, "--qas, not installed or available, stdout")
        assert_equal(
          "No packages available\n", stderr.read,
          "--qas, not installed or available, stderr")
      end
      assert_equal(
        1, status.exitstatus,
        "--qas, not installed or available, exitstatus")
      # Same query with --quiet should be quiet
      status = Open4.popen4(
        "#{RUBY} #{TPKG_EXECUTABLE} --qas --quiet " +
        "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal(
          '', stdout.read,
          "--qas --quiet, not installed or available, stdout")
        assert_equal(
          '', stderr.read,
          "--qas --quiet, not installed or available, stderr")
      end
      assert_equal(
        1, status.exitstatus,
        "--qas --quiet, not installed or available, exitstatus")
      
      # Query with no package installed
      status = Open4.popen4(
        "#{RUBY} #{TPKG_EXECUTABLE} --qas " +
        "--source #{[@pkgfile,pkgfile2,pkgfile3].join(',')} " +
        "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal(
          [pkgfile2, @pkgfile, pkgfile3].collect {|p| "#{File.basename(p)} (#{p})"}.join("\n") + "\n",
          stdout.read, "--qas, not installed, stdout")
        assert_equal('', stderr.read, "--qas, not installed, stderr")
      end
      assert_equal(0, status.exitstatus, "--qas, not installed, exitstatus")
      # Same query with --quiet should be quiet
      status = Open4.popen4(
        "#{RUBY} #{TPKG_EXECUTABLE} --qas " +
        "--source #{[@pkgfile,pkgfile2,pkgfile3].join(',')} " +
        "--quiet --test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal('', stdout.read, "--qas --quiet, not installed, stdout")
        assert_equal('', stderr.read, "--qas --quiet, not installed, stderr")
      end
      assert_equal(
        0, status.exitstatus, "--qas --quiet, not installed, exitstatus")
      
      # Install package and try again
      tpkg = Tpkg.new(:file_system_root => testroot, :sources => [@pkgfile])
      tpkg.install([@pkgfile], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      # Installed packages should still show up as available
      status = Open4.popen4(
        "#{RUBY} #{TPKG_EXECUTABLE} --qas " +
        "--source #{[@pkgfile,pkgfile2,pkgfile3].join(',')} " +
        "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal(
          [pkgfile2, @pkgfile, pkgfile3].collect {
            |p| "#{File.basename(p)} (#{p})"}.join("\n") + "\n",
          stdout.read, "--qas, installed, stdout")
        assert_equal('', stderr.read, "--qas, installed, stderr")
      end
      assert_equal(0, status.exitstatus, "--qas, installed, exitstatus")
      # Same query with --quiet should be quiet
      status = Open4.popen4(
        "#{RUBY} #{TPKG_EXECUTABLE} --qas " +
        "--source #{[@pkgfile,pkgfile2,pkgfile3].join(',')} --quiet " +
        "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal('', stdout.read, "--qas --quiet, installed, stdout")
        assert_equal('', stderr.read, "--qas --quiet, installed, stderr")
      end
      assert_equal(
        0, status.exitstatus, "--qas --quiet, installed, exitstatus")
      
      # A package that's installed but no longer available should not show up
      # as available
      status = Open4.popen4(
        "#{RUBY} #{TPKG_EXECUTABLE} --qas " +
        "--source #{[pkgfile2,pkgfile3].join(',')} " +
        "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal(
          [pkgfile2, pkgfile3].collect {
            |p| "#{File.basename(p)} (#{p})"}.join("\n") + "\n",
          stdout.read, "--qas, installed, stdout")
        assert_equal('', stderr.read, "--qas, installed, stderr")
      end
      assert_equal(
        0, status.exitstatus, "--qas, installed, exitstatus")
      # Same query with --quiet should be quiet
      status = Open4.popen4(
        "#{RUBY} #{TPKG_EXECUTABLE} --qas " +
        "--source #{[pkgfile2,pkgfile3].join(',')} --quiet " +
        "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal('', stdout.read, "--qas --quiet, installed, stdout")
        assert_equal('', stderr.read, "--qas --quiet, installed, stderr")
      end
      assert_equal(
        0, status.exitstatus, "--qas --quiet, installed, exitstatus")
        
      # No available packages should still be reported as such even if
      # packages are installed
      status = Open4.popen4(
        "#{RUBY} #{TPKG_EXECUTABLE} --qas " +
        "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal(
          '', stdout.read, "--qas, installed but not available, stdout")
        assert_equal(
          "No packages available\n",
          stderr.read, "--qas, installed but not available, stderr")
      end
      assert_equal(
        1, status.exitstatus,
        "--qas, installed but not available, exitstatus")
      # Same query with --quiet should be quiet
      status = Open4.popen4(
        "#{RUBY} #{TPKG_EXECUTABLE} --qas --quiet " +
        "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal(
          '', stdout.read,
          "--qas --quiet, installed but not available, stdout")
        assert_equal(
          '', stderr.read,
          "--qas --quiet, installed but not available, stderr")
      end
      assert_equal(
        1, status.exitstatus,
        "--qas --quiet, installed but not available, exitstatus")
    end
  end
  def test_qr
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qr #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "No other package depends on '#{query}'\n",
            stdout.read, "--qr #{query}, not installed, stdout")
          assert_equal(
            "No packages matching '#{query}' installed\n",
            stderr.read, "--qr #{query}, not installed, stderr")
        end
        assert_equal(1, status.exitstatus, "--qr #{query}, not installed, exitstatus")
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
        status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qr #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "The following package(s) require #{File.basename(@pkgfile)}:\n" +
            "  #{File.basename(pkgfile2)}\n",
            stdout.read, "--qr #{query}, installed, stdout")
          assert_equal(
            "", stderr.read, "--qr #{query}, installed, stderr")
        end
        assert_equal(0, status.exitstatus, "--qr, #{metadata[:name]}, installed, exitstatus")
      end
      [File.basename(pkgfile2), metadata2[:name]].each do |query|
        status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qr #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal("No other package depends on '#{query}'\n",
            stdout.read, "--qr #{query}, installed, stdout")
          assert_equal("", stderr.read, "--qr #{query}, installed, stderr")
        end
        assert_equal(0, status.exitstatus, "--qr #{query}, installed, exitstatus")
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
        status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qd #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal("", stdout.read, "--qd #{query}, not installed, stdout")
          assert_equal("No packages matching '#{query}' installed\n",
            stderr.read, "--qd #{query}, not installed, stderr")
        end
        assert_equal(1, status.exitstatus, "--qd #{query}, not installed, exitstatus")
      end
      # But querying a package file should work
      # This package has no dependencies
      status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qd #{@pkgfile} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal(
          "Package '#{@pkgfile}' does not depend on other packages\n",
          stdout.read, "--qd #{@pkgfile}, not installed, stdout")
        assert_equal(
          "", stderr.read, "--qd #{@pkgfile}, not installed, stderr")
      end
      assert_equal(0, status.exitstatus, "--qd #{@pkgfile}, not installed, exitstatus")
      # This package has some dependencies
      status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qd #{pkgfile3} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal("Package #{File.basename(pkgfile3)} depends on:\n" +
          "  name: qdslavepkg\n  type: tpkg\n\n" +
          "  name: #{metadata[:name]}\n  type: tpkg\n",
          stdout.read, "--qd #{pkgfile3}, not installed, stdout")
        assert_equal("", stderr.read, "--qd #{pkgfile3}, not installed, stderr")
      end
      assert_equal(0, status.exitstatus, "--qd #{pkgfile3}, not installed, exitstatus")
      
      # Install packages and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile, pkgfile2, pkgfile3])
      tpkg.install([@pkgfile, pkgfile2, pkgfile3], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qd #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "Package '#{query}' does not depend on other packages\n",
            stdout.read, "--qd #{query}, installed, stdout")
          assert_equal(
            "", stderr.read, "--qd #{query}, installed, stderr")
        end
        assert_equal(0, status.exitstatus, "--qd #{query}, installed, exitstatus")
      end
      [File.basename(pkgfile3), metadata3[:name]].each do |query|
        status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qd #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal("Package #{File.basename(pkgfile3)} depends on:\n" +
            "  name: qdslavepkg\n  type: tpkg\n\n" +
            "  name: #{metadata[:name]}\n  type: tpkg\n",
            stdout.read, "--qd #{query}, installed, stdout")
          assert_equal("", stderr.read, "--qd #{query}, installed, stderr")
        end
        assert_equal(0, status.exitstatus, "--qd #{query}, installed, exitstatus")
      end
    end
  end
  def test_qds
    # FIXME: ways to improve this:
    # - Multiple packages available matching package name
    #   - Some available packages have dependencies, some done
    # - For the "Installed and available" case make the installed and available packages different to make sure that we're getting the data for the available package instead of the installed package
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      pkgfile2 = make_package(
        :change => {'name' => 'qdsslavepkg'},
        :remove => ['operatingsystem', 'architecture'],
        :output_directory => File.join(testroot, 'tmp'))
      metadata2 = Tpkg::metadata_from_package(pkgfile2)
      pkgfile3 = make_package(
        :change => {'name' => 'qdsdepspkg'},
        :dependencies => {metadata[:name] => {}, 'qdsslavepkg' => {:minimum_version => '1'}},
        :remove => ['operatingsystem', 'architecture'],
        :output_directory => File.join(testroot, 'tmp'))
      metadata3 = Tpkg::metadata_from_package(pkgfile3)
      
      # Not available, not installed
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qds #{query} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "", stdout.read,
            "--qds #{query}, not available, not installed, stdout")
          assert_equal(
            "No packages matching '#{query}' available\n", stderr.read,
            "--qds #{query}, not available, not installed, stderr")
        end
        assert_equal(
          1, status.exitstatus,
          "--qds #{query}, not available, not installed, exitstatus")
      end
      
      # Available, not installed
      # This package has no dependencies
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qds #{query} " +
          "--source=#{[@pkgfile,pkgfile2,pkgfile3].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "Package '#{query}' does not depend on other packages\n",
            stdout.read, "--qds #{query}, available, not installed, stdout")
          assert_equal(
            "", stderr.read,
            "--qds #{query}, available, not installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qds #{query}, available, not installed, exitstatus")
      end
      # This package has some dependencies
      [File.basename(pkgfile3), metadata3[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qds #{query} " +
          "--source=#{[@pkgfile,pkgfile2,pkgfile3].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal("Package #{File.basename(pkgfile3)} depends on:\n" +
            "  name: qdsslavepkg\n  type: tpkg\n\n" +
            "  name: #{metadata[:name]}\n  type: tpkg\n",
            stdout.read, "--qds #{query}, available, not installed, stdout")
          assert_equal(
            "", stderr.read,
            "--qds #{query}, available, not installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qds #{query}, available, not installed, exitstatus")
      end
      
      # Install packages and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile, pkgfile2, pkgfile3])
      tpkg.install([@pkgfile, pkgfile2, pkgfile3], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      # Installed and available
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qds #{query} " +
          "--source=#{[@pkgfile,pkgfile2,pkgfile3].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "Package '#{query}' does not depend on other packages\n",
            stdout.read, "--qds #{query}, available, installed, stdout")
          assert_equal(
            "", stderr.read, "--qds #{query}, available, installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qds #{query}, available, installed, exitstatus")
      end
      [File.basename(pkgfile3), metadata3[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qds #{query} " +
          "--source=#{[@pkgfile,pkgfile2,pkgfile3].join(',')} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal("Package #{File.basename(pkgfile3)} depends on:\n" +
            "  name: qdsslavepkg\n  type: tpkg\n\n" +
            "  name: #{metadata[:name]}\n  type: tpkg\n",
            stdout.read, "--qds #{query}, available, installed, stdout")
          assert_equal(
            "", stderr.read, "--qds #{query}, available, installed, stderr")
        end
        assert_equal(
          0, status.exitstatus,
          "--qds #{query}, available, installed, exitstatus")
      end
      
      # Not available but installed
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qds #{query} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            "", stdout.read,
            "--qds #{query}, not available, installed, stdout")
          assert_equal(
            "No packages matching '#{query}' available\n", stderr.read,
            "--qds #{query}, not available, installed, stderr")
        end
        assert_equal(
          1, status.exitstatus,
          "--qds #{query}, not available, installed, exitstatus")
      end
    end
  end
  def test_qX
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      # Query with no package installed
      # Queries for installed packages should return nothing
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qX #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal("", stdout.read, "--qX #{query}, not installed, stdout")
          assert_equal("No packages matching '#{query}' installed\n",
            stderr.read, "--qX #{query}, not installed, stderr")
        end
        assert_equal(1, status.exitstatus, "--qX #{query}, not installed, exitstatus")
      end
      # But querying a package file should work
      status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qX #{@pkgfile} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
        stdin.close
        assert_equal(metadata.text, stdout.read, "--qX #{@pkgfile}, not installed, stdout")
        assert_equal("", stderr.read, "--qX #{@pkgfile}, not installed, stderr")
      end
      assert_equal(0, status.exitstatus, "--qX #{@pkgfile}, not installed, exitstatus")
      
      # Install package and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile])
      tpkg.install([@pkgfile], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4("#{RUBY} #{TPKG_EXECUTABLE} --qX #{query} --test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(
            metadata.text, stdout.read, "--qX #{query}, installed, stdout")
          assert_equal("", stderr.read, "--qX #{query}, installed, stderr")
        end
        assert_equal(0, status.exitstatus, "--qX #{query}, installed, exitstatus")
      end
    end
  end
  def test_qXs
    # FIXME: ways to improve this:
    # - Multiple packages available matching package name
    # - For the "Installed and available" case make the installed and available packages different to make sure that we're getting the data for the available package instead of the installed package
    metadata = Tpkg::metadata_from_package(@pkgfile)
    
    Dir.mktmpdir('testroot') do |testroot|
      # Not available, not installed
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qXs #{query} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal("", stdout.read,
            "--qXs #{query}, not available, not installed, stdout")
          assert_equal(
            "No packages matching '#{query}' available\n", stderr.read,
            "--qXs #{query}, not available, not installed, stderr")
        end
        assert_equal(1, status.exitstatus,
          "--qXs #{query}, not available, not installed, exitstatus")
      end
      
      # Available, not installed
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qXs #{query} " +
          "--source #{@pkgfile} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(metadata.text, stdout.read,
            "--qXs #{query}, available, not installed, stdout")
          assert_equal("", stderr.read,
            "--qXs #{query}, available, not installed, stderr")
        end
        assert_equal(0, status.exitstatus,
          "--qXs #{query}, available, not installed, exitstatus")
      end
      
      # Install package and try again
      tpkg = Tpkg.new(
        :file_system_root => testroot,
        :sources => [@pkgfile])
      tpkg.install([@pkgfile], PASSPHRASE)
      
      # TPKG_HOME ends up set in our environment due to use of the tpkg library
      ENV.delete('TPKG_HOME')
      
      # Installed and available
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qXs #{query} " +
          "--source #{@pkgfile} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal(metadata.text, stdout.read,
            "--qXs #{query}, installed and available, stdout")
          assert_equal("", stderr.read,
            "--qXs #{query}, installed and available, stderr")
        end
        assert_equal(0, status.exitstatus,
          "--qXs #{query}, installed and available, exitstatus")
      end
      
      # Installed, not available
      [File.basename(@pkgfile), metadata[:name]].each do |query|
        status = Open4.popen4(
          "#{RUBY} #{TPKG_EXECUTABLE} --qXs #{query} " +
          "--test-root #{testroot}") do |pid, stdin, stdout, stderr|
          stdin.close
          assert_equal("", stdout.read,
            "--qXs #{query}, not available, installed, stdout")
          assert_equal(
            "No packages matching '#{query}' available\n", stderr.read,
            "--qXs #{query}, not available, installed, stderr")
        end
        assert_equal(1, status.exitstatus,
          "--qXs #{query}, not available, installed, exitstatus")
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
    # Test the --base switch
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
    # Test the --test-root switch
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
    FileUtils.rm_f(@pkgfile)
  end
end

