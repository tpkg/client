# tpkg package management system
# License: MIT (http://www.opensource.org/licenses/mit-license.php)

begin
  # Try loading facter w/o gems first so that we don't introduce a
  # dependency on rubygems if it is not needed.
  require 'facter'
rescue LoadError
  require 'rubygems'
  require 'facter'
end

class Tpkg::OS
  @@implementations = []
  def self.register_implementation(impl)
    @@implementations << impl
  end
  Dir.glob(File.expand_path('os/*.rb', File.dirname(__FILE__))).each {|d| require d}
  def self.create(options={})
    impl = @@implementations.detect{|i| i.supported?} || raise(NotImplementedError)
    impl.new(options)
  end

  def initialize(options={})
    @debug = options[:debug]
    @os = nil
    @os_name = nil
    @os_version = nil
    @arch = nil
    Facter.loadfacts
  end

  #
  # OS-specific classes should (must?) implement these methods
  #

  # Given info for a init script from a package's metadata return an array
  # of paths where that init script should linked to on the system
  def init_links(installed_path, tpkgfile)
    # I think users would rather have packages install without their init
    # scripts enabled than have them fail to install on platforms where we
    # don't have init script support.
    # raise NotImplementedError
    warn "No init script support for OS #{os}"
    []
  end
  def available_native_packages(pkgname)
    raise NotImplementedError
  end
  def install_native_package(pkg)
    raise NotImplementedError
  end
  def upgrade_native_package(pkg)
    raise NotImplementedError
  end
  # Create and install a native stub package, if pkg has native
  # dependencies, to express those dependencies to the native package
  # system.  This helps ensure that users don't inadvertently remove native
  # packages that tpkg packages depend on.
  def stub_native_pkg(pkg)
    # I think users would rather have packages install without a native stub
    # than have them fail to install on platforms where we don't have native
    # stub support.
    # raise NotImplementedError
    native_deps = pkg[:metadata].get_native_deps
    if !native_deps.empty?
      warn "No native stub support for OS #{os}"
    end
  end
  # Remove the native dependency stub package (if there is one) associated
  # with pkg
  def remove_native_stub_pkg(pkg)
    # raise NotImplementedError
    warn "No native stub support for OS #{os}"
  end
  # This rarely works as-is, most platforms need something more specific
  def os_version
    if !@os_version
      if Facter['operatingsystemrelease'] &&
         Facter['operatingsystemrelease'].value &&
         !Facter['operatingsystemrelease'].value.empty?
        @os_version = Facter['operatingsystemrelease'].value
      else
        raise "Unable to determine proper OS value on this platform"
      end
    end
    @os_version.dup
  end
  # This also rarely works as-is
  def native_pkg_to_install_string(pkg)
    name = pkg[:metadata][:name]
    version = pkg[:metadata][:version]
    package_version = pkg[:metadata][:package_version]
    pkgname = "#{name}-#{version}"
    if package_version
       pkgname << "-#{package_version}"
    end
    pkgname
  end

  #
  # These methods have implementations that work in most cases, but
  # OS-specific classes may modify these definitions if needed.
  #

  def os
    if !@os
      @os = "#{os_name}-#{os_version}"
    end
    @os.dup
  end
  def os_name
    if !@os_name
      @os_name = Facter['operatingsystem'].value
    end
    @os_name.dup
  end
  def arch
    if !@arch
      @arch = Facter['hardwaremodel'].value
    end
    @arch.dup
  end
  def fqdn
    # Note that we intentionally do not cache the fqdn.  The hostname of a
    # machine can change at any time and it would be unexpected if the user
    # had to restart a tpkg-based application to pick up a hostname change.
    if Facter['fqdn'] && Facter['fqdn'].value
      Facter['fqdn'].value
    else
      Facter['hostname'].value << '.' << Facter['domain'].value
    end
  end
  # Systems with cron.d support should override this
  def cron_dot_d_directory
  end
  # Should sudo be on by default?
  def sudo_default?
    true
  end

  #
  # Utility methods
  #

  def sys_v_init_links(installed_path, tpkgfile, default_levels, init_directory)
    start = '99'
    if tpkgfile[:init][:start]
      start = tpkgfile[:init][:start]
    end
    levels = default_levels
    if tpkgfile[:init][:levels]
      levels = tpkgfile[:init][:levels]
      # In case the user specified levels in yaml as string/integer
      # instead of array
      if !levels.kind_of?(Array)
        levels = levels.to_s.split(//)
      end
    end
    levels.collect do |level|
      File.join(init_directory, "rc#{level}.d", 'S' + start.to_s + File.basename(installed_path))
    end
  end
end
