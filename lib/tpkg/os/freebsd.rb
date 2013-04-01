# tpkg package management system
# License: MIT (http://www.opensource.org/licenses/mit-license.php)

require 'erb'

class Tpkg::OS::FreeBSD < Tpkg::OS
  def self.supported?
    Facter.loadfacts
    Facter['operatingsystem'].value == 'FreeBSD'
  end
  register_implementation(self)
  
  def initialize(options={})
    @pkginfocmd = options[:pkginfocmd] || options[:testcmd] || 'pkg_info'
    @pkgaddcmd = options[:pkgaddcmd] || options[:testcmd] || 'pkg_add'
    @pkgdeletecmd = options[:pkgdeletecmd] || options[:testcmd] || 'pkg_delete'
    # pkg_add -r defaults to the Latest/ directory, which just has generic
    # versionless symlinks like curl.tbz.  We want to use the All/ directory
    # so that we can specify a versioned file like curl-7.24.0.tbz.
    @packagesite = options[:packagesite] ||
      'ftp://ftp.freebsd.org/pub/FreeBSD/ports/<%= arch %>/packages-<%= os_version %>-stable/All/'
    super
  end
  
  def packagesite
    url = ERB.new(@packagesite).result(binding)
    # pkg_add expects the URL to end with a /
    url << '/' if (url[-1] != '/')
    url
  end
  
  def init_links(installed_path, tpkgfile)
    links = []
    init_directory = '/usr/local/etc/rc.d'
    if tpkgfile[:init][:levels] && tpkgfile[:init][:levels].empty?
      # User doesn't want the init script linked in to auto-start
    else
      links << File.join(init_directory, File.basename(installed_path))
    end
    links
  end
  def available_native_packages(pkgname)
    native_packages = []
    cmd = "#{@pkginfocmd} -E #{pkgname}-*"
    puts "available_native_packages running '#{cmd}'" if @debug
    Open3.popen3(cmd) do |stdin, stdout, stderr|
      stdin.close
      stdout.each_line do |line|
        fbversion = line.sub("#{pkgname}-", '').chomp
        # Seems to be FreeBSD convention that if the package has a
        # package version you seperate that from the upstream version
        # with an underscore.
        version, package_version = fbversion.split('_', 2)
        native_packages <<
          Tpkg.pkg_for_native_package(
            pkgname, version, package_version, :native_installed)
      end
      stderr_first_line = stderr.gets
    end
    # FIXME: popen3 doesn't set $?
    if !$?.success?
      # Ignore 'no matching packages', raise anything else
      if stderr_first_line !~ 'No match'
        raise "available_native_packages error running pkg_info"
      end
    end
    # FIXME: FreeBSD available packages
    # We could either poke around in the ports tree (if installed), or
    # try to recreate the URL "pkg_add -r" would use and pull a
    # directory listing.
    native_packages
  end
  def native_pkg_to_install_string(pkg)
    name = pkg[:metadata][:name]
    version = pkg[:metadata][:version]
    package_version = pkg[:metadata][:package_version]
    pkgname = "#{name}-#{version}"
    if package_version
       pkgname << "_#{package_version}"
    end
    pkgname
  end
  def install_native_package(pkg)
    pkgname = native_pkg_to_install_string(pkg)
    cmd = "PACKAGESITE=#{packagesite} #{@pkgaddcmd} -r #{pkgname}"
    puts "Running '#{cmd}' to install native package" if @debug
    system('sh', '-c', cmd)
  end
  def upgrade_native_package(pkg)
    pkgname = native_pkg_to_install_string(pkg)
    # This is not very ideal.  It would be better to download the
    # new package, and if the download is successful remove the
    # old package and install the new one.  The way we're doing it
    # here we risk leaving the system with neither version
    # installed if the download of the new package fails.
    # However, the FreeBSD package tools don't make it easy to
    # handle things properly.
    deletecmd = "#{@pkgdeletecmd} #{pkgname}"
    addcmd = "PACKAGESITE=#{packagesite} #{@pkgaddcmd} -r #{pkgname}"
    puts "Running '#{deletecmd}' and '#{addcmd}' to upgrade native package" if @debug
    system(deletecmd)
    system('sh', '-c', addcmd)
  end
  
  def os_version
    if !@os_version
      # Extract 7 from 7.1-RELEASE, for example
      fbver = Facter['operatingsystemrelease'].value
      @os_version = fbver.split('.').first
    end
    super
  end
end
