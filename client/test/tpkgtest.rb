#
# Module of code shared by all of the tpkg test cases
#

$:.unshift(File.join(File.dirname(File.dirname(__FILE__)), 'thirdparty'))
$:.unshift(File.join(File.dirname(File.dirname(__FILE__)), 'lib'))
require 'test/unit'
require 'fileutils'
require 'tpkg'
require File.dirname(__FILE__) + '/tempdir'
require 'tempfile'
require 'facter'

Tpkg::set_debug(true) if ENV['debug']

module TpkgTests
  # Directory with test package contents
  TESTPKGDIR = File.join(File.dirname(__FILE__), 'testpkg')
  # Passphrase used for encrypting/decrypting packages
  PASSPHRASE = 'password'

  def create_metadata_file(filename, options={})
    format = :xml
    if options[:format]
      format = options[:format]
      # FIXME
      if format != :xml
        raise "Support for metadata file formats other than XML not yet implemented"
      end
    end
    change = {}
    if options[:change]
      change = options[:change]
    end
    remove = []
    if options[:remove]
      remove = options[:remove]
    end
    file_defaults = {}
    if options[:file_defaults]
      file_defaults = options[:file_defaults]
    end
    files = {}
    if options[:files]
      files = options[:files]
    end
    dependencies = {}
    if options[:dependencies]
      dependencies = options[:dependencies]
    end
    conflicts = {}
    if options[:conflicts]
      conflicts = options[:conflicts]
    end
    externals = {}
    if options[:externals]
      externals = options[:externals]
    end
    
    # FIXME:  We currently assume the specified filename exists and is a valid
    # template file that we make changes to.  Might want to rearchitect that
    # at some point.
    tpkgdst = Tempfile.new(File.basename(filename), File.dirname(filename))
    IO.foreach(filename) do |line|
      if line =~ /^\s*<(\w+)>/
        field = $1
        if change.has_key?(field)
          line.sub!(/^(\s*<\w+>).*(<\/\w+>)/, '\1' + change[$1] + '\2')
        elsif remove.include?(field)
          line = ''
        end
      end
      
      # Insert dependencies right before the files section
      if line =~ /^\s*<files>/ && !dependencies.empty?
        tpkgdst.puts('  <dependencies>')
        dependencies.each do |name, opts|
          tpkgdst.puts('    <dependency>')
          tpkgdst.puts("      <name>#{name}</name>")
          ['minimum_version', 'maximum_version', 'minimum_package_version', 'maximum_package_version'].each do |opt|
            if opts[opt]
              tpkgdst.puts("      <#{opt}>#{opts[opt]}</#{opt}>")
            end
          end
          if opts['native']
            tpkgdst.puts('      <native/>')
          end
          tpkgdst.puts('    </dependency>')
        end
        tpkgdst.puts('  </dependencies>')
      end

      # Insert conflicts right before the files section
      if line =~ /^\s*<files>/ && !conflicts.empty?
        tpkgdst.puts('  <conflicts>')
        conflicts.each do |name, opts|
          tpkgdst.puts('    <conflict>')
          tpkgdst.puts("      <name>#{name}</name>")
          ['minimum_version', 'maximum_version', 'minimum_package_version', 'maximum_package_version'].each do |opt|
            if opts[opt]
              tpkgdst.puts("      <#{opt}>#{opts[opt]}</#{opt}>")
            end
          end
          if opts['native']
            tpkgdst.puts('      <native/>')
          end
          tpkgdst.puts('    </conflict>')
        end
        tpkgdst.puts('  </conflicts>')
      end
      
      # Insert externals right before the files section
      if line =~ /^\s*<files>/ && !externals.empty?
        tpkgdst.puts('  <externals>')
        externals.each do |name, opts|
          tpkgdst.puts('    <external>')
          tpkgdst.puts("      <name>#{name}</name>")
          if opts['data']
            tpkgdst.puts("      <data>#{opts['data']}</data>")
          elsif opts['datafile']
            tpkgdst.puts("      <datafile>#{opts['datafile']}</datafile>")
          elsif opts['datascript']
            tpkgdst.puts("      <datascript>#{opts['datascript']}</datascript>")
          end
          tpkgdst.puts('    </external>')
        end
        tpkgdst.puts('  </externals>')
      end
      
      # Insert file_defaults settings at the end of the files section
      if line =~ /^\s*<\/files>/ && !file_defaults.empty?
        tpkgdst.puts('    <file_defaults>')
        if file_defaults['owner'] || file_defaults['group'] || file_defaults['perms']
          tpkgdst.puts('      <posix>')
          ['owner', 'group', 'perms'].each do |opt|
            if file_defaults[opt]
              tpkgdst.puts("        <#{opt}>#{file_defaults[opt]}</#{opt}>")
            end
          end
          tpkgdst.puts('      </posix>')
        end
        tpkgdst.puts('    </file_defaults>')
      end
      
      # Insert additional file entries at the end of the files section
      if line =~ /^\s*<\/files>/ && !files.empty?
        files.each do |path, opts|
          tpkgdst.puts('    <file>')
          tpkgdst.puts("      <path>#{path}</path>")
          if opts['owner'] || opts['group'] || opts['perms']
            tpkgdst.puts('      <posix>')
            ['owner', 'group', 'perms'].each do |opt|
              if opts[opt]
                tpkgdst.puts("        <#{opt}>#{opts[opt]}</#{opt}>")
              end
            end
            tpkgdst.puts('      </posix>')
          end
          if opts['config']
            tpkgdst.puts('      <config/>')
          end
          if opts['encrypt']
            if opts['encrypt'] = 'precrypt'
              tpkgdst.puts('      <encrypt precrypt="true"/>')
            else
              tpkgdst.puts('      <encrypt/>')
            end
          end
          if opts['init']
            tpkgdst.puts('      <init>')
            if opts['init']['start']
              tpkgdst.puts("        <start>#{opts['init']['start']}</start>")
            end
            if opts['init']['levels']
              tpkgdst.puts("        <levels>#{opts['init']['levels']}</levels>")
            end
            tpkgdst.puts('      </init>')
          end
          if opts['crontab']
            if opts['crontab']['user']
              tpkgdst.puts("      <crontab><user>#{opts['crontab']['user']}</user></crontab>")
            else
              tpkgdst.puts('      <crontab/>')
            end
          end
          tpkgdst.puts('    </file>')
        end
      end
      
      tpkgdst.write(line)
    end
    tpkgdst.close
    File.rename(tpkgdst.path, filename)
  end
  
  # Make up our regular test package, substituting any fields and adding
  # dependencies as requested by the caller
  def make_package(options={})
    source_directory = TESTPKGDIR
    if options[:source_directory]
      source_directory = options[:source_directory]
    end
    output_directory = nil
    if options[:output_directory]
      output_directory = options[:output_directory]
    end
    passphrase = PASSPHRASE
    if options[:passphrase]
      passphrase = options[:passphrase]
    end
    
    pkgdir = Tempdir.new('make_package')
    
    # Copy package contents into working directory
    system("#{Tpkg::find_tar} -C #{source_directory} --exclude .svn -cf - . | #{Tpkg::find_tar} -C #{pkgdir} -xpf -")
    
    create_metadata_file(File.join(pkgdir, 'tpkg.xml'), options)
    pkgfile = Tpkg.make_package(pkgdir, passphrase, options)
    FileUtils.rm_rf(pkgdir)
    
    # move the pkgfile to designated directory (if user specifies it)
    if output_directory
      FileUtils.mkdir_p(output_directory)
      FileUtils.move(pkgfile, output_directory)
      pkgfile = File.join(output_directory, File.basename(pkgfile))
    end
    
    pkgfile
  end
  
end

