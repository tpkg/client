# tpkg package management system
# License: MIT (http://www.opensource.org/licenses/mit-license.php)

class Tpkg::OS::Solaris < Tpkg::OS
  def self.supported?
    Facter.loadfacts
    Facter['operatingsystem'].value == 'Solaris'
  end
  register_implementation(self)
  
  def initialize(options={})
    @pkginfocmd = options[:pkginfocmd] || options[:testcmd] || 'pkginfo'
    @pkgutilcmd = options[:pkgutilcmd] || options[:testcmd] || '/opt/csw/bin/pkgutil'
    super
  end
  
  def init_links(installed_path, tpkgfile)
    sys_v_init_links(installed_path, tpkgfile, ['2', '3'], '/etc')
  end
  def available_native_packages(pkgname)
    native_packages = []
    # Example of pkginfo -x output:
    # SUNWzfsu                      ZFS (Usr)
    #                               (i386) 11.10.0,REV=2006.05.18.01.46
    cmd = "#{@pkginfocmd} -x #{pkgname}"
    puts "available_native_packages running '#{cmd}'" if @debug
    IO.popen(cmd) do |pipe|
      name = nil
      pipe.each_line do |line|
        if line =~ /^\w/
          name = line.split(' ').first
        else
          arch, solversion = line.split(' ')
          # Lots of Sun and some third party packages (including CSW)
          # seem to use this REV= convention in the version.  I've
          # never seen it documented, but since it seems to be a
          # widely used convention we'll go with it.
          version, package_version = solversion.split(',REV=')
          native_packages <<
            Tpkg.pkg_for_native_package(
              name, version, package_version, :native_installed)
          name = nil
        end
      end
    end
    if !$?.success?
      raise "available_native_packages error running pkginfo"
    end
    if File.exist?(@pkgutilcmd)
      cmd = "#{@pkgutilcmd} -a --parse #{pkgname}"
      puts "available_native_packages running '#{cmd}'" if @debug
      IO.popen(cmd) do |pipe|
        pipe.each_line do |line|
          shortname, name, solversion, size = line.chomp.split("\t")
          # pkgutil treats the specified name as a regular expression, so we
          # have filter for the ones that are an exact match
          next if name != pkgname
          # Lots of Sun and some third party packages (including CSW)
          # seem to use this REV= convention in the version.  I've
          # never seen it documented, but since it seems to be a
          # widely used convention we'll go with it.
          version, package_version = solversion.split(',REV=')
          native_packages <<
            Tpkg.pkg_for_native_package(
              name, version, package_version, :native_available)
        end
      end
    end
    native_packages
  end
  def native_pkg_to_install_string(pkg)
    name = pkg[:metadata][:name]
    version = pkg[:metadata][:version]
    package_version = pkg[:metadata][:package_version]
    pkgname = "#{name}-#{version}"
    if package_version
       pkgname << ",REV=#{package_version}"
    end
    pkgname
  end
  def install_native_package(pkg)
    pkgname = native_pkg_to_install_string(pkg)
    if File.exist?(@pkgutilcmd)
      cmd = "#{@pkgutilcmd} -y -i #{pkgname}"
      puts "Running '#{cmd}' to install native package" if @debug
      system(cmd)
    else
      raise "No supported native package tool available on #{os}"
    end
  end
  def upgrade_native_package(pkg)
    pkgname = native_pkg_to_install_string(pkg)
    if File.exist?(@pkgutilcmd)
      cmd = "#{@pkgutilcmd} -y -u #{pkgname}"
      puts "Running '#{cmd}' to upgrade native package" if @debug
      system(cmd)
    else
      raise "No supported native package tool available on #{os}"
    end
  end
end
