require 'tempfile'
require 'rexml/document'
require 'tpkg'
require 'nventory'

# Haven't found a Ruby method for creating temporary directories,
# so create a temporary file and replace it with a directory.
def tempdir(basename, tmpdir=Dir::tmpdir)
  tmpfile = Tempfile.new(basename, tmpdir)
  tmpdir = tmpfile.path
  tmpfile.close!
  Dir.mkdir(tmpdir)
  tmpdir
end

def get_tpkg_servers_for_environment(environment)
  nvclient = NVentory::Client.new
  servers = nvclient.get_expanded_nodegroup("tpkg_#{environment}")
  if servers.empty?
    abort "No servers found for environment '#{environment}'"
  end
  servers
end

namespace :tpkg do
  desc 'Build tpkg'
  task :build do
    # Check that we are in a directory that appears to be the top level
    # of a Rails app.  We need to be at the top level to get the right
    # svn url in the next step.
    if !File.exist?('app') || !File.exist?('config')
      raise "Run task from top level of Rails app"
    end
    
    # Get the svn url for the app
    url = nil
    IO.popen('svn info .') do |pipe|
      pipe.each do |line|
        line.chomp!
        if line =~ /^URL:\s*(.*)/
          url = $1
        end
      end
    end
    if !url
      raise "Unable to determine svn url"
    end
    
    # Prep the package build directory and export the app from svn
    pkgdir = tempdir('rake_tpkg')
    rootdir = File.join(pkgdir, 'root')
    mkdir(rootdir)
    apppath = File.join(rootdir, 'home/t/tpkg')
    mkdir_p(File.dirname(apppath))
    system("cd #{File.dirname(apppath)} && svn export #{url} #{File.basename(apppath)}")
    
    # Copy over tpkg.xml and any package scripts
    cp(File.join(apppath, 'config', 'tpkg.xml'), File.join(pkgdir, 'tpkg.xml'))
    ['preinstall', 'postinstall', 'preremove', 'postremove'].each do |script|
      if File.exist?(File.join(apppath, 'config', script))
        cp(File.join(apppath, 'config', script), File.join(pkgdir, script))
        File.chmod(0755, File.join(pkgdir, script))
      end
    end
    
    # We keep a generic database.yml in svn, need to remove that so we
    # can move the encrypted one into place in the next section.
    rm(File.join(apppath, 'config', 'database.yml'))
    
    # Rename precrypt files
    tpkg_xml = REXML::Document.new(File.open(File.join(pkgdir, 'tpkg.xml')))
    tpkg_xml.elements.each('/tpkg/files/file') do |tpkgfile|
      if tpkgfile.elements['encrypt']
        if tpkgfile.elements['encrypt'].attribute('precrypt') &&
           tpkgfile.elements['encrypt'].attribute('precrypt').value == 'true'
          tpkg_path = tpkgfile.elements['path'].text
          working_path = nil
          if tpkg_path[0,1] == File::SEPARATOR
            working_path = File.join(pkgdir, 'root', tpkg_path)
          else
            working_path = File.join(pkgdir, 'reloc', tpkg_path)
          end
          if !File.exist?(working_path + '.enc')
            warn "No .enc file for precrypt #{working_path}"
          elsif File.exist?(working_path)
            warn "Won't overwrite #{working_path} with .enc file"
          else
            mv(working_path + '.enc', working_path)
          end
        end
      end
    end
    
    # Copy init scripts into the appropriate place
    mkdir_p(File.join(rootdir, 'opt', 'tpkg', 'etc', 'init.d'))
    ['web', 'app', 'db'].each do |appclass|
      cp(File.join(apppath, 'config', "init-tpkg-#{appclass}"),
         File.join(rootdir, 'opt', 'tpkg', 'etc', 'init.d', "tpkg-#{appclass}"))
    end
    
    # Copy crontab into the appropriate place
    mkdir_p(File.join(rootdir, 'opt', 'tpkg', 'etc', 'cron.d'))
    # The tpkg client package installs a crontab named 'tpkg',
    # so we name this file 'tpkg_server' to differentiate
    cp(File.join(apppath, 'config', "cron-tpkg_server"),
       File.join(rootdir, 'opt', 'tpkg', 'etc', 'cron.d', "tpkg_server"))
    
    # stunnel server config -> /opt/tpkg/etc/stunnel
    mkdir_p(File.join(rootdir, 'opt', 'tpkg', 'etc', 'stunnel'))
    cp(File.join(apppath, 'config', 'stunnel-mysql_server.conf'),
       File.join(rootdir, 'opt', 'tpkg', 'etc', 'stunnel', 'mysql_server.conf'))
    
    # logrotate configs -> /opt/tpkg/etc/logrotate.d
    mkdir_p(File.join(rootdir, 'opt', 'tpkg', 'etc', 'logrotate.d'))
    ['web', 'app', 'db'].each do |appclass|
      cp(File.join(apppath, 'config', "logrotate-tpkg-#{appclass}"),
         File.join(rootdir, 'opt', 'tpkg', 'etc', 'logrotate.d', "tpkg-#{appclass}"))
    end
    
    @pkgfile = Tpkg::make_package(pkgdir)
    puts "Package is #{@pkgfile}"
    
    # Cleanup
    rm_rf(pkgdir)
  end
  
  desc 'Upload tpkg'
  task :upload => :build do
    puts "running tpkg_uploader"
    # system silently fails if the executable is not found or not executable,
    # some warning to the user might be nice.
    system("tpkg_uploader.rb --file #{@pkgfile}")
    rm(@pkgfile)
  end
  
  desc 'Deploy tpkg, e.g. rake tpkg:deploy[prod]'
  task :deploy, :env do |t, args|
    # Make sure we upgrade to the current version
    tpkg_xml = REXML::Document.new(File.open(File.join('config', 'tpkg.xml')))
    version = tpkg_xml.elements['/tpkg/version'].text
    version_request = "=#{version}"
    if tpkg_xml.elements['/tpkg/package_version']
      package_version = tpkg_xml.elements['/tpkg/package_version'].text
      version_request << "=#{package_version}"
    end
    deploy_params = ['--upgrade', "tpkg-server#{version_request}"]
    deploy_options = {'abort-on-fail' => false}
    servers = get_tpkg_servers_for_environment(args.env)
    Tpkg::deploy(deploy_params, deploy_options, servers)
  end
  
  desc 'Start tpkg, e.g. rake tpkg:start[prod]'
  task :start, :env do |t, args|
    deploy_params = ['--start', 'tpkg-server']
    deploy_options = {'abort-on-fail' => false}
    servers = get_tpkg_servers_for_environment(args.env)
    Tpkg::deploy(deploy_params, deploy_options, servers)
  end
  desc 'Stop tpkg, e.g. rake tpkg:stop[prod]'
  task :stop, :env do |t, args|
    deploy_params = ['--stop', 'tpkg-server']
    deploy_options = {'abort-on-fail' => false}
    servers = get_tpkg_servers_for_environment(args.env)
    Tpkg::deploy(deploy_params, deploy_options, servers)
  end
  desc 'Restart tpkg, e.g. rake tpkg:restart[prod]'
  task :restart, :env do |t, args|
    deploy_params = ['--restart', 'tpkg-server']
    deploy_options = {'abort-on-fail' => false}
    servers = get_tpkg_servers_for_environment(args.env)
    Tpkg::deploy(deploy_params, deploy_options, servers)
  end
  desc 'Reload tpkg, e.g. rake tpkg:reload[prod]'
  task :reload, :env do |t, args|
    deploy_params = ['--reload', 'tpkg-server']
    deploy_options = {'abort-on-fail' => false}
    servers = get_tpkg_servers_for_environment(args.env)
    Tpkg::deploy(deploy_params, deploy_options, servers)
  end
end

