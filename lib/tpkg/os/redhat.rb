# tpkg package management system
# License: MIT (http://www.opensource.org/licenses/mit-license.php)

class Tpkg::OS::RedHat < Tpkg::OS
  def self.supported?
    Facter.loadfacts
    ['RedHat', 'CentOS', 'Fedora'].include?(Facter['operatingsystem'].value)
  end
  register_implementation(self)

  def initialize(options={})
    @yumcmd = options[:yumcmd] || options[:testcmd] || 'yum'
    @rpmcmd = options[:rpmcmd] || options[:testcmd] || 'rpm'
    @rpmbuildcmd = options[:rpmbuildcmd] || options[:testcmd] || 'rpmbuild'
    # This is primarily used by the unit tests
    @quiet = options[:quiet]
    super
  end

  def init_links(installed_path, tpkgfile)
    sys_v_init_links(installed_path, tpkgfile, ['2', '3', '4', '5'], '/etc/rc.d')
  end
  def cron_dot_d_directory
    '/etc/cron.d'
  end
  def available_native_packages(pkgname)
    native_packages = []
    [ {:arg => 'installed', :header => 'Installed', :source => :native_installed},
      {:arg => 'available', :header => 'Available', :source => :native_available} ].each do |yum|
      cmd = "#{@yumcmd} info #{yum[:arg]} #{pkgname}"
      puts "available_native_packages running '#{cmd}'" if @debug
      stderr_first_line = nil
      exit_status = nil
      Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        read_packages = false
        name = version = package_version = nil
        stdout.each_line do |line|
          if line =~ /#{yum[:header]} Packages/
            # Skip the header lines until we get to this line
            read_packages = true
          elsif read_packages
            if line =~ /^Name\s*:\s*(.+)/
              name = $1.strip
            elsif line =~ /^Arch\s*:\s*(.+)/
              arch = $1.strip
            elsif line =~ /^Version\s*:\s*(.+)/
              version = $1.strip.to_s
            elsif line =~ /^Release\s*:\s*(.+)/
              package_version = $1.strip.to_s
            elsif line =~ /^Repo\s*:\s*(.+)/
              repo = $1.strip
            elsif line =~ /^\s*$/
              pkg = Tpkg.pkg_for_native_package(name, version, package_version, yum[:source])
              native_packages << pkg
              name = version = package_version = nil
            end
            # In the end we ignore the architecture.  Anything that
            # shows up in yum should be installable on this box, and
            # the chance of a mismatch between facter's idea of the
            # architecture and RPM's idea is high.  I.e. i386 vs i686
            # or i32e vs x86_64 or whatever.
          end
        end
        stderr_first_line = stderr.gets
        exit_status = wait_thr ? wait_thr.value : $?	# Pre-1.9 Ruby's popen3 doesn't return the thread. $? is not correct, but it was used here instead of Thread.value for a long time.
      end
      if !exit_status.success?
        # Ignore 'no matching packages', raise anything else
        if stderr_first_line != "Error: No matching Packages to list\n"
          raise "available_native_packages error running yum"
        end
      end
    end
    native_packages
  end
  def install_native_package(pkg)
    pkgname = native_pkg_to_install_string(pkg)
    cmd = "#{@yumcmd} -y install #{pkgname}"
    puts "Running '#{cmd}' to install native package" if @debug
    system(cmd)
  end
  def upgrade_native_package(pkg)
    pkgname = native_pkg_to_install_string(pkg)
    cmd = "#{@yumcmd} -y install #{pkgname}"
    puts "Running '#{cmd}' to upgrade native package" if @debug
    system(cmd)
  end
  def stub_native_pkg(pkg)
    native_deps = pkg[:metadata].get_native_deps
    return if native_deps.empty?

    rpm = create_rpm("stub_for_#{pkg[:metadata][:name]}", native_deps)
    return if rpm.nil?

    cmd = "#{@rpmcmd} -i #{rpm}"
    puts "Running '#{cmd} to install native dependency stub" if @debug
    system(cmd)
    if !$?.success?
      warn "Warning: Failed to install native stub package for #{pkg[:metadata][:name]}" unless @quiet
    end
  end
  def remove_native_stub_pkg(pkg)
    native_deps = pkg[:metadata].get_native_deps
    return if native_deps.empty?

    stub_pkg_name = "stub_for_#{pkg[:metadata][:name]}"
    cmd = "#{@yumcmd} -y remove #{stub_pkg_name}"
    puts "Running '#{cmd} to remove native dependency stub" if @debug
    puts cmd if @debug
    system(cmd)
    if !$?.success?
      warn "Warning: Failed to remove native stub package for #{pkg[:metadata][:name]}" unless @quiet
    end
  end

  def os_version
    if !@os_version
      if Facter['lsbmajdistrelease'] &&
         Facter['lsbmajdistrelease'].value &&
         !Facter['lsbmajdistrelease'].value.empty?
        @os_version = Facter['lsbmajdistrelease'].value
      end
    end
    super
  end

  private
  def create_rpm(name, deps=[])
    topdir = Tpkg::tempdir('rpmbuild')
    %w[BUILD RPMS SOURCES SPECS SRPMS].each do |dir|
      FileUtils.mkdir_p(File.join(topdir, dir))
    end

    dep_list = deps.collect{|dep|dep[:name]}.join(",")

    spec = <<-EOS.gsub(/^\s+/, "")
    Name: #{name}
    Summary: stub pkg created by tpkg
    Version: 1
    Release: 1
    buildarch: noarch
    Requires: #{dep_list}
    Group: Applications/System
    License: MIT
    BuildRoot: %{_builddir}/%{name}-buildroot
    %description
    stub pkg created by tpkg for the following dependencies: #{dep_list}
    %files
    EOS
    spec_file = File.join(topdir, 'SPECS', 'pkg.spec')
    File.open(spec_file, 'w') do |file|
      file.puts(spec)
    end

    system("#{@rpmbuildcmd} -bb --define '_topdir #{topdir}' #{spec_file}")
    if !$?.success?
      warn "Warning: Failed to create native stub package for #{name}" unless @quiet
      return nil
    end
    result = File.join(topdir, 'RPMS', 'noarch', "#{name}-1-1.noarch.rpm")
    if !File.exists?(result)
      warn "Warning: rpmbuild failed to produce a native stub package for #{name}" unless @quiet
      return nil
    end
    tmpfile = Tempfile.new(File.basename(result))
    FileUtils.cp(result, tmpfile.path)
    rpm = tmpfile.path
    FileUtils.rm_rf(topdir)

    return rpm
  end

end
