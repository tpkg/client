# tpkg package management system
# License: MIT (http://www.opensource.org/licenses/mit-license.php)

class Tpkg::OS::Debian < Tpkg::OS
  def self.supported?
    Facter.loadfacts
    ['Debian', 'Ubuntu'].include?(Facter['operatingsystem'].value)
  end
  register_implementation(self)
  
  def initialize(options={})
    @dpkgquerycmd = options[:dpkgquerycmd] || options[:testcmd] || 'dpkg-query'
    @aptcachecmd = options[:aptcachecmd] || options[:testcmd] || 'apt-cache'
    @aptgetcmd = options[:aptgetcmd] || options[:testcmd] || 'apt-get'
    super
  end
  
  def init_links(installed_path, tpkgfile)
    sys_v_init_links(installed_path, tpkgfile, ['2', '3', '4', '5'], '/etc')
  end
  def cron_dot_d_directory
    '/etc/cron.d'
  end
  def available_native_packages(pkgname)
    native_packages = []
    # The default 'dpkg -l' format has an optional third column for errors
    # which makes it hard to parse reliably, so we specify a custom format.
    cmd = "#{@dpkgquerycmd} -W -f='${Package} ${Version} ${Status}\n' #{pkgname}"
    puts "available_native_packages running #{cmd}" if @debug
    stderr_first_line = nil
    exit_status = nil
    Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      stdout.each_line do |line|
        name, debversion, status = line.split(' ', 3)
        # Seems to be Debian convention that if the package has a
        # package version you seperate that from the upstream version
        # with a hyphen.
        version = nil
        package_version = nil
        if debversion =~ /-/
          version, package_version = debversion.split('-', 2)
        else
          version = debversion
        end
        # We want packages with a state of "installed".  However,
        # there's also a state of "not-installed", and the state
        # field contains several space-seperated values, so we have
        # to be somewhat careful to pick out "installed".
        if status.split(' ').include?('installed')
          pkg = Tpkg.pkg_for_native_package(name, version, package_version, :native_installed)
          native_packages << pkg
        end
      end
      stderr_first_line = stderr.gets
      exit_status = wait_thr ? wait_thr.value : $?	# Pre-1.9 Ruby's popen3 doesn't return the thread. $? is not correct, but it was used here instead of Thread.value for a long time.
    end
    if !exit_status.success?
      # Ignore 'no matching packages', raise anything else
      if stderr_first_line !~ 'No packages found matching'
        raise "available_native_packages error running dpkg-query"
      end
    end
    
    cmd = "#{@aptcachecmd} show #{pkgname}"
    puts "available_native_packages running '#{cmd}'" if @debug
    stderr_first_line = nil
    Open3.popen3(cmd) do |stdin, stdout, stderr|
      stdin.close
      name = nil
      version = nil
      package_version = nil
      skip = false
      stdout.each_line do |line|
        if line =~ /^Package: (.*)/
          name = $1
          version = nil
          package_version = nil
          skip = false
        elsif line =~ /Status: (.*)/
          # Packages with status are coming from dpkg rather than apt. They're
          # either already installed (and thus captured by the dpkg-query
          # above) or uninstalled and not really available.  This seems to be
          # a new feature of apt-get in Debian 7.  On older systems these
          # packages don't show up in apt-get show, which is why we still need
          # the dpkg-query command above.
          skip = true
        elsif line =~ /^Version: (.*)/ && !skip
          debversion = $1
          # Seems to be Debian convention that if the package has a
          # package version you seperate that from the upstream version
          # with a hyphen.
          if debversion =~ /-/
            version, package_version = debversion.split('-', 2)
          else
            version = debversion
          end
          pkg = Tpkg.pkg_for_native_package(name, version, package_version, :native_available)
          native_packages << pkg
        end
      end
      stderr_first_line = stderr.gets
    end
    # FIXME: popen3 doesn't set $?
    if !$?.success?
      # Ignore 'no matching packages', raise anything else
      if stderr_first_line !~ 'No packages found'
        raise "available_native_packages error running apt-cache"
      end
    end
    native_packages
  end
  def native_pkg_to_install_string(pkg)
    name = pkg[:metadata][:name]
    version = pkg[:metadata][:version]
    package_version = pkg[:metadata][:package_version]
    pkgname = "#{name}=#{version}"
    if package_version
       pkgname << "-#{package_version}"
    end
    pkgname
  end
  def install_native_package(pkg)
    pkgname = native_pkg_to_install_string(pkg)
    cmd = "#{@aptgetcmd} -y install #{pkgname}"
    puts "Running '#{cmd}' to install native package" if @debug
    system(cmd)
  end
  def upgrade_native_package(pkg)
    pkgname = native_pkg_to_install_string(pkg)
    cmd = "#{@aptgetcmd} -y install #{pkgname}"
    puts "Running '#{cmd}' to upgrade native package" if @debug
    system(cmd)
  end
  
  def os_version
    if !@os_version
      if Facter['lsbmajdistrelease'] &&
         Facter['lsbmajdistrelease'].value &&
         !Facter['lsbmajdistrelease'].value.empty?
        lsbmajdistrelease = Facter['lsbmajdistrelease'].value
        # Normal wheezy beta returns 'testing', but Raspian on the
        # Raspberry Pi returns this uglier string.  Normalize it.
        if lsbmajdistrelease == 'testing/unstable'
          lsbmajdistrelease = 'testing'
        end
        @os_version = lsbmajdistrelease
      elsif Facter['lsbdistrelease'] &&
            Facter['lsbdistrelease'].value &&
            !Facter['lsbdistrelease'].value.empty? &&
        # Work around lack of lsbmajdistrelease on older versions of Ubuntu
        # due to older version of facter.  Support for lsbmajdistrelease on
        # Ubuntu was added in facter 1.5.3, but there's no good way to force
        # older Ubuntu systems to a newer version of facter.
        @os_version = Facter['lsbdistrelease'].value.split('.').first
      end
    end
    super
  end
end
