# tpkg package management system
# License: MIT (http://www.opensource.org/licenses/mit-license.php)

class Tpkg::OS::MacOSX < Tpkg::OS
  def self.supported?
    Facter.loadfacts
    Facter['operatingsystem'].value == 'Darwin'
  end
  register_implementation(self)

  def initialize(options={})
    @portcmd = options[:portcmd] || options[:testcmd] || '/opt/local/bin/port'
    super
  end

  def available_native_packages(pkgname)
    native_packages = []
    if File.exist?(@portcmd)
      # Ports can also have an "epoch" number, but that appears to be
      # invisible from the command line
      # http://guide.macports.org/#reference.keywords
      cmd = "#{@portcmd} installed #{pkgname}"
      puts "available_native_packages running '#{cmd}'" if @debug
      IO.popen(cmd) do |pipe|
        pipe.each_line do |line|
          next if line =~ /The following ports are currently installed/
          next if line =~ /None of the specified ports are installed/
          next if line !~ /\(active\)/
          name, portversion = line.split(' ')
          portversion.sub!(/^@/, '')
          # Remove variant names
          portversion.sub!(/\+.*/, '')
          version, package_version = portversion.split('_', 2)
          pkg = Tpkg.pkg_for_native_package(name, version, package_version, :native_installed)
          native_packages << pkg
        end
      end
      if !$?.success?
        raise "available_native_packages error running port"
      end
      cmd = "#{@portcmd} list #{pkgname}"
      puts "available_native_packages running '#{cmd}'" if @debug
      IO.popen(cmd) do |pipe|
        pipe.each_line do |line|
          name, version = line.split(' ')
          version.sub!(/^@/, '')
          package_version = nil
          pkg = Tpkg.pkg_for_native_package(name, version, package_version, :native_available)
          native_packages << pkg
        end
      end
      if !$?.success?
        raise "available_native_packages error running port"
      end
    else
      # Fink, Homebrew support would be nice
      raise "No supported native package tool available on #{os}"
    end
    native_packages
  end
  def native_pkg_to_install_string(pkg)
    pkgname = nil
    if File.exist?(@portcmd)
      pkgname = pkg[:metadata][:name]
      # MacPorts doesn't support installing a specific version (AFAIK)
      if pkg[:metadata][:version]
        warn "Ignoring version with MacPorts"
      end
      if pkg[:metadata][:package_version]
        warn "Ignoring package version with MacPorts"
      end
    else
      # Fink, Homebrew support would be nice
      raise "No supported native package tool available on #{os}"
    end
    pkgname
  end
  def install_native_package(pkg)
    pkgname = native_pkg_to_install_string(pkg)
    if File.exist?(@portcmd)
      cmd = "#{@portcmd} install #{pkgname}"
      puts "Running '#{cmd}' to install native package" if @debug
      system(cmd)
    else
      # Fink, Homebrew support would be nice
      raise "No supported native package tool available on #{os}"
    end
  end
  def upgrade_native_package(pkg)
    pkgname = native_pkg_to_install_string(pkg)
    if File.exist?(@portcmd)
      cmd = "#{@portcmd} upgrade #{pkgname}"
      puts "Running '#{cmd}' to upgrade native package" if @debug
      system(cmd)
    else
      # Fink, Homebrew support would be nice
      raise "No supported native package tool available on #{os}"
    end
  end

  def os_version
    if !@os_version
      if Facter['macosx_productversion'] &&
         Facter['macosx_productversion'].value &&
         !Facter['macosx_productversion'].value.empty?
        macver = Facter['macosx_productversion'].value
        # Extract 10.5 from 10.5.6, for example
        @os_version = macver.split('.')[0,2].join('.')
      end
    end
    super
  end
end
