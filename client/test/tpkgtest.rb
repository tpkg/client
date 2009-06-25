#
# Module of code shared by all of the tpkg test cases
#

$:.unshift('..')
require 'tpkg'
require 'tempdir'

Tpkg::set_debug(true)

module TpkgTests
  # Passphrase used for encrypting/decrypting packages
  PASSPHRASE = 'password'
  
  # Haven't found a Ruby method for creating temporary directories,
  # so create a temporary file and replace it with a directory.
  def tempdir
    tmpfile = Tempfile.new('tpkgtest')
    tmpdir = tmpfile.path
    tmpfile.close!
    Dir.mkdir(tmpdir)
    tmpdir
  end
  
  # Make up our regular test package, substituting any fields and adding
  # dependencies as requested by the caller
  def make_package(options={})
    change = {}
    if options[:change]
      change = options[:change]
    end
    remove = []
    if options[:remove]
      remove = options[:remove]
    end
    files = {}
    if options[:files]
      files = options[:files]
    end
    dependencies = {}
    if options[:dependencies]
      dependencies = options[:dependencies]
    end
    source_directory = 'testpkg'
    if options[:source_directory]
      source_directory = options[:source_directory]
    end
    passphrase = PASSPHRASE
    if options[:passphrase]
      passphrase = options[:passphrase]
    end
    if options[:output_directory]
      output_directory = options[:output_directory]
    end
    
    pkgdir = tempdir
    
    # Copy package contents into working directory
    system("#{Tpkg::find_tar} -C #{source_directory} --exclude .svn -cf - . | #{Tpkg::find_tar} -C #{pkgdir} -xpf -")
    
    # Prep tpkg.xml
    File.open(File.join(pkgdir, 'tpkg.xml.new'), 'w') do |tpkgdst|
      IO.foreach(File.join(pkgdir, 'tpkg.xml')) do |line|
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
    end
    File.rename(File.join(pkgdir, 'tpkg.xml.new'), File.join(pkgdir, 'tpkg.xml'))
    
    pkgfile = Tpkg.make_package(pkgdir, passphrase)
    FileUtils.rm_rf(pkgdir)

    # move the pkgfile to designated directory (if user specifies it)
    if !output_directory.nil?
      FileUtils.move(pkgfile, output_directory) 
      return File.join(output_directory, File.basename(pkgfile))
    else
      return pkgfile
    end
  end
  
end

