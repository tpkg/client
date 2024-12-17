##############################################################################
# tpkg package management system
# License: MIT (http://www.opensource.org/licenses/mit-license.php)
##############################################################################

STDOUT.sync = STDERR.sync = true # All outputs/prompts to the kernel ASAP

# Exclude standard libraries and gems from the warnings induced by
# running ruby with the -w flag.  Several of these have warnings under
# ruby 1.9 and there's nothing we can do to fix that.
require 'tpkg/silently'
Silently.silently do
  require 'digest/sha2'    # Digest::SHA256#hexdigest, etc.
  require 'etc'            # Etc.getpwnam, getgrnam
  require 'fileutils'      # FileUtils.cp, rm, etc.
  require 'find'           # Find
  require 'net/http'       # Net::HTTP
  require 'net/https'      # Net::HTTP#use_ssl, etc.
  require 'openssl'        # OpenSSL
  require 'open3'          # Open3
  require 'set'            # Enumerable#to_set
  require 'rexml/document' # REXML::Document
  require 'stringio'       # StringIO
  require 'tempfile'       # Tempfile
  require 'time'           # Time#httpdate
  require 'uri'            # URI
  require 'yaml'           # YAML
end

OpenSSLCipherError = OpenSSL::Cipher.const_defined?(:CipherError) ? OpenSSL::Cipher::CipherError : OpenSSL::CipherError

class Tpkg
  require 'tpkg/deployer'
  require 'tpkg/metadata'
  require 'tpkg/versiontype'
  require 'tpkg/os'
  require 'tpkg/version'

  GENERIC_ERR = 1
  POSTINSTALL_ERR = 2
  POSTREMOVE_ERR = 3
  INITSCRIPT_ERR = 4

  CONNECTION_TIMEOUT = 10

  DEFAULT_OWNERSHIP_UID = 0
  DEFAULT_OWNERSHIP_GID = 0
  DEFAULT_FILE_PERMS = nil
  DEFAULT_DIR_PERMS = 0755

  #
  # Class methods
  #

  @@debug = false
  def self.set_debug(debug)
    @@debug = debug
  end

  @@prompt = true
  def self.set_prompt(prompt)
    @@prompt = prompt
  end

  # Find GNU tar or bsdtar in ENV['PATH']
  # Raises an exception if a suitable tar cannot be found
  @@tar = nil
  @@taroptions = ""
  @@tarinfo = {:version => 'unknown'}
  TARNAMES = ['tar', 'gtar', 'gnutar', 'bsdtar']
  def self.find_tar
    if !@@tar
      catch :tar_found do
        if !ENV['PATH']
          raise "tpkg cannot run because the PATH env variable is not set."
        end
        ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
          TARNAMES.each do |tarname|
            tarpath = nil
            if RUBY_PLATFORM == 'i386-mingw32'
              # Turns out that File.join is fairly pointless, at least as far
              # as Windows compatibility.  Ruby always uses '/' as the path
              # separator, even on Windows.  I.e. File::SEPARATOR is '/' on
              # Windows (yes, really!).  File::ALT_SEPARATOR is '\' but
              # File.join and its ilk will never use it.  The forward slash
              # works fine for API-level file operations, Windows will accept
              # either forward slashes or backslashes at the API level. But
              # you can't execute a path with forward slashes, apparently due
              # to some backwards-compatibility thing with cmd.exe. Sigh.
              tarpath = path.gsub('/', '\\') + '\\' + tarname + '.exe'
            else
              tarpath = File.join(path, tarname)
            end
            if File.executable?(tarpath)
              # Particularly on Windows it is possible that the path contains
              # spaces.  I.e. C:\Program Files (x86)\GnuWin32\bin\bsdtar.exe
              # It looks like that needs to be wrapped in quotes to execute
              # properly.
              if tarpath.include?(' ')
                tarpath = '"' + tarpath + '"'
              end
              Open3.popen3("#{tarpath} --version") do |stdin, stdout, stderr|
                stdin.close
                stdout.each_line do |line|
                  if line.include?('GNU tar')
                    @@tarinfo[:type] = 'gnu'
                    @@tar = tarpath
                  elsif line.include?('bsdtar')
                    @@tarinfo[:type] = 'bsd'
                    @@tar = tarpath
                  end
                  if line =~ /(?:(\d+)\.)?(?:(\d+)\.)?(\*|\d+)/
                    @@tarinfo[:version] = [$1, $2, $3].compact.join(".")
                  end
                  throw :tar_found if @@tar
                end
              end
            end
          end
        end
        raise "Unable to find GNU tar or bsdtar in PATH"
      end
    end
    # bsdtar uses pax format by default. This format allows for vendor extensions, such
    # as the SCHILY.* extensions which were introduced by star). bsdtar actually uses
    # these extensions. These extension headers includde useful, but not vital information.
    # gnu tar should just ignore them and gives a warning. This is what the latest gnu tar
    # will do. However, on older gnu tar, it only threw an error at the end. The work
    # around is to explicitly tell gnu tar to ignore those extensions.
    if @@tarinfo[:type] == 'gnu' && @@tarinfo[:version] != 'unknown' && @@tarinfo[:version] >= '1.15.1'
      @@taroptions = "--pax-option='delete=SCHILY.*,delete=LIBARCHIVE.*'"
    end
    @@tar.dup
  end
  def self.clear_cached_tar
    @@tar = nil
    @@taroptions = ""
    @@tarinfo = {:version => 'unknown'}
  end

  # Encrypts the given file in-place (the plaintext file is replaced by the
  # encrypted file).  The resulting file is compatible with openssl's 'enc'
  # utility.
  # Algorithm from http://www.ruby-forum.com/topic/101936#225585
  MAGIC = 'Salted__'
  SALT_LEN = 8
  @@passphrase = nil
  def self.encrypt(pkgname, filename, passphrase, cipher='aes-256-cbc')
    # passphrase can be a callback Proc, call it if that's the case
    pass = nil
    if @@passphrase
      pass = @@passphrase
    elsif passphrase.kind_of?(Proc)
      pass = passphrase.call(pkgname)
      @@passphrase = pass
    else
      pass = passphrase
    end

    # special handling for directory
    if File.directory?(filename)
      Find.find(filename) do |f|
        encrypt(pkgname, f, pass, cipher) if File.file?(f)
      end
      return
    end

    salt = OpenSSL::Random::random_bytes(SALT_LEN)
    c = OpenSSL::Cipher::Cipher.new(cipher)
    c.encrypt
    c.pkcs5_keyivgen(pass, salt, 1)
    tmpfile = Tempfile.new(File.basename(filename), File.dirname(filename))
    # Match permissions and ownership of plaintext file
    st = File.stat(filename)
    File.chmod(st.mode & 07777, tmpfile.path)
    begin
      File.chown(st.uid, st.gid, tmpfile.path)
    rescue Errno::EPERM
      raise if Process.euid == 0
    rescue Errno::EINVAL
      raise if RUBY_PLATFORM != 'i386-cygwin'
    end
    tmpfile.write(MAGIC)
    tmpfile.write(salt)
    content = IO.read(filename)
    tmpfile.write(c.update(content) + c.final) unless content.empty?
    tmpfile.close
    File.rename(tmpfile.path, filename)
  end

  # Decrypt the given file in-place.
  def self.decrypt(pkgname, filename, passphrase, cipher='aes-256-cbc')
    # passphrase can be a callback Proc, call it if that's the case
    pass = nil
    if @@passphrase
      pass = @@passphrase
    elsif passphrase.kind_of?(Proc)
      pass = passphrase.call(pkgname)
      @@passphrase = pass
    else
      pass = passphrase
    end

    if File.directory?(filename)
      Find.find(filename) do |f|
        decrypt(pkgname, f, pass, cipher) if File.file?(f)
      end
      return
    end

    file = File.open(filename)
    if (buf = file.read(MAGIC.length)) != MAGIC
      raise "Unrecognized encrypted file #{filename}"
    end
    salt = file.read(SALT_LEN)
    c = OpenSSL::Cipher::Cipher.new(cipher)
    c.decrypt
    c.pkcs5_keyivgen(pass, salt, 1)
    tmpfile = Tempfile.new(File.basename(filename), File.dirname(filename))
    # Match permissions and ownership of encrypted file
    st = File.stat(filename)
    File.chmod(st.mode & 07777, tmpfile.path)
    begin
      File.chown(st.uid, st.gid, tmpfile.path)
    rescue Errno::EPERM
      raise if Process.euid == 0
    rescue Errno::EINVAL
      raise if RUBY_PLATFORM != 'i386-cygwin'
    end
    content = file.read
    tmpfile.write(c.update(content) + c.final) unless content.empty?
    tmpfile.close
    File.rename(tmpfile.path, filename)
  end
  def self.verify_precrypt_file(filename)
    # This currently just verifies that the file seems to start with the
    # right bits.  Any further verification would require the passphrase
    # and cipher so we could decrypt the file, but that would preclude
    # folks from including precrypt files for which they don't have the
    # passphrase in a package.  In some environments it might be desirable
    # for folks to be able to build the package even if they couldn't
    # install it.
    file = File.open(filename)
    if (buf = file.read(MAGIC.length)) != MAGIC
      raise "Unrecognized encrypted file #{filename}"
    end
    true
  end

  # Makes a package from a directory containing the files to put into the package
  def self.make_package(pkgsrcdir, passphrase=nil, options = {})
    pkgfile = nil

    # validate the output directory if the user has specified one
    outdir = options[:out]
    if outdir
      outdir = File.expand_path(outdir)
      if !File.directory?(outdir)
        raise "#{outdir} is not a valid directory"
      elsif !File.writable?(outdir)
        raise "#{outdir} is not writable"
      end
    end

    # Make a working directory
    workdir = nil
    # dirname('.') returns '.', which screws things up.  So in cases
    # where the user passed us a directory that doesn't have enough
    # parts that we can get the parent directory we use a working
    # directory in the system's temp area.  As an alternative we could
    # use Pathname.realpath to convert whatever the user passed us into
    # an absolute path.
    if File.dirname(pkgsrcdir) == pkgsrcdir
      workdir = tempdir('tpkg')
    else
      workdir = tempdir('tpkg', File.dirname(pkgsrcdir))
    end
    begin
      # Make the 'tpkg' directory for storing the package contents
      tpkgdir = File.join(workdir, 'tpkg')
      Dir.mkdir(tpkgdir)

      # A package really shouldn't be partially relocatable, warn the user if
      # they're creating such a scourge.
      if (File.exist?(File.join(pkgsrcdir, 'root')) && File.exist?(File.join(pkgsrcdir, 'reloc')))
        warn 'Warning: Your source directory should contain either a "root" or "reloc" directory, but not both.'
      end

      # Copy the package contents into that directory
      # I tried to use FileUtils.cp_r but it doesn't handle symlinks properly
      # And on further reflection it makes sense to only have one chunk of
      # code (tar) ever touch the user's files.
      system("#{find_tar} -C #{pkgsrcdir} -cf - . | #{find_tar} -C #{tpkgdir} -xpf -") || raise("Package content copy failed")

      # check metadata file
      errors = []
      metadata = Metadata::instantiate_from_dir(tpkgdir)
      if !metadata
        raise 'Your source directory does not contain the metadata configuration file.'
      end

      # This is for when we're in developement mode or when installed as gem
      if File.exists?(File.join(File.dirname(File.dirname(__FILE__)), "schema"))
        schema_dir = File.join(File.dirname(File.dirname(__FILE__)), "schema")
      # This is the directory where we put our dtd/schema for validating
      # the metadata file
      # FIXME: This method should become an instance method and use @configdir
      elsif File.exist?(File.join(DEFAULT_CONFIGDIR, 'tpkg', 'schema'))
        schema_dir = File.join(DEFAULT_CONFIGDIR, 'tpkg', 'schema')
      else
        warn "Warning: unable to find schema for tpkg.yml"
      end

      errors = metadata.validate(schema_dir) if schema_dir
      if errors && !errors.empty?
        puts "Bad metadata file. Possible error(s):"
        errors.each {|e| puts e }
        raise "Failed to create package."  unless options[:force]
      end

      # file_metadata hold information for files that are installed
      # by the package. For example, checksum, path, relocatable or not, etc.
      File.open(File.join(tpkgdir, "file_metadata.bin"), "w") do |file|
        filemetadata = get_filemetadata_from_directory(tpkgdir)
        filemetadata[:files].each do |file1|
          if metadata[:files] && metadata[:files][:files] &&
             metadata[:files][:files].any?{|file2|file2[:path] == file1[:path] && file2[:config]}
            file1[:config] = true
          end
        end
        data = filemetadata.to_hash.recursively{|h| h.stringify_keys }
        Marshal::dump(data, file)
      end

      # Check all the files are there as specified in the metadata config file
      metadata[:files][:files].each do |tpkgfile|
        tpkg_path = tpkgfile[:path]
        working_path = nil
        if tpkg_path[0,1] == File::SEPARATOR
          working_path = File.join(tpkgdir, 'root', tpkg_path)
        else
          working_path = File.join(tpkgdir, 'reloc', tpkg_path)
        end
        # Raise an exception if any files listed in tpkg.yml can't be found
        if !File.exist?(working_path) && !File.symlink?(working_path)
          raise "File #{tpkg_path} referenced in tpkg.yml but not found"
        end

        # check permission/ownership of cron.d-style crontab files
        if tpkgfile[:crontab] && !tpkgfile[:crontab][:user]
          data = {:actual_file => working_path, :metadata => metadata, :file_metadata => tpkgfile}
          perms, uid, gid = predict_file_perms_and_ownership(data)
          # crontab needs to be owned by root, and is not writable by group or others
          if uid != 0
            warn "Warning: Your cron jobs in \"#{tpkgfile[:path]}\" might fail to run because the file is not owned by root."
          end
          if (perms & 0022) != 0
            warn "Warning: Your cron jobs in \"#{tpkgfile[:path]}\" might fail to run because the file is writable by group and/or others."
          end
        end

        # Encrypt any files marked for encryption
        if tpkgfile[:encrypt]
          if tpkgfile[:encrypt][:precrypt]
            verify_precrypt_file(working_path)
          else
            if passphrase.nil?
              raise "Package requires encryption but supplied passphrase is nil"
            end
            encrypt(metadata[:name], working_path, passphrase, *([tpkgfile[:encrypt][:algorithm]].compact))
          end
        end
      end unless metadata[:files].nil? or metadata[:files][:files].nil?

      package_filename = metadata.generate_package_filename
      package_directory = File.join(workdir, package_filename)
      Dir.mkdir(package_directory)

      if outdir
        pkgfile = File.join(outdir, package_filename + '.tpkg')
      else
        pkgfile = File.join(File.dirname(pkgsrcdir), package_filename + '.tpkg')
      end

      if File.exist?(pkgfile) || File.symlink?(pkgfile)
        if @@prompt
          print "Package file #{pkgfile} already exists, overwrite? [y/N]"
          response = $stdin.gets
          if response !~ /^y/i
            return
          end
        end
        File.delete(pkgfile)
      end

      # update metadata file with the tpkg version
      begin
        metadata.add_tpkg_version(VERSION)
      rescue Errno::EACCES => e
        # The source directory from which the package is made may not be
        # writeable by the user making the package.  It is not critical that
        # the tpkg version get added to the package metadata, so just warn the
        # user if that happens.
        warn "Failed to insert tpkg_version into tpkg.(xml|yml): #{e.message}"
      end

      # Tar up the tpkg directory
      tpkgfile = File.join(package_directory, 'tpkg.tar')
      system("#{find_tar} -C #{workdir} -cf #{tpkgfile} tpkg") || raise("tpkg.tar creation failed")

      # Checksum the tarball
      digest = Digest::SHA256.hexdigest(File.read(tpkgfile))

      # Create checksum.xml
      File.open(File.join(package_directory, 'checksum.xml'), 'w') do |csx|
        csx.puts('<tpkg_checksums>')
        csx.puts('  <checksum>')
        csx.puts('    <algorithm>SHA256</algorithm>')
        csx.puts("    <digest>#{digest}</digest>")
        csx.puts('  </checksum>')
        csx.puts('</tpkg_checksums>')
      end

      # compress if needed
      if options[:compress]
        tpkgfile = compress_file(tpkgfile, options[:compress])
      end

      # Tar up checksum.xml and the main tarball
      system("#{find_tar} -C #{workdir} -cf #{pkgfile} #{package_filename}") || raise("Final package creation failed")
    ensure
      # Remove our working directory
      FileUtils.rm_rf(workdir)
    end

    # Return the filename of the package
    pkgfile
  end

  def self.package_toplevel_directory(package_file)
    # This assumes the first entry in the tarball is the top level directory.
    # I think that is a safe assumption.
    toplevel = nil
    # We need one or more 512 byte tar blocks from the file to get the first
    # filename.  In most cases we'll just need one block, but if the top-level
    # directory has an exceptionally long name it may be spread over multiple
    # blocks.  The trick is that we don't want any additional blocks because
    # that will confuse tar and it will report that the archive is damaged.
    # So start with one block and go up to an arbitrarily picked limit of 10
    # blocks (I've been unable to make a test tarball that needed more than 3
    # blocks) and see if tar succeeds in listing a file.
    1.upto(10) do |numblocks|
      tarblocks = File.read(package_file, 512*numblocks)
      Open3.popen3("#{find_tar} -tf - #{@@taroptions}") do |stdin, stdout, stderr|
        stdin.write(tarblocks)
        stdin.close
        toplevel = stdout.read
      end
      if !toplevel.empty?
        break
      else
        toplevel = nil
      end
    end
    if toplevel.nil?
      raise "Error reading top level directory from #{package_file}"
    end
    toplevel.chomp!
    # Strip off the trailing slash
    toplevel.sub!(Regexp.new("#{File::SEPARATOR}$"), '')
    if toplevel.include?(File::SEPARATOR)
      raise "Package directory structure of #{package_file} unexpected, top level is more than one directory deep"
    end
    toplevel
  end

  # Takes the path to the 'tpkg' directory of an unpacked package and returns
  # an array of the top level directories that exist for package files within
  # that directory.  Currently that is one or both of 'reloc' for relocatable
  # files and 'root' for non-relocatable files.
  def self.get_package_toplevels(tpkgdir)
    toplevels = []
    ['reloc', 'root'].each do |toplevel|
      if File.directory?(File.join(tpkgdir, toplevel))
        toplevels << File.join(tpkgdir, toplevel)
      end
    end
    toplevels
  end

  def self.get_filemetadata_from_directory(tpkgdir)
    filemetadata = {}
    root_dir = File.join(tpkgdir, "root")
    reloc_dir = File.join(tpkgdir, "reloc")
    files = []

    Find.find(*get_package_toplevels(tpkgdir)) do |f|
      relocatable = false

      # Append file separator at the end for directory
      if File.directory?(f)
        f += File::SEPARATOR
      end

      # check if it's from root dir or reloc dir
      if f =~ /^#{Regexp.escape(root_dir)}/
        short_fn = f[root_dir.length ..-1]
      else
        short_fn = f[reloc_dir.length + 1..-1]
        relocatable = true
      end

      next if short_fn.nil? or short_fn.empty?

      file = {}
      file[:path] = short_fn
      file[:relocatable] = relocatable

      # only do checksum for file
      if File.file?(f)
        digest = Digest::SHA256.hexdigest(File.read(f))
        file[:checksum] = {:algorithm => "SHA256", :digests => [{:value => digest}]}
      end
      files << file
    end
    filemetadata['files'] = files
    #return FileMetadata.new(YAML::dump(filemetadata),'yml')
    return FileMetadata.new(Marshal::dump(filemetadata),'bin')
  end

  def self.verify_package_checksum(package_file, options = {})
    topleveldir = options[:topleveldir] || package_toplevel_directory(package_file)
    # Extract checksum.xml from the package
    checksum_xml = nil
    IO.popen("#{find_tar} #{@@taroptions} -xf #{package_file} -O #{File.join(topleveldir, 'checksum.xml')}") do |pipe|
      checksum_xml = REXML::Document.new(pipe.read)
    end
    if !$?.success?
      raise "Error extracting checksum.xml from #{package_file}"
    end

    # Verify checksum.xml
    checksum_xml.elements.each('/tpkg_checksums/checksum') do |checksum|
      digest = nil
      algorithm = checksum.elements['algorithm'].text
      digest_from_package = checksum.elements['digest'].text
      case algorithm
      when 'SHA224'
        digest = Digest::SHA224.new
      when 'SHA256'
        digest = Digest::SHA256.new
      when 'SHA384'
        digest = Digest::SHA384.new
      when 'SHA512'
        digest = Digest::SHA512.new
      else
        raise("Unrecognized checksum algorithm #{checksum.elements['algorithm']}")
      end
      # Extract tpkg.tar from the package and digest it
      extract_tpkg_tar_command = cmd_to_extract_tpkg_tar(package_file, topleveldir)
      IO.popen(extract_tpkg_tar_command) do |pipe|
      #IO.popen("#{find_tar} -xf #{package_file} -O #{File.join(topleveldir, 'tpkg.tar')} #{@@taroptions}") do |pipe|
        # Package files can be quite large, so we digest the package in
        # chunks.  A survey of the Internet turns up someone who tested
        # various chunk sizes on various platforms and found 4k to be
        # consistently the best.  I'm too lazy to do my own testing.
        # http://groups.google.com/group/comp.lang.ruby/browse_thread/thread/721d304fc8a5cc71
        while buf = pipe.read(4096)
          digest << buf
        end
      end
      if !$?.success?
        raise "Error extracting tpkg.tar from #{package_file}"
      end
      if digest != digest_from_package
        raise "Checksum mismatch for #{algorithm}, #{digest} != #{digest_from_package}"
      end
    end
  end

  # Extracts and returns the metadata from a package file
  def self.metadata_from_package(package_file, options = {})
    topleveldir = options[:topleveldir] || package_toplevel_directory(package_file)
    # Verify checksum
    verify_package_checksum(package_file)
    # Extract and parse tpkg.xml
    metadata = nil
    ['yml','xml'].each do |format|
      file = File.join('tpkg', "tpkg.#{format}")

      # use popen3 instead of popen because popen display stderr when there's an error such as
      # tpkg.yml not being there, which is something we want to ignore since old tpkg doesn't
      # have tpkg.yml file
      extract_tpkg_tar_command = cmd_to_extract_tpkg_tar(package_file, topleveldir)
      stdin, stdout, stderr = Open3.popen3("#{extract_tpkg_tar_command} | #{find_tar} -xf - -O #{file}")
      filecontent = stdout.read
      if filecontent.nil? or filecontent.empty?
        next
      else
        metadata = Metadata.new(filecontent, format)
        break
      end
    end
    unless metadata
      raise "Failed to extract metadata from #{package_file}"
    end

    # Insert an attribute on the root element with the package filename
    metadata[:filename] = File.basename(package_file)
    return metadata
  end

  # Extracts and returns the metadata from a directory of package files
  def self.metadata_from_directory(directory)
    metadata = []

    # if metadata.xml already exists, then go ahead and
    # parse it
    existing_metadata_file = File.join(directory, 'metadata.yml')
    existing_metadata = {}

    if File.exists?(existing_metadata_file)
      metadata_lists = File.read(File.join(directory, 'metadata.yml')).split("---")
      metadata_lists.each do | metadata_text |
        if metadata_text =~ /^:?filename:(.+)/
           filename = $1.strip
           existing_metadata[filename] = Metadata.new(metadata_text,'yml')
        end
      end
    end

    # Populate the metadata array with metadata for all of the packages
    # in the given directory. Reuse existing metadata if possible.
    Dir.glob(File.join(directory, '*.tpkg')) do |pkg|
      if existing_metadata[File.basename(pkg)]
        metadata << existing_metadata[File.basename(pkg)]
      else
        metadata_yml = metadata_from_package(pkg)
        metadata << metadata_yml
      end
    end

    return metadata
  end

  # Extracts the metadata from a directory of package files and saves it
  # to metadata.xml in that directory
  def self.extract_metadata(directory, dest=nil)
    dest = directory if dest.nil?
    metadata = metadata_from_directory(directory)
    # And write that out to metadata.yml
    metadata_tmpfile = Tempfile.new('metadata.yml', dest)
    metadata.each do | m |
      YAML::dump(m.to_hash.recursively{|h| h.stringify_keys }, metadata_tmpfile)
      #YAML::dump(m.to_hash, metadata_tmpfile)
    end
    metadata_tmpfile.close
    File.chmod(0644, metadata_tmpfile.path)
    File.rename(metadata_tmpfile.path, File.join(dest, 'metadata.yml'))
  end

  # Ruby 1.8.7 and later have Dir.mktmpdir, but we support ruby 1.8.5 for
  # RHEL/CentOS 5.  So this is a basic substitute.
  # FIXME: consider "backport" for Dir.mktmpdir like we use in the test suite
  def self.tempdir(basename, tmpdir=Dir::tmpdir)
    tmpfile = Tempfile.new(basename, tmpdir)
    tmpdir = tmpfile.path
    tmpfile.close!
    Dir.mkdir(tmpdir)
    tmpdir
  end

  # Backward compatibility method. Use tpkg.os.arch instead.
  @@arch = nil
  def self.get_arch
    @@arch = Tpkg::OS.create().arch if @@arch.nil?
    @@arch.dup
  end

  # Backward compatibility method. Use tpkg.os.os instead.
  @@os = nil
  def self.get_os
    @@os = Tpkg::OS.create().os if @@os.nil?
    @@os.dup
  end

  # Given an array of pkgs. Determine if any of those package
  # satisfy the requirement specified by req
  def packages_meet_requirement?(pkgs, req)
    pkgs.each do | pkg |
      return true if package_meets_requirement?(pkg, req)
    end
    return false
  end

  # pkg is a standard Hash format used in the library to represent an
  # available package
  # req is a standard Hash format used in the library to represent package
  # requirements
  def package_meets_requirement?(pkg, req)
    result = true
    puts "pkg_meets_req checking #{pkg.inspect} against #{req.inspect}" if @@debug
    metadata = pkg[:metadata]
    if req[:type] == :native && pkg[:source] != :native_installed && pkg[:source] != :native_available
      # A req for a native package must be satisfied by a native package
      puts "Package fails native requirement" if @@debug
      result = false
    elsif req[:filename]
      result = false if req[:filename] != metadata[:filename]
    elsif req[:type] == :tpkg &&
          (pkg[:source] == :native_installed || pkg[:source] == :native_available)
      # Likewise a req for a tpkg must be satisfied by a tpkg
      puts "Package fails non-native requirement" if @@debug
      result = false
    elsif metadata[:name] == req[:name]
      same_min_ver_req = false
      same_max_ver_req = false
      if req[:allowed_versions]
        version = metadata[:version]
        version = "#{version}-#{metadata[:package_version]}" if metadata[:package_version]
        if !File.fnmatch(req[:allowed_versions], version)
          puts "Package fails version requirement.)" if @@debug
          result = false
        end
      end
      if req[:minimum_version]
        pkgver = Version.new(metadata[:version])
        reqver = Version.new(req[:minimum_version])
        if pkgver < reqver
          puts "Package fails minimum_version (#{pkgver} < #{reqver})" if @@debug
          result = false
        elsif pkgver == reqver
          same_min_ver_req = true
        end
      end
      if req[:version_greater_than]
        pkgver = Version.new(metadata[:version])
        reqver = Version.new(req[:version_greater_than])
        if pkgver <= reqver
          puts "Package fails version_greater_than (#{pkgver} <= #{reqver})" if @@debug
          result = false
        end
      end
      if req[:maximum_version]
        pkgver = Version.new(metadata[:version])
        reqver = Version.new(req[:maximum_version])
        if pkgver > reqver
          puts "Package fails maximum_version (#{pkgver} > #{reqver})" if @@debug
          result = false
        elsif pkgver == reqver
          same_max_ver_req = true
        end
      end
      if req[:version_less_than]
        pkgver = Version.new(metadata[:version])
        reqver = Version.new(req[:version_less_than])
        if pkgver >= reqver
          puts "Package fails version_less_than (#{pkgver} >= #{reqver})" if @@debug
          result = false
        end
      end
      if same_min_ver_req && req[:minimum_package_version]
        pkgver = Version.new(metadata[:package_version])
        reqver = Version.new(req[:minimum_package_version])
        if pkgver < reqver
          puts "Package fails minimum_package_version (#{pkgver} < #{reqver})" if @@debug
          result = false
        end
      end
      if same_min_ver_req && req[:package_version_greater_than]
        pkgver = Version.new(metadata[:package_version])
        reqver = Version.new(req[:package_version_greater_than])
        if pkgver <= reqver
          puts "Package fails package_version_greater_than (#{pkgver} <= #{reqver})" if @@debug
          result = false
        end
      end
      if same_max_ver_req && req[:maximum_package_version]
        pkgver = Version.new(metadata[:package_version])
        reqver = Version.new(req[:maximum_package_version])
        if pkgver > reqver
          puts "Package fails maximum_package_version (#{pkgver} > #{reqver})" if @@debug
          result = false
        end
      end
      if same_max_ver_req && req[:package_version_less_than]
        pkgver = Version.new(metadata[:package_version])
        reqver = Version.new(req[:package_version_less_than])
        if pkgver >= reqver
          puts "Package fails package_version_less_than (#{pkgver} >= #{reqver})" if @@debug
          result = false
        end
      end
      # The empty? check ensures that a package with no operatingsystem
      # field matches all clients.
      if metadata[:operatingsystem] &&
         !metadata[:operatingsystem].empty? &&
         !metadata[:operatingsystem].include?(os.os) &&
         !metadata[:operatingsystem].any?{|mos| os.os =~ /#{mos}/}
        puts "Package fails operatingsystem" if @@debug
        result = false
      end
      # Same deal with empty? here
      if metadata[:architecture] &&
         !metadata[:architecture].empty? &&
         !metadata[:architecture].include?(os.arch) &&
         !metadata[:architecture].any?{|march| os.arch =~ /#{march}/}
        puts "Package fails architecture" if @@debug
        result = false
      end
    else
      puts "Package fails name" if @@debug
      result = false
    end
    if result
      puts "Package matches" if @@debug
    end
    result
  end

  # Define a block for sorting packages in order of desirability
  # Suitable for passing to Array#sort as array.sort(&SORT_PACKAGES)
  SORT_PACKAGES = lambda do |a,b|
    #
    # We first prepare all of the values we wish to compare
    #

    # Name
    aname = a[:metadata][:name]
    bname = b[:metadata][:name]
    # Currently installed
    # Conflicted about whether this belongs here or not, not sure if all
    # potential users of this sorting system would want to prefer currently
    # installed packages.
    acurrentinstall = 0
    if (a[:source] == :currently_installed || a[:source] == :native_installed) && a[:prefer] == true
      acurrentinstall = 1
    end
    bcurrentinstall = 0
    if (b[:source] == :currently_installed || b[:source] == :native_installed) && b[:prefer] == true
      bcurrentinstall = 1
    end
    # Version
    aversion = Version.new(a[:metadata][:version])
    bversion = Version.new(b[:metadata][:version])
    # Package version
    apkgver = Version.new(0)
    if a[:metadata][:package_version]
      apkgver = Version.new(a[:metadata][:package_version])
    end
    bpkgver = Version.new(0)
    if b[:metadata][:package_version]
      bpkgver = Version.new(b[:metadata][:package_version])
    end
    # OS
    #  Fewer OSs is better, but zero is least desirable because zero means
    #  the package works on all OSs (i.e. it is the most generic package).
    #  We prefer packages tuned to a particular set of OSs over packages
    #  that work everywhere on the assumption that the package that works
    #  on only a few platforms was tuned more specifically for those
    #  platforms.  We remap 0 to a big number so that the sorting works
    #  properly.
    aoslength = 0
    aoslength = a[:metadata][:operatingsystem].length if a[:metadata][:operatingsystem]
    if aoslength == 0
      # See comments above
      aoslength = 1000
    end
    boslength = 0
    boslength = b[:metadata][:operatingsystem].length if b[:metadata][:operatingsystem]
    if boslength == 0
      boslength = 1000
    end
    # Architecture
    #  Same deal here, fewer architectures is better but zero is least desirable
    aarchlength = 0
    aarchlength = a[:metadata][:architecture].length if a[:metadata][:architecture]
    if aarchlength == 0
      aarchlength = 1000
    end
    barchlength = 0
    barchlength = b[:metadata][:architecture].length if b[:metadata][:architecture]
    if barchlength == 0
      barchlength = 1000
    end
    # Prefer a currently installed package over an otherwise identical
    # not installed package even if :prefer==false as a last deciding
    # factor.
    acurrentinstallnoprefer = 0
    if a[:source] == :currently_installed || a[:source] == :native_installed
      acurrentinstallnoprefer = 1
    end
    bcurrentinstallnoprefer = 0
    if b[:source] == :currently_installed || b[:source] == :native_installed
      bcurrentinstallnoprefer = 1
    end

    #
    # Then compare
    #

    # The mixture of a's and b's in these two arrays may seem odd at first,
    # but for some fields bigger is better (versions) but for other fields
    # smaller is better.
    [aname, bcurrentinstall, bversion, bpkgver, aoslength,
     aarchlength, bcurrentinstallnoprefer] <=>
    [bname, acurrentinstall, aversion, apkgver, boslength,
     barchlength, acurrentinstallnoprefer]
  end

  def self.files_in_package(package_file, options = {})
    files = {:root => [], :reloc => []}

    # If the metadata_directory option is available, it means this package
    # has been installed and the file_metadata might be available in that directory.
    # If that's the case, then parse the file_metadata to get the file list. It's
    # much faster than extracting from the tar file
    if metadata_directory = options[:metadata_directory]
      package_name = File.basename(package_file, File.extname(package_file))
      file_metadata = FileMetadata::instantiate_from_dir(File.join(metadata_directory, package_name))
    end

    if file_metadata
      file_metadata[:files].each do |file|
        if file[:relocatable]
          files[:reloc] << file[:path]
        else
          files[:root] << file[:path]
        end
      end
    else
      file_lists = []
      topleveldir = package_toplevel_directory(package_file)
      extract_tpkg_tar_cmd = cmd_to_extract_tpkg_tar(package_file, topleveldir)
      IO.popen("#{extract_tpkg_tar_cmd} | #{find_tar} #{@@taroptions} -tf -") do |pipe|
        pipe.each do |file|
          file_lists << file.chomp!
        end
      end
      if !$?.success?
        raise "Extracting file list from #{package_file} failed"
      end

      file_lists.each do |file|
        if file =~ Regexp.new(File.join('tpkg', 'root'))
          files[:root] << file.sub(Regexp.new(File.join('tpkg', 'root')), '')
        elsif file =~ Regexp.new(File.join('tpkg', 'reloc', '.'))
          files[:reloc] << file.sub(Regexp.new(File.join('tpkg', 'reloc', '')), '')
        end
      end
    end

    files
  end

  def self.lookup_uid(user)
    uid = nil
    if user =~ /^\d+$/
      # If the user was specified as a numeric UID, use it directly.
      uid = user
    else
      # Otherwise attempt to look up the username to get a UID.
      # Default to UID 0 if the username can't be found.
      # TODO: Should we cache this info somewhere?
      begin
        pw = Etc.getpwnam(user)
        uid = pw.uid
      rescue ArgumentError
        puts "Package requests user #{user}, but that user can't be found.  Using UID 0."
        uid = 0
      end
    end

    uid.to_i
  end

  def self.lookup_gid(group)
    gid = nil
    if group =~ /^\d+$/
      # If the group was specified as a numeric GID, use it directly.
      gid = group
    else
      # Otherwise attempt to look up the group to get a GID.  Default
      # to GID 0 if the group can't be found.
      # TODO: Should we cache this info somewhere?
      begin
        gr = Etc.getgrnam(group)
        gid = gr.gid
      rescue ArgumentError
        puts "Package requests group #{group}, but that group can't be found.  Using GID 0."
        gid = 0
      end
    end

    gid.to_i
  end

  # foo
  # foo=1.0
  # foo=1.0=1
  # foo>1.0
  # foo<=1.0=2
  # foo<=1.0>=3
  # foo=1.0<=6
  # foo-1.0-1.tpkg
  def self.parse_request(request)
    req = {}
    # Note that the ordering in the regex is important.  <= and >= have to
    # appear before others so that they match rather than two separate matches
    # for the '>' and '=' characters.  I.e. '1>=2'.split(/(>=|>|=)/) ==
    # ['1', '>=', '2'] but '1>=2'.split(/(>|=|>=)/) == ['1', '>', '=', '2']
    parts = request.split(/(<=|>=|<|>|=)/)

    # upgrade/remove/query options could take package filenames
    # We're assuming that the filename ends in .tpkg and has a version number that starts
    # with a digit. For example: foo-1.0.tpkg, foo-bar-1.0-1.tpkg
    if request =~ /\.tpkg$/
      req = {:filename => request, :name => request.split(/-\d/)[0]}
    else
      if parts.length > 4 && parts[-3] =~ /^[\d\.]/ && parts[-1] =~ /^[\d\.]/
        package_version = parts.pop
        package_version_sign = parts.pop
        version = parts.pop
        version_sign = parts.pop

        case version_sign
        when '<'
          # E.g. foo<1.0
          req[:version_less_than] = version
        when '<='
          # E.g. foo<=1.0
          req[:maximum_version] = version
        when '='
          # E.g. foo=1.0
          req[:minimum_version] = version
          req[:maximum_version] = version
        when '>'
          # E.g. foo>1.0
          req[:version_greater_than] = version
        when '>='
          # E.g. foo>=1.0
          req[:minimum_version] = version
        end

        case package_version_sign
        when '<'
          # E.g. foo=1.0<2.0
          req[:package_version_less_than] = package_version
        when '<='
          # E.g. foo=1.0<=2.0
          req[:maximum_package_version] = package_version
        when '='
          # E.g. foo=1.0=2.0
          req[:minimum_package_version] = package_version
          req[:maximum_package_version] = package_version
        when '>'
          # E.g. foo=1.0>2.0
          req[:package_version_greater_than] = package_version
        when '>='
          # E.g. foo=1.0>=2.0
          req[:minimum_package_version] = package_version
        end
      elsif parts.length > 1 && parts[-1] =~ /^[\d\.]/
        version = parts.pop
        version_sign = parts.pop
        if version_sign == '=' && version.include?('*')
          req[:allowed_versions] = version
        else
          case version_sign
          when '<'
            # E.g. foo<1.0
            req[:version_less_than] = version
          when '<='
            # E.g. foo<=1.0
            req[:maximum_version] = version
          when '='
            # E.g. foo=1.0
            req[:minimum_version] = version
            req[:maximum_version] = version
          when '>'
            # E.g. foo>1.0
            req[:version_greater_than] = version
          when '>='
            # E.g. foo>=1.0
            req[:minimum_version] = version
          end
        end
      end
      req[:name] = parts.join('')
    end
    req[:type] = :tpkg
    req
  end

  # deploy_options is used for configuration the deployer. It is a map of option_names => option_values. Possible
  # options are: use-ssh-key, deploy-as, worker-count, abort-on-fail
  #
  # deploy_params is an array that holds the list of paramters that is used when invoking tpkg on to the remote
  # servers where we want to deploy to.
  #
  # servers is an array, a filename or a callback that list the remote servers where we want to deploy to
  def self.deploy(deploy_params, deploy_options, servers)
    servers.uniq!
    deployer = Deployer.new(deploy_options)
    deployer.deploy(deploy_params, servers)
  end

  # Given a pid, check if it is running
  def self.process_running?(pid)
    return false if pid.nil? or pid == ""
    begin
      Process.kill(0, pid.to_i)
    rescue Errno::ESRCH
      return false
    rescue => e
      puts e
      return true
    end
  end

  # Prompt user to confirm yes or no. Default to yes if user just hit enter without any input.
  def self.confirm
    while true
      print "Confirm? [Y/n] "
      response = $stdin.gets
      if response =~ /^n/i
        return false
      elsif response =~ /^y|^\s$/i
        return true
      end
    end
  end

  def self.extract_tpkg_metadata_file(package_file)
    result = ""
    workdir = ""
    begin
      topleveldir = Tpkg::package_toplevel_directory(package_file)
      workdir = Tpkg::tempdir(topleveldir)
      extract_tpkg_tar_command = cmd_to_extract_tpkg_tar(package_file, topleveldir)
      system("#{extract_tpkg_tar_command} | #{find_tar} #{@@taroptions} -C #{workdir} -xpf -")

      if File.exist?(File.join(workdir,"tpkg", "tpkg.yml"))
        metadata_file = File.join(workdir,"tpkg", "tpkg.yml")
      elsif File.exist?(File.join(workdir,"tpkg", "tpkg.xml"))
        metadata_file = File.join(workdir,"tpkg", "tpkg.xml")
      else
        raise "#{package_file} does not contain metadata configuration file."
      end
      result = File.read(metadata_file)
    rescue
      puts "Failed to extract package."
    ensure
      FileUtils.rm_rf(workdir) if workdir
    end
    return result
  end

  # The only restriction right now is that the file doesn't begin with "."
  def self.valid_pkg_filename?(filename)
    return File.basename(filename) !~ /^\./
  end

  # helper method for predicting the permissions and ownership of a file that
  # will be installed by tpkg. This is done by looking at:
  #  1) its current perms & ownership
  #  2) the file_defaults settings of the metadata file
  #  3) the explicitly defined settings in the corresponding file section of the metadata file
  def self.predict_file_perms_and_ownership(data)
    perms = uid = gid = nil

    # get current permission and ownership
    if data[:actual_file]
      stat = File.stat(data[:actual_file])
      perms = stat.mode
      # This is what we set the ownership to by default
      uid = DEFAULT_OWNERSHIP_UID
      gid = DEFAULT_OWNERSHIP_GID
    end

    # get default permission and ownership
    metadata = data[:metadata]
    if (metadata && metadata[:files] && metadata[:files][:file_defaults] && metadata[:files][:file_defaults][:posix])
      uid = Tpkg::lookup_uid(metadata[:files][:file_defaults][:posix][:owner]) if metadata[:files][:file_defaults][:posix][:owner]
      gid = Tpkg::lookup_gid(metadata[:files][:file_defaults][:posix][:group]) if metadata[:files][:file_defaults][:posix][:group]
      perms = metadata[:files][:file_defaults][:posix][:perms] if metadata[:files][:file_defaults][:posix][:perms]
    end

    # get explicitly defined permission and ownership
    file_metadata = data[:file_metadata]
    if file_metadata && file_metadata[:posix]
      uid = Tpkg::lookup_uid(file_metadata[:posix][:owner]) if file_metadata[:posix][:owner]
      gid = Tpkg::lookup_gid(file_metadata[:posix][:group]) if file_metadata[:posix][:group]
      perms = file_metadata[:posix][:perms] if file_metadata[:posix][:perms]
    end
    return perms, uid, gid
  end

  # Given a package file, figure out if tpkg.tar was compressed
  # Return what type of compression. If tpkg.tar wasn't compressed, then return nil.
  def self.get_compression(package_file)
    compression = nil
    IO.popen("#{find_tar} #{@@taroptions} -tf #{package_file}") do |pipe|
      pipe.each do |file|
        if file =~ /tpkg.tar.gz$/
          compression = "gzip"
        elsif file =~ /tpkg.tar.bz2$/
          compression = "bz2"
        end
      end
    end
    return compression
  end

  # Given a .tpkg file and the topleveldir, generate the command for
  # extracting tpkg.tar
  def self.cmd_to_extract_tpkg_tar(package_file, topleveldir)
    compression = get_compression(package_file)
    if compression == "gzip"
      cmd = "#{find_tar} #{@@taroptions} -xf #{package_file} -O #{File.join(topleveldir, 'tpkg.tar.gz')} | gunzip -c"
    elsif compression == "bz2"
      cmd = "#{find_tar} #{@@taroptions} -xf #{package_file} -O #{File.join(topleveldir, 'tpkg.tar.bz2')} | bunzip2 -c"
    else
      cmd = "#{find_tar} #{@@taroptions} -xf #{package_file} -O #{File.join(topleveldir, 'tpkg.tar')}"
    end
  end

  # Compresses the file using the compression type
  # specified by the compress flag
  # Returns the compressed file
  def self.compress_file(file, compress)
    if compress == true or compress == "gzip"
      result = "#{file}.gz"
      system("gzip #{file}")
    elsif compress == "bz2"
      result = "#{file}.bz2"
      system("bzip2 #{file}")
    else
      raise "Compression #{compress} is not supported"
    end
    if !$?.success? or !File.exists?(result)
      raise "Failed to compress the package"
    end
    return result
  end

  # Used where we wish to capture an exception and modify the message.  This
  # method returns a new exception with desired message but with the backtrace
  # from the original exception so that the backtrace info is not lost.  This
  # is necessary because Exception lacks a set_message method.
  def self.wrap_exception(e, message)
    eprime = e.exception(message)
    eprime.set_backtrace(e.backtrace)
    eprime
  end

  #
  # Instance methods
  #

  DEFAULT_BASE = '/opt/tpkg'
  DEFAULT_CONFIGDIR = '/etc'

  def initialize(options={})
    # Options
    @base = options[:base] ? options[:base] : DEFAULT_BASE
    # An array of filenames or URLs which point to individual package files
    # or directories containing packages and extracted metadata.
    @sources = []
    if options[:sources]
      @sources = options[:sources]
      # Clean up any URI sources by ensuring they have a trailing slash
      # so that they are compatible with URI::join
      @sources.map! do |source|
        if !File.exist?(source) && source !~ %r{/$}
          source << '/'
        end
        source
      end
    end
    @report_server = nil
    if options[:report_server]
      @report_server = options[:report_server]
    end
    @lockforce = false
    if options.has_key?(:lockforce)
      @lockforce = options[:lockforce]
    end
    @force =false
    if options.has_key?(:force)
      @force = options[:force]
    end

    @cmd_crontab = 'crontab'
    if options[:cmd_crontab]
      @cmd_crontab = options[:cmd_crontab]
    end

    @configdir = DEFAULT_CONFIGDIR

    @file_system_root = '/'  # Not sure if this needs to be more portable
    # This option is only intended for use by the test suite
    if options[:file_system_root]
      @file_system_root = options[:file_system_root]
      @base = File.join(@file_system_root, @base)
      @configdir = File.join(@file_system_root, @configdir)
    end

    # Various external scripts that we run might need to adjust things for
    # relocatable packages based on the base directory.  Set $TPKG_HOME so
    # those scripts know what base directory is being used.
    ENV['TPKG_HOME'] = @base

    # Other instance variables
    @metadata = {}
    @available_packages = {}
    @available_native_packages = {}
    @var_directory = File.join(@base, 'var', 'tpkg')
    if !File.exist?(@var_directory)
      begin
        FileUtils.mkdir_p(@var_directory)
      rescue Errno::EACCES
        raise if Process.euid == 0
      rescue Errno::EIO => e
        if os.os =~ /Darwin/
          # Try to help our Mac OS X users, otherwise this could be
          # rather confusing.
          warn "\nNote: /home is controlled by the automounter by default on Mac OS X.\n" +
            "You'll either need to disable that in /etc/auto_master or configure\n" +
            "tpkg to use a different base via tpkg.conf.\n"
        end
        raise e
      end
    end
    @installed_directory = File.join(@var_directory, 'installed')
    @metadata_directory = File.join(@installed_directory, 'metadata')
    @sources_directory = File.join(@var_directory, 'sources')
    @tmp_directory = File.join(@var_directory, 'tmp')
    @log_directory = File.join(@var_directory, 'logs')
    # It is important to create these dirs in correct order
    dirs_to_create = [@installed_directory, @metadata_directory, @sources_directory,
                      @tmp_directory, @log_directory]
    dirs_to_create.each do |dir|
      begin
        FileUtils.mkdir_p(dir)
      rescue Errno::EACCES
        raise if Process.euid == 0
      end
    end
    @tar = Tpkg::find_tar
    @external_directory = File.join(@file_system_root, 'usr', 'lib', 'tpkg', 'externals')
    @lock_directory = File.join(@var_directory, 'lock')
    @lock_pid_file = File.join(@lock_directory, 'pid')
    @locks = 0
    @installed_metadata = {}
    @available_packages_cache = {}
    @os = nil
  end

  attr_reader :base
  attr_reader :installed_directory
  attr_reader :sources
  attr_reader :report_server
  attr_reader :lockforce
  attr_reader :force
  attr_reader :file_system_root

  # This allows us to avoid creating an OS object (which is rather slow due to
  # Facter loading) unless it is needed.  Many tpkg operations don't require
  # an OS object, so it is nice to not spend the time creating one if it is
  # not needed.
  def os
    if !@os
      @os = Tpkg::OS.create(:debug => @@debug)
    end
    @os
  end

  def gethttp(uri)
    if uri.scheme != 'http' && uri.scheme != 'https'
      # It would be possible to add support for FTP and possibly
      # other things if anyone cares
      raise "Only http/https URIs are supported, got: '#{uri}'"
    end
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
      http.use_ssl = true
      if File.exist?(File.join(@configdir, 'tpkg', 'ca.pem'))
        http.ca_file = File.join(@configdir, 'tpkg', 'ca.pem')
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      elsif File.directory?(File.join(@configdir, 'tpkg', 'ca'))
        http.ca_path = File.join(@configdir, 'tpkg', 'ca')
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
    end
    http.start
    http
  end

  def source_to_local_directory(source)
    source_as_directory = source.gsub(/[^a-zA-Z0-9]/, '')
    File.join(@sources_directory, source_as_directory)
  end

  # One-time operations related to loading information about available
  # packages
  def prep_metadata
    if @metadata.empty?
      metadata = {}
      @sources.each do |source|
        if File.file?(source)
          metadata_yml = Tpkg::metadata_from_package(source)
          metadata_yml.source = source
          name = metadata_yml[:name]
          metadata[name] = [] if !metadata[name]
          metadata[name] << metadata_yml
        elsif source[0,1] == File::SEPARATOR || File.directory?(source)
          if File.directory?(source)
            if !File.exists?(File.join(source, 'metadata.yml'))
              warn "Source directory #{source} has no metadata.yml file. Try running tpkg -x #{source} first."
              next
            end
            metadata_contents = File.read(File.join(source, 'metadata.yml'))
            Metadata::get_pkgs_metadata_from_yml_doc(metadata_contents, metadata, source)
          else
            warn "Source directory #{source} does not exist, skipping."
          end
        else
          uri = http = localdate = remotedate = localdir = localpath = nil

          if !URI.parse(source).absolute?
            warn "Source #{source} is not a file, directory, or absolute URI, skipping"
            next
          end

          uri = URI.join(source, 'metadata.yml')
          http = gethttp(uri)

          # Calculate the path to the local copy of the metadata for this URI
          localdir = source_to_local_directory(source)
          localpath = File.join(localdir, 'metadata.yml')
          if File.exist?(localpath)
            localdate = File.mtime(localpath)
          end

          # get last modified time of the metadata file from the server
          response = http.head(uri.path)
          case response
          when Net::HTTPSuccess
            remotedate = Time.httpdate(response['Date'])
          else
            puts "Error fetching metadata from #{uri}: #{response.body}"
            response.error!  # Throws an exception
          end

          # Fetch the metadata if necessary
          metadata_contents = nil
          if !localdate || remotedate != localdate
            response = http.get(uri.path)
            case response
            when Net::HTTPSuccess
              metadata_contents = response.body
              remotedate = Time.httpdate(response['Date'])
              # Attempt to save a local copy, might not work if we're not
              # running with sufficient privileges
              begin
                FileUtils.mkdir_p(localdir)
                File.open(localpath, 'w') do |file|
                  file.puts(response.body)
                end
                File.utime(remotedate, remotedate, localpath)
              rescue Errno::EACCES
                raise if Process.euid == 0
              end
            else
              puts "Error fetching metadata from #{uri}: #{response.body}"
              response.error!  # Throws an exception
            end
          else
            metadata_contents = IO.read(localpath)
          end
          # This method will parse the yml doc and populate the metadata variable
          # with list of pkgs' metadata
          Metadata::get_pkgs_metadata_from_yml_doc(metadata_contents, metadata, source)
        end
      end
      @metadata = metadata
      if @@debug
        @sources.each do |source|
          count = metadata.inject(0) do |memo,m|
                    # metadata is a hash of pkgname => array of Metadata
                    # objects.
                    # Thus m is a 2 element array of [pkgname, array of
                    # Metadata objects]  And thus m[1] is the array of
                    # Metadata objects.
                    memo + m[1].select{|mo| mo.source == source}.length
                  end
          puts "Found #{count} packages from #{source}"
        end
      end
    end
  end

  # Populate our list of available packages for a given package name
  def load_available_packages(name=nil)
    prep_metadata

    if name
      if !@available_packages[name]
        packages = []
        if @metadata[name]
          @metadata[name].each do |metadata_obj|
            packages << { :metadata => metadata_obj,
                          :source => metadata_obj.source }
          end
        end
        @available_packages[name] = packages

        if @@debug
          puts "Loaded #{@available_packages[name].size} available packages for #{name}"
        end
      end
    else
      # Load all packages
      @metadata.each do |pkgname, metadata_objs|
        if !@available_packages[pkgname]
          packages = []
          metadata_objs.each do |metadata_obj|
            packages << { :metadata => metadata_obj,
                          :source => metadata_obj.source }
          end
          @available_packages[pkgname] = packages
        end
      end
    end
  end

  # Used by available_native_packages to stuff all the info about a
  # native package into a hash to match the structure we pass around
  # internally for tpkgs
  def self.pkg_for_native_package(name, version, package_version, source)
    metadata = {}
    metadata[:name] = name
    metadata[:version] = version
    metadata[:package_version] = package_version if package_version
    pkg = { :metadata => metadata, :source => source }
    if source == :native_installed
      pkg[:prefer] = true
    end
    pkg
  end

  def available_native_packages(pkgname)
    if @available_native_packages[pkgname]
      return @available_native_packages[pkgname]
    else
      native_packages = os.available_native_packages(pkgname)
      if @@debug
        nicount = native_packages.select{|pkg| pkg[:source] == :native_installed}.length
        nacount = native_packages.select{|pkg| pkg[:source] == :native_available}.length
        puts "Found #{nicount} installed native packages for #{pkgname}"
        puts "Found #{nacount} available native packages for #{pkgname}"
      end
      @available_native_packages[pkgname] = native_packages
    end
  end

  # Returns an array of metadata for installed packages
  def metadata_for_installed_packages
    metadata = {}
    if File.directory?(@installed_directory)
      Dir.foreach(@installed_directory) do |entry|
        next if entry == '.' || entry == '..' || entry == 'metadata' || !Tpkg::valid_pkg_filename?(entry)
        # Check the timestamp on the file to see if it is new or has
        # changed since we last loaded data
        timestamp = File.mtime(File.join(@installed_directory, entry))
        if @installed_metadata[entry] &&
           timestamp == @installed_metadata[entry][:timestamp]
          puts "Using cached installed metadata for #{entry}" if @@debug
          metadata[entry] = @installed_metadata[entry]
        else
          puts "Loading installed metadata from disk for #{entry}" if @@debug
          # Check to see if we already have a saved copy of the metadata
          # Originally tpkg just stored a copy of the package file in
          # @installed_directory and we had to extract the metadata
          # from the package file every time we needed it.  That was
          # determined to be too slow, so we now cache a copy of the
          # metadata separately.  However we may encounter installs by
          # old copies of tpkg and need to extract and cache the
          # metadata.
          package_metadata_dir =
            File.join(@metadata_directory,
                      File.basename(entry, File.extname(entry)))
          metadata_file = File.join(package_metadata_dir, "tpkg.yml")
          m = Metadata::instantiate_from_dir(package_metadata_dir)
          # No cached metadata found, we have to extract it ourselves
          # and save it for next time
          if !m
            m = Tpkg::metadata_from_package(
                  File.join(@installed_directory, entry))
            begin
              FileUtils.mkdir_p(package_metadata_dir)
              File.open(metadata_file, "w") do |file|
                YAML::dump(m.to_hash, file)
              end
            rescue Errno::EACCES
              raise if Process.euid == 0
            end
          end
          metadata[entry] = { :timestamp => timestamp,
                              :metadata => m } unless m.nil?
        end
      end
    end
    @installed_metadata = metadata
    # FIXME: dup the array we return?
    @installed_metadata.collect { |im| im[1][:metadata] }
  end

  # Convert metadata_for_installed_packages into pkg hashes
  def installed_packages(pkgname=nil)
    instpkgs = []
    metadata_for_installed_packages.each do |metadata|
      if !pkgname || metadata[:name] == pkgname
        instpkgs << { :metadata => metadata,
                      :source => :currently_installed,
                      # It seems reasonable for this to default to true
                      :prefer => true }
      end
    end
    instpkgs
  end

  # Returns a hash of file_metadata for installed packages
  def file_metadata_for_installed_packages(package_files = nil)
    ret = {}

    if package_files
      package_files.collect!{|package_file| File.basename(package_file, File.extname(package_file))}
    end

    if File.directory?(@metadata_directory)
      Dir.foreach(@metadata_directory) do |entry|
        next if entry == '.' || entry == '..'
        next if package_files && !package_files.include?(entry)
        file_metadata = FileMetadata::instantiate_from_dir(File.join(@metadata_directory, entry))
        ret[file_metadata[:package_file]] = file_metadata
      end
    end
    ret
  end

  # Returns an array of packages which meet the given requirement
  def available_packages_that_meet_requirement(req=nil)
    pkgs = nil
    puts "avail_pkgs_that_meet_req checking for #{req.inspect}" if @@debug
    if @available_packages_cache[req]
      puts "avail_pkgs_that_meet_req returning cached result" if @@debug
      pkgs = @available_packages_cache[req]
    else
      pkgs = []
      if req
        req = req.clone # we're using req as the key for our cache, so it's important
                        # that we clone it here. Otherwise, req can be changed later on from
                        # the calling method and modify our cache inadvertently
        if req[:type] == :native
          available_native_packages(req[:name]).each do |pkg|
            if package_meets_requirement?(pkg, req)
              pkgs << pkg
            end
          end
        else
          load_available_packages(req[:name])
          @available_packages[req[:name]].each do |pkg|
            if package_meets_requirement?(pkg, req)
              pkgs << pkg
            end
          end
          # There's a weird dicotomy here where @available_packages contains
          # available tpkg and native packages, and _installed_ native
          # packages, but not installed tpkgs.  That's somewhat intentional,
          # as we don't want to cache the installed state since that might
          # change during a run.  We probably should be consistent, and not
          # cache installed native packages either.  However, we do have
          # some intelligent caching of the installed tpkg state which would
          # be hard to replicate for native packages, and this method gets
          # called a lot so re-running the native package query commands
          # frequently would not be acceptable.  So maybe we have the right
          # design, and this just serves as a note that it is not obvious.
          pkgs.concat(installed_packages_that_meet_requirement(req))
        end
      else
        # We return everything available if given a nil requirement
        # We do not include native packages
        load_available_packages
        # @available_packages is a hash of pkgname => array of pkgs
        # Thus m is a 2 element array of [pkgname, array of pkgs]
        # And thus m[1] is the array of packages
        pkgs = @available_packages.collect{|m| m[1]}.flatten
      end
      @available_packages_cache[req] = pkgs
    end
    pkgs
  end

  # Returns an array (possibly empty) of the packages that meet the given
  # requirement.  If the given requirement is nil or not specified then all
  # installed packages are returned.
  def installed_packages_that_meet_requirement(req=nil)
    pkgs = []
    if req && req[:type] == :native
      available_native_packages(req[:name]).each do |pkg|
        if pkg[:source] == :native_installed &&
           package_meets_requirement?(pkg, req)
          pkgs << pkg
        end
      end
    else
      pkgname = nil
      if req && req[:name]
        pkgname = req[:name]
      end
      # Passing a package name if we have one to installed_packages serves
      # primarily to make following the debugging output of dependency
      # resolution easier.  The dependency resolution process makes frequent
      # calls to available_packages_that_meet_requirement, which in turn calls
      # this method.  For available packages we're able to pre-filter based on
      # package name before calling package_meets_requirement? because we
      # store available packages hashed based on package name.
      # package_meets_requirement? is fairly verbose in its debugging output,
      # so the user sees each package it checks against a given requirement.
      # It is therefore a bit disconcerting when trying to follow the
      # debugging output to see the fairly clean process of checking available
      # packages which have already been filtered to match the desired name,
      # and then available_packages_that_meet_requirement calls this method,
      # and the user starts to see every installed package checked against the
      # same requirement.  It is not obvious to the someone why all of a
      # sudden packages that aren't even remotely close to the requirement
      # start getting checked.  Doing a pre-filter based on package name here
      # makes the process more consistent and easier to follow.
      installed_packages(pkgname).each do |pkg|
        if req
          if package_meets_requirement?(pkg, req)
            pkgs << pkg
          end
        else
          pkgs << pkg
        end
      end
    end
    pkgs
  end
  # Takes a files structure as returned by files_in_package.  Inserts
  # a new entry in the structure with the combined relocatable and
  # non-relocatable file lists normalized to their full paths.
  def normalize_paths(files)
    files[:normalized] = []
    files[:root].each do |rootfile|
      files[:normalized] << File.join(@file_system_root, rootfile)
    end
    files[:reloc].each do |relocfile|
      files[:normalized] << File.join(@base, relocfile)
    end
  end
  def normalize_path(path,root=nil,base=nil)
    root ||= @file_system_root
    base ||= @base
    if path[0,1] == File::SEPARATOR
      normalized_path = File.join(root, path)
    else
      normalized_path = File.join(base, path)
    end
    normalized_path
  end
  def files_for_installed_packages(package_files=nil)
    files = {}
    if !package_files
      package_files = []
      metadata_for_installed_packages.each do |metadata|
        package_files << metadata[:filename]
      end
    end

    metadata_for_installed_packages.each do |metadata|
      package_file = metadata[:filename]
      if package_files.include?(package_file)
        fip = Tpkg::files_in_package(File.join(@installed_directory, package_file), {:metadata_directory => @metadata_directory})
        normalize_paths(fip)
        fip[:metadata] = metadata
        files[package_file] = fip
      end
    end
    files
  end

  # Returns the best solution that meets the given requirements.  Some or all
  # packages may be optionally pre-selected and specified via the packages
  # parameter, otherwise packages are picked from the set of available
  # packages.  The requirements parameter is an array of package requirements.
  # The packages parameter is in the form of a hash with package names as keys
  # pointing to arrays of package specs (our standard hash of package metadata
  # and source).  The core_packages parameter is an array of the names of
  # packages that should be considered core requirements, i.e. the user
  # specifically requested they be installed or upgraded. The return value
  # will be an array of package specs.
  MAX_POSSIBLE_SOLUTIONS_TO_CHECK = 10000
  def best_solution(requirements, packages, core_packages)
    result = resolve_dependencies(requirements, {:tpkg => packages, :native => {}}, core_packages)
    if @@debug
      if result[:solution]
        puts "bestsol picks: #{result[:solution].inspect}" if @@debug
      else
        puts "bestsol checked #{result[:number_of_possible_solutions_checked]} possible solutions, none worked"
      end
    end
    result[:solution]
  end

  # Recursive method used by best_solution
  # Parameters mostly map from best_solution, but packages turns into a hash
  # with two possible keys, :tpkg and :native.  The value for the :tpkg key
  # would be the packages parameter from best_solution.  Native packages are
  # only installed due to dependencies, we don't let the user request them
  # directly, so callers of best_solution never need to pass in a package list
  # for native packages.  Separating the two sets of packages allows us to
  # calculate a solution that contains both a tpkg and a native package with
  # the same name.  This may be necessary if different dependencies of the
  # core packages end up needing both.
  def resolve_dependencies(requirements, packages, core_packages, number_of_possible_solutions_checked=0)
    # We're probably going to make changes to packages, dup it now so
    # that we don't mess up the caller's state.
    packages = {:tpkg => packages[:tpkg].dup, :native => packages[:native].dup}

    # Make sure we have populated package lists for all requirements.
    # Filter the package lists against the requirements and
    # ensure we can at least satisfy the initial requirements.
    requirements.each do |req|
      if !packages[req[:type]][req[:name]]
        puts "resolvedeps initializing packages for #{req.inspect}" if @@debug
        packages[req[:type]][req[:name]] =
          available_packages_that_meet_requirement(req)
      else
        # Loop over packages and eliminate ones that don't work for
        # this requirement
        puts "resolvedeps filtering packages for #{req.inspect}" if @@debug
        packages[req[:type]][req[:name]] =
          packages[req[:type]][req[:name]].select do |pkg|
            # When this method is called recursively there might be a
            # nil entry inserted into packages by the sorting code
            # below.  We need to skip those.
            if pkg != nil
              package_meets_requirement?(pkg, req)
            end
          end
      end
      if packages[req[:type]][req[:name]].empty?
        if @@debug
          puts "No packages matching #{req.inspect}"
        end
        return {:number_of_possible_solutions_checked => number_of_possible_solutions_checked}
      end
    end

    # FIXME: Should we weed out any entries in packages that don't correspond
    # to something in requirements?  We operate later on the assumption that
    # there are no such entries.  Because we dup packages at the right points
    # I believe we'll never accidently end up with orphaned entries, but maybe
    # it would be worth the compute cycles to make sure?

    # Sort the packages
    [:tpkg, :native].each do |type|
      packages[type].each do |pkgname, pkgs|
        pkgs.sort!(&SORT_PACKAGES)
        # Only currently installed packages are allowed to score 0.
        # Anything else can score 1 at best.  This ensures
        # that we prefer the solution which leaves the most
        # currently installed packages alone.
        if pkgs[0] &&
           pkgs[0][:source] != :currently_installed &&
           pkgs[0][:source] != :native_installed
          pkgs.unshift(nil)
        end
      end
    end

    if @@debug
      puts "Packages after initial population and filtering:"
      puts packages.inspect
    end

    # Here's an example of the possible solution sets we should come
    # up with and the proper ordering.  Sets with identical averages
    # are equivalent, the order they appear in does not matter.
    #
    # packages: [a0, a1, a2], [b0, b1, b2], [c0, c1, c2]
    # core_packages: a, b
    #
    # [a0, b0, c0]  (core avg 0)  (avg 0)
    # [a0, b0, c1]                (avg .33)
    # [a0, b0, c2]                (avg .66)
    # [a0, b1, c0]  (core avg .5) (avg .33)
    # [a1, b0, c0]
    # [a0, b1, c1]                (avg .66)
    # [a1, b0, c1]
    # [a0, b1, c2]                (avg 1)
    # [a1, b0, c2]
    # [a1, b1, c0]  (core avg 1)  (avg .66)
    # [a0, b2, c0]
    # [a2, b0, c0]
    # [a1, b1, c1]                (avg 1)
    # [a0, b2, c1]
    # [a2, b0, c1]
    # [a1, b1, c2]                (avg 1.33)
    # [a0, b2, c2]
    # [a2, b0, c2]
    # [a1, b2, c0] (core avg 1.5) (avg 1)
    # [a2, b1, c0]
    # [a1, b2, c1]                (avg 1.33)
    # [a2, b1, c1]
    # [a1, b2, c2]                (avg 1.67)
    # [a2, b1, c2]
    # [a2, b2, c0] (core avg 2)   (avg 1.33)
    # [a2, b2, c1]                (avg 1.67)
    # [a2, b2, c2]                (avg 2)

    # Divide packages into core and non-core packages
    corepkgs = packages[:tpkg].reject{|pkgname, pkgs| !core_packages.include?(pkgname)}
    noncorepkgs = {}
    noncorepkgs[:tpkg] = packages[:tpkg].reject{|pkgname, pkgs| core_packages.include?(pkgname)}
    noncorepkgs[:native] = packages[:native]

    # Calculate total package depth, the sum of the lengths (or rather
    # the max array index) of each array of packages.
    coretotaldepth = corepkgs.inject(0) {|memo, pkgs| memo + pkgs[1].length - 1}
    noncoretotaldepth = noncorepkgs[:tpkg].inject(0) {|memo, pkgs| memo + pkgs[1].length - 1} +
                        noncorepkgs[:native].inject(0) {|memo, pkgs| memo + pkgs[1].length - 1}
    if @@debug
      puts "resolvedeps coretotaldepth #{coretotaldepth}"
      puts "resolvedeps noncoretotaldepth #{noncoretotaldepth}"
    end

    # First pass, combinations of core packages
    (0..coretotaldepth).each do |coredepth|
      puts "resolvedeps checking coredepth: #{coredepth}" if @@debug
      core_solutions = [{:remaining_coredepth => coredepth, :pkgs => []}]
      corepkgs.each do |pkgname, pkgs|
        puts "resolvedeps corepkg #{pkgname}: #{pkgs.inspect}" if @@debug
        new_core_solutions = []
        core_solutions.each do |core_solution|
          remaining_coredepth = core_solution[:remaining_coredepth]
          puts "resolvedeps :remaining_coredepth: #{remaining_coredepth}" if @@debug
          (0..[remaining_coredepth, pkgs.length-1].min).each do |corepkgdepth|
            puts "resolvedeps corepkgdepth: #{corepkgdepth}" if @@debug
            # We insert a nil entry in some situations (see the sort
            # step earlier), so skip nil entries in the pkgs array.
            if pkgs[corepkgdepth] != nil
              coresol = core_solution.dup
              # Hash#dup doesn't dup each key/value, so we need to
              # explicitly dup :pkgs so that each copy has an
              # independent array that we can modify.
              coresol[:pkgs] = core_solution[:pkgs].dup
              coresol[:remaining_coredepth] -= corepkgdepth
              coresol[:pkgs] << pkgs[corepkgdepth]
              new_core_solutions << coresol
              # If this is a complete combination of core packages then
              # proceed to the next step
              puts "resolvedeps coresol[:pkgs] #{coresol[:pkgs].inspect}" if @@debug
              if coresol[:pkgs].length == corepkgs.length
                puts "resolvedeps complete core pkg set: #{coresol.inspect}" if @@debug
                # Solutions with remaining depth are duplicates of
                # solutions we already checked at lower depth levels
                # I.e. at coredepth==0 we'd have:
                # {:pkgs=>{a0, b0}, :remaining_coredepth=0}
                # And at coredepth==1:
                # {:pkgs=>{a0,b0}, :remaining_coredepth=1}
                # Whereas at coredepth==1 this is new and needs to be checked:
                # {:pkgs=>{a1,b0}, :remaining_coredepth=0}
                if coresol[:remaining_coredepth] == 0
                  # Second pass, add combinations of non-core packages
                  if noncorepkgs[:tpkg].empty? && noncorepkgs[:native].empty?
                    puts "resolvedeps noncorepkgs empty, checking solution" if @@debug
                    result = check_solution(coresol, requirements, packages, core_packages, number_of_possible_solutions_checked)
                    if result[:solution]
                      return result
                    else
                      number_of_possible_solutions_checked = result[:number_of_possible_solutions_checked]
                    end
                  else
                    (0..noncoretotaldepth).each do |noncoredepth|
                      puts "resolvedeps noncoredepth: #{noncoredepth}" if @@debug
                      coresol[:remaining_noncoredepth] = noncoredepth
                      solutions = [coresol]
                      [:tpkg, :native].each do |nctype|
                        noncorepkgs[nctype].each do |ncpkgname, ncpkgs|
                          puts "resolvedeps noncorepkg #{nctype} #{ncpkgname}: #{ncpkgs.inspect}" if @@debug
                          new_solutions = []
                          solutions.each do |solution|
                            remaining_noncoredepth = solution[:remaining_noncoredepth]
                            puts "resolvedeps :remaining_noncoredepth: #{remaining_noncoredepth}" if @@debug
                            (0..[remaining_noncoredepth, ncpkgs.length-1].min).each do |ncpkgdepth|
                              puts "resolvedeps ncpkgdepth: #{ncpkgdepth}" if @@debug
                              # We insert a nil entry in some situations (see the sort
                              # step earlier), so skip nil entries in the pkgs array.
                              if ncpkgs[ncpkgdepth] != nil
                                sol = solution.dup
                                # Hash#dup doesn't dup each key/value, so we need to
                                # explicitly dup :pkgs so that each copy has an
                                # independent array that we can modify.
                                sol[:pkgs] = solution[:pkgs].dup
                                sol[:remaining_noncoredepth] -= ncpkgdepth
                                sol[:pkgs] << ncpkgs[ncpkgdepth]
                                new_solutions << sol
                                # If this is a complete combination of packages then
                                # proceed to the next step
                                puts "resolvedeps sol[:pkgs] #{sol[:pkgs].inspect}" if @@debug
                                if sol[:pkgs].length == packages[:tpkg].length + packages[:native].length
                                  puts "resolvedeps complete pkg set: #{sol.inspect}" if @@debug
                                  # Solutions with remaining depth are duplicates of
                                  # solutions we already checked at lower depth levels
                                  if sol[:remaining_noncoredepth] == 0
                                    result = check_solution(sol, requirements, packages, core_packages, number_of_possible_solutions_checked)
                                    if result[:solution]
                                      puts "resolvdeps returning successful solution" if @@debug
                                      return result
                                    else
                                      number_of_possible_solutions_checked = result[:number_of_possible_solutions_checked]
                                    end
                                  end
                                end
                              end
                            end
                          end
                          solutions = new_solutions
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
        core_solutions = new_core_solutions
      end
    end
    # No solutions found
    puts "resolvedeps returning failure" if @@debug
    return {:number_of_possible_solutions_checked => number_of_possible_solutions_checked}
  end

  # Used by resolve_dependencies
  def check_solution(solution, requirements, packages, core_packages, number_of_possible_solutions_checked)
    number_of_possible_solutions_checked += 1
    # Probably should give the user a way to override this
    if number_of_possible_solutions_checked > MAX_POSSIBLE_SOLUTIONS_TO_CHECK
      raise "Checked #{MAX_POSSIBLE_SOLUTIONS_TO_CHECK} possible solutions to requirements and dependencies, no solution found"
    end

    if @@debug
      puts "checksol checking sol #{solution.inspect}"
    end

    # Extract dependencies from each package in the solution
    newreqs = []
    solution[:pkgs].each do |pkg|
      puts "checksol pkg #{pkg.inspect}" if @@debug
      if pkg[:metadata][:dependencies]
        pkg[:metadata][:dependencies].each do |depreq|
          if !requirements.include?(depreq) && !newreqs.include?(depreq)
            puts "checksol new depreq #{depreq.inspect}" if @@debug
            newreqs << depreq
          end
        end
      end
    end

    if newreqs.empty?
      # No additional requirements, this is a complete solution
      puts "checksol no newreqs, complete solution" if @@debug
      return {:solution => solution[:pkgs]}
    else
      newreqs_that_need_packages = []
      newreqs.each do |newreq|
        puts "checksol checking newreq: #{newreq.inspect}" if @@debug
        if packages[newreq[:type]][newreq[:name]]
          pkg = solution[:pkgs].find{|solpkg| solpkg[:metadata][:name] == newreq[:name]}
          puts "checksol newreq pkg: #{pkg.inspect}" if @@debug
          if pkg && package_meets_requirement?(pkg, newreq)
            # No change to solution needed
          else
            # Solution no longer works
            puts "checksol solution no longer works" if @@debug
            return {:number_of_possible_solutions_checked => number_of_possible_solutions_checked}
          end
        else
          puts "checksol newreq needs packages" if @@debug
          newreqs_that_need_packages << newreq
        end
      end
      if newreqs_that_need_packages.empty?
        # None of the new requirements changed the solution, so the solution is complete
        puts "checksol no newreqs that need packages, complete solution" if @@debug
        return {:solution => solution[:pkgs]}
      else
        puts "checksol newreqs need packages, calling resolvedeps" if @@debug
        result = resolve_dependencies(requirements+newreqs_that_need_packages, packages, core_packages, number_of_possible_solutions_checked)
        if result[:solution]
          puts "checksol returning successful solution" if @@debug
          return result
        else
          number_of_possible_solutions_checked = result[:number_of_possible_solutions_checked]
        end
      end
    end
    puts "checksol returning failure" if @@debug
    return {:number_of_possible_solutions_checked => number_of_possible_solutions_checked}
  end

  def download(source, path, downloaddir = nil, use_cache = true)
    http = gethttp(URI.parse(source))
    localdir = source_to_local_directory(source)
    localpath = File.join(localdir, File.basename(path))
    # Don't download again if file is already there from previous installation
    # and still has valid checksum
    if File.file?(localpath) && use_cache
      begin
        Tpkg::verify_package_checksum(localpath)
        return localpath
      rescue RuntimeError, NoMethodError
        # Previous download is bad (which can happen for a variety of
        # reasons like an interrupted download or a bad package on the
        # server).  Delete it and we'll try to grab it again.
        File.delete(localpath)
      end
    else
      # If downloaddir is specified, then download to that directory. Otherwise,
      # download to default source directory
      localdir = downloaddir || localdir
      FileUtils.mkdir_p(localdir)
      localpath = File.join(localdir, File.basename(path))
    end
    uri = URI.join(source, path)
    tmpfile = Tempfile.new(File.basename(localpath), File.dirname(localpath))
    http.request_get(uri.path) do |response|
      # Package files can be quite large, so we transfer the package to a
      # local file in chunks
      response.read_body do |chunk|
        tmpfile.write(chunk)
      end
      remotedate = Time.httpdate(response['Date'])
      File.utime(remotedate, remotedate, tmpfile.path)
    end
    tmpfile.close

    begin
      Tpkg::verify_package_checksum(tmpfile.path)
      File.chmod(0644, tmpfile.path)
      File.rename(tmpfile.path, localpath)
    rescue
      # FIXME: should include original exception message to help user debug
      raise "Unable to download and/or verify the package."
    end

    localpath
  end

  # Given a package's metadata return a hash of init scripts in the
  # package and the entry for that file from the metadata
  def init_scripts(metadata)
    init_scripts = {}
    # don't do anything unless we have to
    unless metadata[:files] && metadata[:files][:files]
      return init_scripts
    end
    metadata[:files][:files].each do |tpkgfile|
      if tpkgfile[:init]
        tpkg_path = tpkgfile[:path]
        installed_path = normalize_path(tpkg_path)
        init_scripts[installed_path] = tpkgfile
      end
    end
    init_scripts
  end
  # Given a package's metadata return a hash of init scripts in the
  # package and where they need to be linked to on the system
  def init_links(metadata)
    links = {}
    init_scripts(metadata).each do |installed_path, tpkgfile|
      os.init_links(installed_path, tpkgfile).each do |link_path|
        link = File.join(@file_system_root, link_path)
        links[link] = File.join(@file_system_root, installed_path)
      end
    end
    links
  end
  # Given a package's metadata return a hash of crontabs in the
  # package and the entry for that file from the metadata
  def crontabs(metadata)
    crontabs = {}
    unless metadata[:files] && metadata[:files][:files]
      return crontabs
    end
    metadata[:files][:files].each do |tpkgfile|
      if tpkgfile[:crontab]
        tpkg_path = tpkgfile[:path]
        installed_path = normalize_path(tpkg_path)
        crontabs[installed_path] = tpkgfile
      end
    end
    crontabs
  end
  # Given a package's metadata return a hash of crontabs in the
  # package and where they need to be installed on the system
  def crontab_destinations(metadata)
    destinations = {}
    crontabs(metadata).each do |installed_path, tpkgfile|
      destinations[installed_path] = crontab_destination(installed_path, tpkgfile)
    end
    destinations
  end
  # Given info for a crontab from a package's metadata return info about
  # where the crontab needs to be installed on the system
  def crontab_destination(installed_path, tpkgfile)
    destination = {}
    # Decide whether we're going to add the file to a per-user crontab or
    # link it into a directory of cron.d-style crontabs.
    if tpkgfile[:crontab][:user]
      destination[:type] = :file
      destination[:user] = tpkgfile[:crontab][:user]
    else
      if os.cron_dot_d_directory
        destination[:type] = :link
        destination[:path] = File.join(os.cron_dot_d_directory, File.basename(installed_path))
      else
        warn "No cron.d-style crontab support for #{os}"
      end
    end
    destination
  end

  def run_external(pkgfile, operation, name, data)
    externalpath = File.join(@external_directory, name)
    if !File.executable?(externalpath)
      if @force
        warn "External #{externalpath} does not exist or is not executable"
      else
        raise "External #{externalpath} does not exist or is not executable"
      end
    end
    case operation
    when :install
      begin
        IO.popen("#{externalpath} '#{pkgfile}' install", 'w') do |pipe|
          pipe.write(data)
        end
        if !$?.success?
          raise "Exit value #{$?.exitstatus}"
        end
      rescue => e
        # Tell the user which external and package were involved, otherwise
        # failures in externals are very hard to debug
        # FIXME: should we clean up the external request files?
        if @force
          warn "External #{name} #{operation} for #{File.basename(pkgfile)}: " + e.message
        else
          raise Tpkg.wrap_exception(e, "External #{name} #{operation} for #{File.basename(pkgfile)}: " + e.message)
        end
      end
    when :remove
      begin
        IO.popen("#{externalpath} '#{pkgfile}' remove", 'w') do |pipe|
          pipe.write(data)
        end
        if !$?.success?
          raise "Exit value #{$?.exitstatus}"
        end
      rescue => e
        if @force
          warn "External #{name} #{operation} for #{File.basename(pkgfile)}: " + e.message
        else
          raise Tpkg.wrap_exception(e, "External #{name} #{operation} for #{File.basename(pkgfile)}: " + e.message)
        end
      end
    else
      raise "Bug, unknown external operation #{operation}"
    end
  end

  # Unpack the files from a package into place, decrypt as necessary, set
  # permissions and ownership, etc.  Does not check for conflicting
  # files or packages, etc.  Those checks (if desired) must be done before
  # calling this method.
  def unpack(package_file, options={})
    ret_val = 0

    # set env variable to let pre/post install know  whether this unpack
    # is part of an install or upgrade
    if options[:is_doing_upgrade]
       ENV['TPKG_ACTION'] = "upgrade"
    else
       ENV['TPKG_ACTION'] = "install"
    end

    # Unpack files in a temporary directory
    # I'd prefer to unpack on the fly so that the user doesn't need to
    # have disk space to hold three copies of the package (the package
    # file itself, this temporary unpack, and the final copy of the
    # files).  However, I haven't figured out a way to get that to work,
    # since we need to strip several layers of directories out of the
    # directory structure in the package.
    topleveldir = Tpkg::package_toplevel_directory(package_file)
    workdir = Tpkg::tempdir(topleveldir, @tmp_directory)
    extract_tpkg_tar_cmd = Tpkg::cmd_to_extract_tpkg_tar(package_file, topleveldir)
    system("#{extract_tpkg_tar_cmd} | #{@tar} #{@@taroptions} -C #{workdir} -xpf -")
    files_info = {} # store perms, uid, gid, etc. for files
    checksums_of_decrypted_files = {}

    metadata = Tpkg::metadata_from_package(package_file, {:topleveldir => topleveldir})

    # Get list of files/directories that already exist in the system. Store their perm/ownership.
    # That way, when we copy over the new files, we can set the new files to have the same perm/owernship.
    conflicting_files = {}
    fip = Tpkg::files_in_package(package_file)
    (fip[:root] | fip[:reloc]).each do |file|
      file_in_staging = normalize_path(file, File.join(workdir, 'tpkg', 'root'), File.join(workdir, 'tpkg', 'reloc'))
      file_in_system = normalize_path(file)
      if File.exists?(file_in_system) && !File.symlink?(file_in_system)
        conflicting_files[file] = {:normalized => file_in_staging, :stat => File.stat(file_in_system)}
      end
    end

    run_preinstall(package_file, workdir)

    run_externals_for_install(metadata, workdir, options[:externals_to_skip])

    # Since we're stuck with unpacking to a temporary folder take
    # advantage of that to handle permissions, ownership and decryption
    # tasks before moving the files into their final location.

    # Handle any default permissions and ownership
    default_uid = DEFAULT_OWNERSHIP_UID
    default_gid = DEFAULT_OWNERSHIP_GID
    default_perms = DEFAULT_FILE_PERMS

    if (metadata[:files][:file_defaults][:posix][:owner] rescue nil)
      default_uid = Tpkg::lookup_uid(metadata[:files][:file_defaults][:posix][:owner])
    end
    if (metadata[:files][:file_defaults][:posix][:group] rescue nil)
      default_gid = Tpkg::lookup_gid(metadata[:files][:file_defaults][:posix][:group])
    end
    # FIXME: Default file permissions aren't likely to be generally useful
    # since different classes of files often require different permissions.
    # I.e. executables should be 0555, links 0777, everything else 0444.
    # Something more like a umask would probably be more generally useful.
    if (metadata[:files][:file_defaults][:posix][:perms] rescue nil)
      default_perms = metadata[:files][:file_defaults][:posix][:perms]
    end

    # Set default dir uid/gid to be same as for file.
    default_dir_uid = default_uid
    default_dir_gid = default_gid
    default_dir_perms = DEFAULT_DIR_PERMS

    if (metadata[:files][:dir_defaults][:posix][:owner] rescue nil)
      default_dir_uid = Tpkg::lookup_uid(metadata[:files][:dir_defaults][:posix][:owner])
    end
    if (metadata[:files][:dir_defaults][:posix][:group] rescue nil)
      default_dir_gid = Tpkg::lookup_gid(metadata[:files][:dir_defaults][:posix][:group])
    end
    if (metadata[:files][:dir_defaults][:posix][:perms] rescue nil)
      default_dir_perms = metadata[:files][:dir_defaults][:posix][:perms]
    end

    root_dir = File.join(workdir, 'tpkg', 'root')
    reloc_dir = File.join(workdir, 'tpkg', 'reloc')
    Find.find(*Tpkg::get_package_toplevels(File.join(workdir, 'tpkg'))) do |f|
      begin
        if File.symlink?(f)
          begin
            File.lchown(default_uid, default_gid, f)
          rescue NotImplementedError
          end
        elsif File.file?(f)
          File.chown(default_uid, default_gid, f)
        elsif File.directory?(f)
          File.chown(default_dir_uid, default_dir_gid, f)
        end
      rescue Errno::EPERM
        raise if Process.euid == 0
      rescue Errno::EINVAL
        raise if RUBY_PLATFORM != 'i386-cygwin'
      end
      if File.symlink?(f)
        if default_perms
          begin
            File.lchmod(default_perms, f)
          rescue NotImplementedError
          end
        end
      elsif File.file?(f)
        if default_perms
          File.chmod(default_perms, f)
        end
      elsif File.directory?(f)
        File.chmod(default_dir_perms, f)
      end
    end

    # Reset the permission/ownership of the conflicting files as how they were before.
    # This needs to be done after the default permission/ownership is applied, but before
    # the handling of ownership/permissions on specific files
    conflicting_files.each do | file, info |
      stat = info[:stat]
      file_path = info[:normalized]
      File.chmod(stat.mode, file_path)
      begin
        File.chown(stat.uid, stat.gid, file_path)
      rescue Errno::EPERM
        raise if Process.euid == 0
      rescue Errno::EINVAL
        raise if RUBY_PLATFORM != 'i386-cygwin'
      end
    end

    # Handle any decryption, ownership/permissions, and other issues for specific files
    metadata[:files][:files].each do |tpkgfile|
      tpkg_path = tpkgfile[:path]
      working_path = normalize_path(tpkg_path, File.join(workdir, 'tpkg', 'root'), File.join(workdir, 'tpkg', 'reloc'))
      if !File.exist?(working_path) && !File.symlink?(working_path)
        raise "tpkg.xml for #{File.basename(package_file)} references file #{tpkg_path} but that file is not in the package"
      end

      # Set permissions and ownership for specific files
      # We do this before the decryption stage so that permissions and
      # ownership designed to protect private file contents are in place
      # prior to decryption.  The decrypt method preserves the permissions
      # and ownership of the encrypted file on the decrypted file.
      if tpkgfile[:posix]
        if tpkgfile[:posix][:owner] || tpkgfile[:posix][:group]
          uid = nil
          if tpkgfile[:posix][:owner]
            uid = Tpkg::lookup_uid(tpkgfile[:posix][:owner])
          end
          gid = nil
          if tpkgfile[:posix][:group]
            gid = Tpkg::lookup_gid(tpkgfile[:posix][:group])
          end
          begin
            if !File.symlink?(working_path)
              File.chown(uid, gid, working_path)
            else
              begin
                File.lchown(uid, gid, working_path)
              rescue NotImplementedError
              end
            end
          rescue Errno::EPERM
            raise if Process.euid == 0
          rescue Errno::EINVAL
            raise if RUBY_PLATFORM != 'i386-cygwin'
          end
        end
        if tpkgfile[:posix][:perms]
          perms = tpkgfile[:posix][:perms]
          if !File.symlink?(working_path)
            File.chmod(perms, working_path)
          else
            begin
              File.lchmod(perms, working_path)
            rescue NotImplementedError
            end
          end
        end
      end

      # Decrypt any files marked for decryption
      if tpkgfile[:encrypt]
        if !options[:passphrase]
          # If the user didn't supply a passphrase then just remove the
          # encrypted file.  This allows users to install packages that
          # contain encrypted files for which they don't have the
          # passphrase.  They end up with just the non-encrypted files,
          # potentially useful for development or QA environments.
          File.delete(working_path)
        else
          (1..3).each do | i |
            begin
              Tpkg::decrypt(metadata[:name], working_path, options[:passphrase], *([tpkgfile[:encrypt][:algorithm]].compact))
              break
            rescue OpenSSLCipherError
              @@passphrase = nil
              if i == 3
                raise "Incorrect passphrase."
              else
                puts "Incorrect passphrase. Try again."
              end
            end
          end

          if File.file?(working_path)
            digest = Digest::SHA256.hexdigest(File.read(working_path))
            # get checksum for the decrypted file. Will be used for creating file_metadata
            checksums_of_decrypted_files[File.expand_path(tpkg_path)] = digest
          end
        end
      end

      # If a conf file already exists on the file system, don't overwrite it. Rename
      # the new one with .tpkgnew file extension.
      if tpkgfile[:config] && conflicting_files[tpkgfile[:path]]
        FileUtils.mv(conflicting_files[tpkgfile[:path]][:normalized], "#{conflicting_files[tpkgfile[:path]][:normalized]}.tpkgnew")
      end
    end if metadata[:files] && metadata[:files][:files]

    # We should get the perms, gid, uid stuff here since all the files
    # have been set up correctly
    Find.find(*Tpkg::get_package_toplevels(File.join(workdir, 'tpkg'))) do |f|
      next if File.symlink?(f)

      # check if it's from root dir or reloc dir
      if f =~ /^#{Regexp.escape(root_dir)}/
        short_fn = f[root_dir.length ..-1]
      else
        short_fn = f[reloc_dir.length + 1..-1]
        relocatable = "true"
      end

      acl = {}
      acl["gid"] = File.stat(f).gid
      acl["uid"] = File.stat(f).uid
      acl["perms"] = File.stat(f).mode.to_s(8)
      files_info[short_fn] = acl
    end

    # Move files into place
    # If we implement any of the ACL permissions features we'll have to be
    # careful here that tar preserves those permissions.  Otherwise we'll
    # need to apply them after moving the files into place.
    if File.directory?(File.join(workdir, 'tpkg', 'root'))
      system("#{@tar} -C #{File.join(workdir, 'tpkg', 'root')} -cf - . | #{@tar} -C #{@file_system_root} -xpf -")
    end
    if File.directory?(File.join(workdir, 'tpkg', 'reloc'))
      system("#{@tar} -C #{File.join(workdir, 'tpkg', 'reloc')} -cf - . | #{@tar} -C #{@base} -xpf -")
    end

    install_init_scripts(metadata)
    install_crontabs(metadata)

    ret_val = run_postinstall(package_file, workdir)

    save_package_metadata(package_file, workdir, metadata, files_info, checksums_of_decrypted_files)

    # Copy the package file to the directory for installed packages
    FileUtils.cp(package_file, @installed_directory)

    # Cleanup
    FileUtils.rm_rf(workdir)
    return ret_val
  end

  def install_init_scripts(metadata)
    init_links(metadata).each do |link, installed_path|
      install_init_script(metadata, link, installed_path)
    end
  end
  def install_init_script(metadata, link, installed_path)
    # We don't have to do anything if there's already symlink to our init
    # script. This can happen if the user removes a package manually without
    # removing the init symlink
    return if File.symlink?(link) && File.readlink(link) == installed_path
    begin
      FileUtils.mkdir_p(File.dirname(link))
      begin
        File.symlink(installed_path, link)
      rescue Errno::EEXIST
        # The link name that init_links provides is not guaranteed to
        # be unique.  It might collide with a base system init script
        # or an init script from another tpkg.  If the link name
        # supplied by init_links results in EEXIST then try appending
        # a number to the end of the link name.
        catch :init_link_done do
          1.upto(9) do |i|
            begin
              File.symlink(installed_path, link + i.to_s)
              throw :init_link_done
            rescue Errno::EEXIST
            end
          end
          # If we get here (i.e. we never reached the throw) then we
          # failed to create any of the possible link names.
          raise "Failed to install init script #{installed_path} -> #{link} for #{File.basename(metadata[:filename].to_s)}, too many overlapping filenames"
        end
      end
    # EACCES for file/directory permissions issues
    rescue Errno::EACCES => e
      # If creating the link fails due to permission problems and
      # we're not running as root just warn the user, allowing folks
      # to run tpkg as a non-root user with reduced functionality.
      if Process.euid != 0
        warn "Failed to install init script for #{File.basename(metadata[:filename].to_s)}, probably due to lack of root privileges: #{e.message}"
      else
        raise e
      end
    end
  end
  def remove_init_scripts(metadata)
    init_links(metadata).each do |link, installed_path|
      remove_init_script(metadata, link, installed_path)
    end
  end
  def remove_init_script(metadata, link, installed_path)
    # The link we ended up making when we unpacked the package could be any
    # of a series (see the code in install_init_scripts for the reasoning),
    # we need to check them all.
    links = [link]
    links.concat((1..9).to_a.map { |i| link + i.to_s })
    links.each do |l|
      if File.symlink?(l) && File.readlink(l) == installed_path
        begin
          File.delete(l)
        # EACCES for file/directory permissions issues
        rescue Errno::EACCES => e
          # If removing the link fails due to permission problems and
          # we're not running as root just warn the user, allowing folks
          # to run tpkg as a non-root user with reduced functionality.
          if Process.euid != 0
            warn "Failed to remove init script for #{File.basename(metadata[:filename].to_s)}, probably due to lack of root privileges: #{e.message}"
          else
            raise e
          end
        end
      end
    end
  end

  def install_crontabs(metadata)
    crontab_destinations(metadata).each do |crontab, destination|
      if destination[:type] == :link
        install_crontab_link(metadata, crontab, destination[:path])
      elsif destination[:type] == :file
        install_crontab_file(metadata, crontab, destination[:user])
      end
    end
  end
  def install_crontab_link(metadata, crontab, destination)
    return if (File.symlink?(destination) && File.readlink(destination) == crontab)
    begin
      FileUtils.mkdir_p(File.dirname(destination))
      begin
        File.symlink(crontab, destination)
      rescue Errno::EEXIST
        # The link name that crontab_destinations provides is not
        # guaranteed to be unique.  It might collide with a base
        # system crontab or a crontab from another tpkg.  If the
        # link name supplied by crontab_destinations results in
        # EEXIST then try appending a number to the end of the link
        # name.
        catch :crontab_link_done do
          1.upto(9) do |i|
            begin
              File.symlink(crontab, destination + i.to_s)
              throw :crontab_link_done
            rescue Errno::EEXIST
            end
          end
          # If we get here (i.e. we never reached the throw) then we
          # failed to create any of the possible link names.
          raise "Failed to install crontab #{crontab} -> #{destination} for #{File.basename(metadata[:filename].to_s)}, too many overlapping filenames"
        end
      end
    rescue Errno::EACCES => e
      # If installing the crontab fails due to permission problems and
      # we're not running as root just warn the user, allowing folks
      # to run tpkg as a non-root user with reduced functionality.
      if Process.euid != 0
        warn "Failed to install crontab for #{File.basename(metadata[:filename].to_s)}, probably due to lack of root privileges: #{e.message}"
      else
        raise e
      end
    end
  end
  def crontab_uoption(user)
    # The crontab command generally seems unwilling to let you specify the -u
    # option, even for your own username, if you aren't root.  So if the user
    # requested is the same as the current user omit the option.
    uoption = nil
    if user == 'ANY' || user == Etc.getpwuid.name
      uoption = ''
    else
      uoption = "-u #{user}"
      if Process.uid != 0
        warn "Package requests user #{user} for crontab, likely to fail due to lack of root privileges"
      end
    end
    uoption
  end
  def install_crontab_file(metadata, crontab, user)
    uoption = crontab_uoption(user)
    tf = Tempfile.new('tpkg_crontab')
    oldcron = `#{@cmd_crontab} #{uoption} -l`
    tf.write(oldcron)
    tf.write("\n") if (oldcron.chomp == oldcron)
    # Insert a header line so we can find this section to remove later
    tf.puts "### TPKG START - #{@base} - #{File.basename(metadata[:filename].to_s)}"
    newcron = File.read(crontab)
    tf.write(newcron)
    tf.write("\n") if (newcron.chomp == newcron)
    tf.puts "### TPKG END - #{@base} - #{File.basename(metadata[:filename].to_s)}"
    tf.close
    system("#{@cmd_crontab} #{uoption} #{tf.path}")
    tf.close!
  end
  def remove_crontabs(metadata)
    crontab_destinations(metadata).each do |crontab, destination|
      if destination[:type] == :link
        remove_crontab_link(metadata, crontab, destination[:path])
      elsif destination[:type] == :file
        remove_crontab_file(metadata, destination[:user])
      end
    end
  end
  def remove_crontab_link(metadata, crontab, destination)
    begin
      # The link we ended up making when we unpacked the package could
      # be any of a series (see the code in unpack for the reasoning),
      # we need to check them all.
      links = [destination]
      links.concat((1..9).to_a.map { |i| destination + i.to_s })
      links.each do |l|
        if File.symlink?(l) && File.readlink(l) == crontab
          File.delete(l)
        end
      end
    rescue Errno::EACCES => e
      # If removing the crontab fails due to permission problems and
      # we're not running as root just warn the user, allowing folks
      # to run tpkg as a non-root user with reduced functionality.
      if Process.euid != 0
        warn "Failed to remove crontab for #{File.basename(metadata[:filename].to_s)}, probably due to lack of root privileges: #{e.message}"
      else
        raise e
      end
    end
  end
  def remove_crontab_file(metadata, user)
    uoption = crontab_uoption(user)
    oldcron = `#{@cmd_crontab} #{uoption} -l`
    tf = Tempfile.new('tpkg_crontab')
    # Remove section associated with this package
    skip = false
    oldcron.lines.each do |line|
      if line == "### TPKG START - #{@base} - #{File.basename(metadata[:filename].to_s)}\n"
        skip = true
      elsif line == "### TPKG END - #{@base} - #{File.basename(metadata[:filename].to_s)}\n"
        skip = false
      elsif !skip
        tf.write(line)
      end
    end
    tf.close
    system("#{@cmd_crontab} #{uoption} #{tf.path}")
    tf.close!
  end

  def run_preinstall(package_file, workdir)
    if File.exist?(File.join(workdir, 'tpkg', 'preinstall'))
      pwd = Dir.pwd
      # chdir into the working directory so that the user can specify
      # relative paths to other files in the package.
      Dir.chdir(File.join(workdir, 'tpkg'))

      begin
        # Warn the user about non-executable files, as system will just
        # silently fail and return if that's the case.
        if !File.executable?(File.join(workdir, 'tpkg', 'preinstall'))
          warn "Warning: preinstall script for #{File.basename(package_file)} is not executable, execution will likely fail"
        end
        if @force
          system(File.join(workdir, 'tpkg', 'preinstall')) || warn("Warning: preinstall for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
        else
          system(File.join(workdir, 'tpkg', 'preinstall')) || raise("Error: preinstall for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
        end
      ensure
        # Switch back to our previous directory
        Dir.chdir(pwd)
      end
    end
  end
  def run_postinstall(package_file, workdir)
    r = 0
    if File.exist?(File.join(workdir, 'tpkg', 'postinstall'))
      pwd = Dir.pwd
      # chdir into the working directory so that the user can specify
      # relative paths to other files in the package.
      Dir.chdir(File.join(workdir, 'tpkg'))

      begin
        # Warn the user about non-executable files, as system will just
        # silently fail and return if that's the case.
        if !File.executable?(File.join(workdir, 'tpkg', 'postinstall'))
          warn "Warning: postinstall script for #{File.basename(package_file)} is not executable, execution will likely fail"
        end
        # Note this only warns the user if the postinstall fails, it does
        # not raise an exception like we do if preinstall fails.  Raising
        # an exception would leave the package's files installed but the
        # package not registered as installed, which does not seem
        # desirable.  We could remove the package's files and raise an
        # exception, but this seems the best approach to me.
        system(File.join(workdir, 'tpkg', 'postinstall'))
        if !$?.success?
          warn("Warning: postinstall for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
          r = POSTINSTALL_ERR
        end
      ensure
        # Switch back to our previous directory
        Dir.chdir(pwd)
      end
    end
    r
  end

  def run_externals_for_install(metadata, workdir, externals_to_skip=[])
    metadata[:externals].each do |external|
      if !externals_to_skip || !externals_to_skip.include?(external)
        # If the external references a datafile or datascript then read/run it
        # now that we've unpacked the package contents and have the file/script
        # available.  This will get us the data for the external.
        if external[:datafile] || external[:datascript]
          pwd = Dir.pwd
          # chdir into the working directory so that the user can specify a
          # relative path to their file/script.
          Dir.chdir(File.join(workdir, 'tpkg'))
          begin
            if external[:datafile]
              # Read the file
              begin
                external[:data] = IO.read(external[:datafile])
              rescue => e
                if @force
                  warn "Datafile #{external[:datafile]} for package #{File.basename(metadata[:filename])}: " + e.message
                else
                  raise Tpkg.wrap_exception(e, "Datafile #{external[:datafile]} for package #{File.basename(metadata[:filename])}: " + e.message)
                end
              end
              # Drop the datafile key so that we don't waste time re-reading the
              # datafile again in the future.
              external.delete(:datafile)
            elsif external[:datascript]
              # Warn the user about non-executable files, popen will visibly
              # complain but in the midst of a complex install of multiple
              # packages it won't be clear to the user in what context the
              # program was executed nor which package has the problem.  Our
              # warning specifies that it was a datascript and includes the
              # package name.
              if !File.executable?(external[:datascript])
                warn "Datascript for package #{File.basename(metadata[:filename])} is not executable, execution will likely fail"
              end
              # Run the script
              begin
                IO.popen(external[:datascript]) do |pipe|
                  external[:data] = pipe.read
                end
                if !$?.success?
                  raise "Exit value #{$?.exitstatus}"
                end
              rescue => e
                if @force
                  warn "Datascript #{external[:datascript]} for package #{File.basename(metadata[:filename])}: " + e.message
                else
                  raise Tpkg.wrap_exception(e, "Datascript #{external[:datascript]} for package #{File.basename(metadata[:filename])}: " + e.message)
                end
              end
              # Drop the datascript key so that we don't waste time re-running the
              # datascript again in the future.
              external.delete(:datascript)
            end
          ensure
            # Switch back to our previous directory
            Dir.chdir(pwd)
          end
        end
        run_external(metadata[:filename], :install, external[:name], external[:data])
      end
    end if metadata[:externals]
  end

  def save_package_metadata(package_file, workdir, metadata, files_info, checksums_of_decrypted_files)
    # Save metadata for this pkg
    package_name = File.basename(package_file, File.extname(package_file))
    package_metadata_dir = File.join(@metadata_directory, package_name)
    FileUtils.mkdir_p(package_metadata_dir)
    metadata.write(package_metadata_dir)

    # Save file_metadata for this pkg
    file_metadata = FileMetadata::instantiate_from_dir(File.join(workdir, 'tpkg'))
    if file_metadata
      file_metadata[:package_file] = File.basename(package_file)
      file_metadata[:files].each do |file|
        # update file_metadata with user/group ownership and permission
        acl = files_info[file[:path]]
        file.merge!(acl) unless acl.nil?

        # update file_metadata with the checksums of decrypted files
        digest = checksums_of_decrypted_files[File.expand_path(file[:path])]
        if digest
          digests = file[:checksum][:digests]
          digests[0][:encrypted] = true
          digests[1] = {:decrypted => true, :value => digest}
        end
      end

      file = File.open(File.join(package_metadata_dir, "file_metadata.bin"), "w")
      Marshal.dump(file_metadata.to_hash, file)
      file.close
    else
      warn "Warning: package #{File.basename(package_file)} does not include file_metadata information."
    end
  end

  def requirements_for_currently_installed_package(pkgname=nil)
    requirements = []
    metadata_for_installed_packages.each do |metadata|
      if !pkgname || pkgname == metadata[:name]
        req = { :name => metadata[:name],
                :minimum_version => metadata[:version],
                :type => :tpkg }
        if metadata[:package_version]
          req[:minimum_package_version] = metadata[:package_version]
        end
        requirements << req
      end
    end
    requirements
  end

  # Adds/modifies requirements and packages arguments to add requirements
  # and package entries for currently installed packages
  # Note: the requirements and packages arguments are modified by this method
  def requirements_for_currently_installed_packages(requirements, packages)
    metadata_for_installed_packages.each do |installed_xml|
      name = installed_xml[:name]
      version = installed_xml[:version]
      # For each currently installed package we insert a requirement for
      # at least that version of the package
      req = { :name => name, :minimum_version => version, :type => :tpkg }
      requirements << req
      # Initialize the list of possible packages for this req
      if !packages[name]
        packages[name] = available_packages_that_meet_requirement(req)
      end
    end
  end

  # Define requirements for requested packages
  # Takes an array of packages: files, URLs, or basic package specs ('foo' or
  # 'foo=1.0')
  # Adds/modifies requirements and packages arguments based on parsing those
  # requests
  # Input:
  # [ 'foo-1.0.tpkg', 'http://server/pkgs/bar-2.3.pkg', 'blat=0.5' ]
  # Result:
  #   requirements << { :name => 'foo' }, packages['foo'] = { :source => 'foo-1.0.tpkg' }
  #   requirements << { :name => 'bar' }, packages['bar'] = { :source => 'http://server/pkgs/bar-2.3.pkg' }
  #   requirements << { :name => 'blat', :minimum_version => '0.5', :maximum_version => '0.5' }, packages['blat'] populated with available packages meeting that requirement
  # Note: the requirements and packages arguments are modified by this method
  # FIXME: This method has a terrible API, can we fix it?
  def parse_requests(requests, requirements, packages, options = {})
    newreqs = []

    requests.each do |request|
      puts "parse_requests processing #{request.inspect}" if @@debug

      # User specified a file or URI
      if request =~ /^http[s]?:\/\// or File.file?(request)
        req = {}
        metadata = nil
        source = nil
        localpath = nil
        if File.file?(request)
          raise "Invalid package filename #{request}" if !Tpkg::valid_pkg_filename?(request)

          puts "parse_requests treating request as a file" if @@debug

          if request !~ /\.tpkg$/
            warn "Warning: Attempting to perform the request on #{File.expand_path(request)}. This might not be a valid package file."
          end

          localpath = request
          metadata = Tpkg::metadata_from_package(request)
          source = request
        else
          puts "parse_requests treating request as a URI" if @@debug
          uri = URI.parse(request)  # This just serves as a sanity check
          # Using these File methods on a URI seems to work but is probably fragile
          source = File.dirname(request) + '/' # dirname chops off the / at the end, we need it in order to be compatible with URI.join
          pkgfile = File.basename(request)
          localpath = download(source, pkgfile, Tpkg::tempdir('download'))
          metadata = Tpkg::metadata_from_package(localpath)
          # Cleanup temp download dir
          FileUtils.rm_rf(localpath)
        end
        req[:name] = metadata[:name]
        req[:type] = :tpkg
        pkg = { :metadata => metadata, :source => source }

        newreqs << req
        # The user specified a particular package, so it is the only package
        # that can be used to meet the requirement
        packages[req[:name]] = [pkg]
      else # basic package specs ('foo' or 'foo=1.0')
        puts "parse_requests request looks like package spec" if @@debug

        req = Tpkg::parse_request(request)
        newreqs << req

        puts "Initializing the list of possible packages for this req" if @@debug
        if !packages[req[:name]]
          if !options[:installed_only]
            packages[req[:name]] = available_packages_that_meet_requirement(req)
          else
            packages[req[:name]] = installed_packages_that_meet_requirement(req)
          end
        end
      end
    end

    requirements.concat(newreqs)
    newreqs
  end

  # After calling parse_request, we should call this method
  # to check whether or not we can meet the requirements/dependencies
  # of the result packages
  def check_requests(packages)
    all_requests_satisfied = true   # whether or not all requests can be satisfied
    errors = [""]
    packages.each do |name, pkgs|
      if pkgs.empty?
        errors << ["Unable to find any packages which satisfy #{name}"]
        all_requests_satisfied = false
        next
      end

      request_satisfied = false # whether or not this request can be satisfied
      possible_errors = []
      pkgs.each do |pkg|
        good_package = true
        metadata = pkg[:metadata]
        req = { :name => metadata[:name], :type => :tpkg }
        # Quick sanity check that the package can be installed on this machine.
        puts "check_requests checking that available package for request works on this machine: #{pkg.inspect}" if @@debug
        if !package_meets_requirement?(pkg, req)
          possible_errors << "  Requested package #{metadata[:filename]} doesn't match this machine's OS or architecture"
          good_package = false
          next
        end
        # a sanity check that there is at least one package
        # available for each dependency of this package
        metadata[:dependencies].each do |depreq|
          puts "check_requests checking for available packages to satisfy dependency: #{depreq.inspect}" if @@debug
          if available_packages_that_meet_requirement(depreq).empty? && !packages_meet_requirement?(packages.values.flatten, depreq)
            possible_errors << "  Requested package #{metadata[:filename]} depends on #{depreq.inspect}, no packages that satisfy that dependency are available"
            good_package = false
          end
        end if metadata[:dependencies]
        request_satisfied = true if good_package
      end
      if !request_satisfied
        errors << ["Unable to find any packages which satisfy #{name}. Possible error(s):"]
        errors << possible_errors
        all_requests_satisfied = false
      end
    end

    if !all_requests_satisfied
      puts errors.join("\n")
      raise "Unable to satisfy the request(s).  Try running with --debug for more info"
    end
  end

  CHECK_INSTALL = 1
  CHECK_UPGRADE = 2
  CHECK_REMOVE  = 3
  def conflicting_files(package_file, mode=CHECK_INSTALL)
    metadata = Tpkg::metadata_from_package(package_file)
    pkgname = metadata[:name]

    conflicts = {}

    installed_files = files_for_installed_packages

    # Pull out the normalized paths, skipping appropriate packages based
    # on the requested mode
    installed_files_normalized = {}
    installed_files.each do |pkgfile, files|
      # Skip packages with the same name if the user is performing an upgrade
      if mode == CHECK_UPGRADE && files[:metadata][:name] == pkgname
        next
      end
      # Skip packages with the same filename if the user is removing
      if mode == CHECK_REMOVE && pkgfile == File.basename(package_file)
        next
      end
      installed_files_normalized[pkgfile] = files[:normalized]
    end

    fip = Tpkg::files_in_package(package_file)
    normalize_paths(fip)

    fip[:normalized].each do |file|
      installed_files_normalized.each do |instpkgfile, files|
        if files.include?(file)
          if !conflicts[instpkgfile]
            conflicts[instpkgfile] = []
          end
          conflicts[instpkgfile] << file
        end
      end
    end
    # The remove method actually needs !conflicts, so invert in that case
    if mode == CHECK_REMOVE
      # Flatten conflicts to an array
      flatconflicts = []
      conflicts.each_value { |files| flatconflicts.concat(files) }
      # And invert
      conflicts = fip[:normalized] - flatconflicts
    end

    conflicts
  end

  # This method is called by install and upgrade method to make sure there is
  # no conflicts between the existing pkgs and the pkgs we're about to install
  def handle_conflicting_pkgs(installed_pkgs, pkgs_to_install, options ={})
    conflicting_pkgs = []

    # check if existing pkgs have conflicts with pkgs we're about to install
    installed_pkgs.each do |pkg1|
      next if pkg1[:metadata][:conflicts].nil?
      pkg1[:metadata][:conflicts].each do | conflict |
        pkgs_to_install.each do |pkg2|
          if package_meets_requirement?(pkg2, conflict)
            conflicting_pkgs << pkg1
          end
        end
      end
    end

    # check if pkgs we're about to install conflict with existing pkgs
    pkgs_to_install.each do |pkg1|
      next if pkg1[:metadata][:conflicts].nil?
      pkg1[:metadata][:conflicts].each do | conflict |
        conflicting_pkgs |= installed_packages_that_meet_requirement(conflict)
      end
    end

    # Check if there are conflicts among the pkgs we're about to install
    # For these type of conflicts, we can't proceed, so raise exception.
    pkgs_to_install.each do |pkg1|
      # native package might not have conflicts defined so skip
      next if pkg1[:metadata][:conflicts].nil?
      pkg1[:metadata][:conflicts].each do | conflict |
        pkgs_to_install.each do |pkg2|
          if package_meets_requirement?(pkg2, conflict)
            raise "Package conflicts between #{pkg2[:metadata][:filename]} and #{pkg1[:metadata][:filename]}"
          end
        end
      end
    end

    # Report to the users if there are conflicts
    unless conflicting_pkgs.empty?
      puts "The package(s) you're trying to install conflict with the following package(s):"
      conflicting_pkgs = conflicting_pkgs.collect{|pkg|pkg[:metadata][:filename]}
      puts conflicting_pkgs.join("\n")
      if options[:force_replace]
        puts "Attemping to replace the conflicting packages."
        success = remove(conflicting_pkgs)
        return success
      else
        puts "Try removing the conflicting package(s) first, or rerun tpkg with the --force-replace option."
        return false
      end
    end
    return true
  end

  def prompt_for_conflicting_files(package_file, mode=CHECK_INSTALL)
    if !@@prompt
      return true
    end

    result = true
    conflicts = conflicting_files(package_file, mode)

    # We don't want to prompt the user for directories, so strip those out
    conflicts.each do |pkgfile, files|
      files.reject! { |file| File.directory?(file) }
    end
    conflicts.reject! { |pkgfile, files| files.empty? }

    if !conflicts.empty?
      puts "File conflicts:"
      conflicts.each do |pkgfile, files|
        files.each do |file|
          puts "#{file} (#{pkgfile})"
        end
      end
      print "Proceed? [y/N] "
      response = $stdin.gets
      if response !~ /^y/i
        result = false
      end
    end
    result
  end

  def prompt_for_install(pkgs, promptstring)
    if @@prompt
      pkgs_to_report = pkgs.select do |pkg|
        pkg[:source] != :currently_installed &&
        pkg[:source] != :native_installed
      end
      if !pkgs_to_report.empty?
        puts "The following packages will be #{promptstring}:"
        pkgs_to_report.sort(&SORT_PACKAGES).each do |pkg|
          if pkg[:source] == :native_available
            puts "Native #{os.native_pkg_to_install_string(pkg)}"
          else
            puts pkg[:metadata][:filename]
          end
        end
        return Tpkg::confirm
      end
    end
    true
  end

  # See parse_requests for format of requests
  def install(requests, passphrase=nil, options={})
    ret_val = 0
    requirements = []
    packages = {}
    lock
    parse_requests(requests, requirements, packages)
    check_requests(packages)

    core_packages = []
    requirements.each do |req|
      core_packages << req[:name] if !core_packages.include?(req[:name])
    end

    puts "install calling best_solution" if @@debug
    puts "install requirements: #{requirements.inspect}" if @@debug
    puts "install packages: #{packages.inspect}" if @@debug
    puts "install core_packages: #{core_packages.inspect}" if @@debug
    solution_packages = best_solution(requirements, packages, core_packages)
    if !solution_packages
      raise "Unable to resolve dependencies.  Try running with --debug for more info"
    end

    success = handle_conflicting_pkgs(installed_packages, solution_packages, options)
    return false if !success

    if !prompt_for_install(solution_packages, 'installed')
      unlock
      return false
    end

    # Build an array of metadata of pkgs that are already installed
    # We will use this later on to figure out what new packages have been installed/removed
    # in order to report back to the server
    already_installed_pkgs = metadata_for_installed_packages.collect{|metadata| metadata.to_hash}

    # Create array of packages (names) we have installed so far
    # We will use it later on to determine the order of how to install the packages
    installed_so_far = installed_packages.collect{|pkg| pkg[:metadata][:name]}

    while pkg = solution_packages.shift
      # get dependencies and make sure we install the packages in the correct order
      # based on the dependencies
      dependencies = nil
      if pkg[:metadata][:dependencies]
        dependencies = pkg[:metadata][:dependencies].collect { |dep| dep[:name] }.compact
        # don't install this pkg right now if its dependencies haven't been installed
        if !dependencies.empty? && !dependencies.to_set.subset?(installed_so_far.to_set)
          solution_packages.push(pkg)
          next
        end
      end

      if pkg[:source] == :currently_installed ||
         pkg[:source] == :native_installed
        # Nothing to do for packages currently installed
        warn "Skipping #{pkg[:metadata][:name]}, already installed"
      elsif pkg[:source] == :native_available
        os.install_native_package(pkg)
      else # regular tpkg that needs to be installed
        pkgfile = nil
        if File.file?(pkg[:source])
          pkgfile = pkg[:source]
        elsif File.directory?(pkg[:source])
          pkgfile = File.join(pkg[:source], pkg[:metadata][:filename])
        else
          pkgfile = download(pkg[:source], pkg[:metadata][:filename])
        end
        if File.exist?(
             File.join(@installed_directory, File.basename(pkgfile)))
          warn "Skipping #{File.basename(pkgfile)}, already installed"
        else
          if prompt_for_conflicting_files(pkgfile)
            ret_val |= unpack(pkgfile, :passphrase => passphrase)
            os.stub_native_pkg(pkg)
          end
        end
      end

      # If we're down here, it means we have installed the package. So go ahead and
      # update the list of packages we installed so far
      installed_so_far << pkg[:metadata][:name]
    end  # end while loop

    # log changes
    currently_installed = metadata_for_installed_packages.collect{|metadata| metadata.to_hash}
    newly_installed = currently_installed - already_installed_pkgs
    log_changes({:newly_installed => newly_installed})

    # send udpate back to reporting server
    unless @report_server.nil?
      options = {:newly_installed => newly_installed, :currently_installed => currently_installed}
      send_update_to_server(options)
    end
    unlock
    return ret_val
  end

  def report
    unless report_server
      puts "no report server given"
      return 1
    end

    lock
    send_update_to_server || 1
  ensure
    unlock if @locks > 0
  end

  # This method can also be used for doing downgrade
  def upgrade(requests=nil, passphrase=nil, options={})
    downgrade = options[:downgrade] || false
    ret_val = 0
    requirements = []
    packages = {}
    core_packages = []
    lock
    has_updates = false	 # flags whether or not there was at least one actual package that
                         # get updated

    # If the user specified some specific packages to upgrade in requests
    # then we look for upgrades for just those packages (and any necessary
    # dependency upgrades).  If the user did not specify specific packages
    # then we look for upgrades for all currently installed packages.

    if requests
      puts "Upgrading requested packages only" if @@debug
      parse_requests(requests, requirements, packages)
      check_requests(packages)
      additional_requirements = []
      requirements.each do |req|
        core_packages << req[:name] if !core_packages.include?(req[:name])

        # When doing downgrade, we don't want to include the package being
        # downgrade as the requirements. Otherwise, we won't be able to downgrade it
        unless downgrade
          additional_requirements.concat(
            requirements_for_currently_installed_package(req[:name]))
        end

        # Initialize the list of possible packages for this req
        if !packages[req[:name]]
          packages[req[:name]] = available_packages_that_meet_requirement(req)
        end
        # Remove preference for currently installed package
        packages[req[:name]].each do |pkg|
          if pkg[:source] == :currently_installed
            pkg[:prefer] = false
          end
        end

        # Look for pkgs that might depend on the pkg we're upgrading,
        # and add them to our list of requirements. We need to make sure that we can still
        # satisfy the dependency requirements if we were to do the upgrade.
        metadata_for_installed_packages.each do | metadata |
          metadata[:dependencies].each do | dep |
            if dep[:name] == req[:name]
              # Package metadata is almost usable as-is as a req, just need to
              # set :type
              # and remove filename (since we're not explicitly requesting the exact file)
              addreq = metadata.to_hash.clone
              addreq[:type] = :tpkg
              addreq[:filename] = nil
              additional_requirements << addreq
            end
          end if metadata[:dependencies]
        end
      end
      requirements.concat(additional_requirements)
      requirements.uniq!
    else
      puts "Upgrading all packages" if @@debug
      requirements_for_currently_installed_packages(requirements, packages)
      # Remove preference for currently installed packages
      packages.each do |name, pkgs|
        core_packages << name if !core_packages.include?(name)
        pkgs.each do |pkg|
          if pkg[:source] == :currently_installed
            pkg[:prefer] = false
          end
        end
      end
    end

    puts "upgrade calling best_solution" if @@debug
    puts "upgrade requirements: #{requirements.inspect}" if @@debug
    puts "upgrade packages: #{packages.inspect}" if @@debug
    puts "upgrade core_packages: #{core_packages.inspect}" if @@debug
    solution_packages = best_solution(requirements, packages, core_packages)

    if solution_packages.nil?
      raise "Unable to find solution for upgrading. Please verify that you specified the correct package(s) for upgrade.  Try running with --debug for more info"
    end

    success = handle_conflicting_pkgs(installed_packages, solution_packages, options)
    return false if !success

    if downgrade
      prompt_action = 'downgraded'
    else
      prompt_action = 'upgraded'
    end
    if !prompt_for_install(solution_packages, prompt_action)
      unlock
      return false
    end

    # Build an array of metadata of pkgs that are already installed
    # We will use this later on to figure out what new packages have been installed/removed
    # in order to report back to the server
    already_installed_pkgs = metadata_for_installed_packages.collect{|metadata| metadata.to_hash}

    removed_pkgs = [] # keep track of what we removed so far
    while pkg = solution_packages.shift
      if pkg[:source] == :currently_installed ||
         pkg[:source] == :native_installed
        # Nothing to do for packages currently installed
      elsif pkg[:source] == :native_available
        os.upgrade_native_package(pkg)
        has_updates = true
        @available_native_packages.delete(pkg[:metadata][:name]) # to have the status of this native package reloaded
      else  # tpkg
        pkgfile = nil
        if File.file?(pkg[:source])
          pkgfile = pkg[:source]
        elsif File.directory?(pkg[:source])
          pkgfile = File.join(pkg[:source], pkg[:metadata][:filename])
        else
          pkgfile = download(pkg[:source], pkg[:metadata][:filename])
        end

        if !Tpkg::valid_pkg_filename?(pkgfile)
          raise "Invalid package filename: #{pkgfile}"
        end

        if prompt_for_conflicting_files(pkgfile, CHECK_UPGRADE)
          # If the old and new packages have overlapping externals then flag
          # them to be skipped so that the external isn't removed and then
          # immediately re-added
          oldpkgs = installed_packages_that_meet_requirement({:name => pkg[:metadata][:name], :type => :tpkg})
          externals_to_skip = []
          pkg[:metadata][:externals].each do |external|
            if oldpkgs.all? {|oldpkg| oldpkg[:metadata][:externals] && oldpkg[:metadata][:externals].include?(external)}
              externals_to_skip << external
            end
          end if pkg[:metadata][:externals] && !oldpkgs.empty?

          # Remove the old package if we haven't done so
          unless oldpkgs.nil? or oldpkgs.empty? or removed_pkgs.include?(pkg[:metadata][:name])
            remove([pkg[:metadata][:name]], :upgrade => true, :externals_to_skip => externals_to_skip)
            removed_pkgs << pkg[:metadata][:name]
          end

          # determine if we can unpack the new version package now by
          # looking to see if all of its dependencies have been installed
          can_unpack = true
          pkg[:metadata][:dependencies].each do | dep |
            iptmr = installed_packages_that_meet_requirement(dep)
            if iptmr.nil? || iptmr.empty?
               can_unpack = false
               # Can't unpack yet. so push it back in the solution_packages queue
               solution_packages.push(pkg)
               break
            end
          end if pkg[:metadata][:dependencies]
          if can_unpack
            is_doing_upgrade = true if removed_pkgs.include?(pkg[:metadata][:name])
            ret_val |= unpack(pkgfile, :passphrase => passphrase, :externals_to_skip => externals_to_skip,
                                       :is_doing_upgrade => is_doing_upgrade)
            os.stub_native_pkg(pkg)
          end
          has_updates = true
        end
      end
    end

    # log changes
    currently_installed = metadata_for_installed_packages.collect{|metadata| metadata.to_hash}
    newly_installed = currently_installed - already_installed_pkgs
    removed = already_installed_pkgs - currently_installed
    log_changes({:newly_installed => newly_installed, :removed => removed})

    # send update back to reporting server
    if !has_updates
      puts "No updates available"
    elsif !@report_server.nil?
      options = {:newly_installed => newly_installed, :removed => removed,
                 :currently_installed => currently_installed}
      send_update_to_server(options)
    end

    unlock
    return ret_val
  end

  def remove(requests=nil, options={})
    ret_val = 0
    lock

    if options[:upgrade]
       ENV['TPKG_ACTION'] = "upgrade"
    else
       ENV['TPKG_ACTION'] = "remove"
    end

    packages_to_remove = nil
    if requests
      requests.uniq! if requests.is_a?(Array)
      packages_to_remove = []
      requests.each do |request|
        req = Tpkg::parse_request(request)
        packages_to_remove.concat(installed_packages_that_meet_requirement(req))
      end
    else
      packages_to_remove = installed_packages_that_meet_requirement
    end

    if packages_to_remove.empty?
      puts "No matching packages"
      unlock
      return false
    end

    # Build an array of metadata of pkgs that are already installed
    # We will use this later on to figure out what new packages have been installed/removed
    # in order to report back to the server
    already_installed_pkgs = metadata_for_installed_packages.collect{|metadata| metadata.to_hash}

    # If user want to remove all the dependent pkgs, then go ahead
    # and include them in our array of things to remove
    if options[:remove_all_dep]
      packages_to_remove |= get_dependents(packages_to_remove)
    elsif options[:remove_all_prereq]
      puts "Attempting to remove #{packages_to_remove.map do |pkg| pkg[:metadata][:filename] end} and all prerequisites."
      # Get list of dependency prerequisites
      ptr = packages_to_remove | get_prerequisites(packages_to_remove)
      pkg_files_to_remove = ptr.map { |pkg| pkg[:metadata][:filename] }

      # see if any other packages depends on the ones we're about to remove
      # If so, we can't remove that package + any of its prerequisites
      non_removable_pkg_files = []
      metadata_for_installed_packages.each do |metadata|
        next if pkg_files_to_remove.include?(metadata[:filename])
        next if metadata[:dependencies].nil?
        metadata[:dependencies].each do |req|
          # We ignore native dependencies because there is no way a removal
          # can break a native dependency, we don't support removing native
          # packages.
          if req[:type] != :native
            iptmr = installed_packages_that_meet_requirement(req)
            if iptmr.all? { |pkg| pkg_files_to_remove.include?(pkg[:metadata][:filename]) }
              non_removable_pkg_files |= iptmr.map{ |pkg| pkg[:metadata][:filename]}
              non_removable_pkg_files |= get_prerequisites(iptmr).map{ |pkg| pkg[:metadata][:filename]}
            end
          end
        end
      end
      # Generate final list of packages that we should remove.
      packages_to_remove = {}
      ptr.each do | pkg |
        next if pkg[:source] == :native or pkg[:source] == :native_installed
        next if non_removable_pkg_files.include?(pkg[:metadata][:filename])
        packages_to_remove[pkg[:metadata][:filename]] = pkg
      end
      packages_to_remove = packages_to_remove.values
      if packages_to_remove.empty?
        raise "Can't remove request package because other packages depend on it."
      elsif !non_removable_pkg_files.empty?
        puts "Can't remove #{non_removable_pkg_files.inspect} because other packages depend on them."
      end
    # Check that this doesn't leave any dependencies unresolved
    elsif !options[:upgrade]
      pkg_files_to_remove = packages_to_remove.map { |pkg| pkg[:metadata][:filename] }
      metadata_for_installed_packages.each do |metadata|
        next if pkg_files_to_remove.include?(metadata[:filename])
        next if metadata[:dependencies].nil?
        metadata[:dependencies].each do |req|
          # We ignore native dependencies because there is no way a removal
          # can break a native dependency, we don't support removing native
          # packages.
          # FIXME: Should we also consider :native_installed?
          if req[:type] != :native
            if installed_packages_that_meet_requirement(req).all? { |pkg| pkg_files_to_remove.include?(pkg[:metadata][:filename]) }
              raise "Package #{metadata[:filename]} depends on #{req[:name]}"
            end
          end
        end
      end
    end

    # Confirm with the user
    # upgrade does its own prompting
    if @@prompt && !options[:upgrade]
      puts "The following packages will be removed:"
      packages_to_remove.each do |pkg|
        puts pkg[:metadata][:filename]
      end
      unless Tpkg::confirm
        unlock
        return false
      end
    end

    # Stop the services if there's init script
    if !options[:upgrade] && !options[:skip_remove_stop]
      packages_to_remove.each do |pkg|
       init_scripts_metadata = init_scripts(pkg[:metadata])
       if init_scripts_metadata && !init_scripts_metadata.empty?
         execute_init_for_package(pkg, 'stop')
       end
      end
    end

    # Remove the packages
    packages_to_remove.each do |pkg|
      pkgname = pkg[:metadata][:name]
      package_file = File.join(@installed_directory, pkg[:metadata][:filename])

      topleveldir = Tpkg::package_toplevel_directory(package_file)
      workdir = Tpkg::tempdir(topleveldir, @tmp_directory)
      extract_tpkg_tar_command = Tpkg::cmd_to_extract_tpkg_tar(package_file, topleveldir)
      system("#{extract_tpkg_tar_command} | #{@tar} #{@@taroptions} -C #{workdir} -xpf -")

      # Run preremove script
      if File.exist?(File.join(workdir, 'tpkg', 'preremove'))
        pwd = Dir.pwd
        # chdir into the working directory so that the user can specify a
        # relative path to their file/script.
        Dir.chdir(File.join(workdir, 'tpkg'))

        # Warn the user about non-executable files, as system will just
        # silently fail and return if that's the case.
        if !File.executable?(File.join(workdir, 'tpkg', 'preremove'))
          warn "Warning: preremove script for #{File.basename(package_file)} is not executable, execution will likely fail"
        end
        if @force
          system(File.join(workdir, 'tpkg', 'preremove')) || warn("Warning: preremove for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
        else
          system(File.join(workdir, 'tpkg', 'preremove')) || raise("Error: preremove for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
        end

        # Switch back to our previous directory
        Dir.chdir(pwd)
      end

      remove_init_scripts(pkg[:metadata])
      remove_crontabs(pkg[:metadata])

      # Run any externals
      pkg[:metadata][:externals].each do |external|
        if !options[:externals_to_skip] || !options[:externals_to_skip].include?(external)
          run_external(pkg[:metadata][:filename], :remove, external[:name], external[:data])
        end
      end if pkg[:metadata][:externals]

      # determine which configuration files have been modified
      modified_conf_files = []
      file_metadata = file_metadata_for_installed_packages([pkg[:metadata][:filename]]).values[0]
      file_metadata[:files].each do |file|
        if file[:config]
          # get expected checksum. For files that were encrypted, we're interested in the
          # checksum of the decrypted version
          chksum_expected = file[:checksum][:digests].first[:value]
          file[:checksum][:digests].each do | digest |
            if digest[:decrypted] == true
              chksum_expected = digest[:value].to_s
            end
          end
          fp = normalize_path(file[:path])
          chksum_actual = Digest::SHA256.hexdigest(File.read(fp))
          if chksum_actual != chksum_expected
            modified_conf_files << fp
          end
        end
      end if file_metadata

      # Remove files
      files_to_remove = conflicting_files(package_file, CHECK_REMOVE)
      # Reverse the order of the files, as directories will appear first
      # in the listing but we want to remove any files in them before
      # trying to remove the directory.
      files_to_remove.reverse.each do |file|
        # don't remove conf files that have been modified
        next if modified_conf_files.include?(file)
        begin
          if File.symlink?(file) || !File.directory?(file)
            File.delete(file)
          else
            begin
              Dir.delete(file)
            rescue SystemCallError => e
              # Directory isn't empty
              #puts e.message
            end
          end
        rescue Errno::ENOENT
          warn "File #{file} from package #{File.basename(package_file)} missing during remove"
        # I know it's bad to have a generic rescue for all exceptions, but in this case, there
        # can be many things that might go wrong when removing a file. We don't want tpkg
        # to crash and leave the packages in a bad state. It's better to catch
        # all exceptions and give the user some warnings.
        rescue
          warn "Failed to remove file #{file}."
        end
      end

      # Run postremove script
      if File.exist?(File.join(workdir, 'tpkg', 'postremove'))
        pwd = Dir.pwd
        # chdir into the working directory so that the user can specify a
        # relative path to their file/script.
        Dir.chdir(File.join(workdir, 'tpkg'))

        # Warn the user about non-executable files, as system will just
        # silently fail and return if that's the case.
        if !File.executable?(File.join(workdir, 'tpkg', 'postremove'))
          warn "Warning: postremove script for #{File.basename(package_file)} is not executable, execution will likely fail"
        end
        # Note this only warns the user if the postremove fails, it does
        # not raise an exception like we do if preremove fails.  Raising
        # an exception would leave the package's files removed but the
        # package still registered as installed, which does not seem
        # desirable.  We could reinstall the package's files and raise an
        # exception, but this seems the best approach to me.
        system(File.join(workdir, 'tpkg', 'postremove')) || warn("Warning: postremove for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
        ret_val = POSTREMOVE_ERR if !$?.success?

        # Switch back to our previous directory
        Dir.chdir(pwd)
      end

      File.delete(package_file)

      # delete metadata dir of this package
      package_metadata_dir = File.join(@metadata_directory, File.basename(package_file, File.extname(package_file)))
      FileUtils.rm_rf(package_metadata_dir)

      os.remove_native_stub_pkg(pkg)

      # Cleanup
      FileUtils.rm_rf(workdir)
    end

    # log changes
    currently_installed = metadata_for_installed_packages.collect{|metadata| metadata.to_hash}
    removed = already_installed_pkgs - currently_installed
    log_changes({:removed => removed})

    # send update back to reporting server
    unless @report_server.nil? || options[:upgrade]
      options = {:removed => removed, :currently_installed => currently_installed}
      send_update_to_server(options)
    end

    unlock
    return ret_val
  end

  def verify_file_metadata(requests)
    results = {}
    packages = []
    # parse request to determine what packages the user wants to verify
    requests.each do |request|
      req = Tpkg::parse_request(request)
      packages.concat(installed_packages_that_meet_requirement(req).collect { |pkg| pkg[:metadata][:filename] })
    end

    # loop through each package, and verify checksum, owner, group and perm of each file that was installed
    packages.each do | package_file |
      puts "Verifying #{package_file}"
      package_full_name = File.basename(package_file, File.extname(package_file))

      # Extract checksum.xml from the package
      checksum_xml = nil

      # get file_metadata from the installed package
      file_metadata = FileMetadata::instantiate_from_dir(File.join(@metadata_directory, package_full_name))
      if !file_metadata
        errors = []
        errors << "Can't find file metadata. Most likely this is because the package was created before the verify feature was added"
        results[package_file] = errors
        return results
      end

      # verify installed files match their checksum
      file_metadata[:files].each do |file|
        errors = []
        gid_expected, uid_expected, perms_expected, chksum_expected = nil
        fp = file[:path]

        # get expected checksum. For files that were encrypted, we're interested in the
        # checksum of the decrypted version
        if file[:checksum]
          chksum_expected = file[:checksum][:digests].first[:value]
          file[:checksum][:digests].each do | digest |
            if digest[:decrypted] == true
              chksum_expected = digest[:value].to_s
            end
          end
        end

        # get expected acl values
        if file[:uid]
          uid_expected = file[:uid].to_i
        end
        if file[:gid]
          gid_expected = file[:gid].to_i
        end
        if file[:perms]
          perms_expected = file[:perms].to_s
        end

        fp  = normalize_path(fp)

        # can't handle symlink
        if File.symlink?(fp)
          next
        end

        # check if file exist
        if !File.exists?(fp)
          errors << "File is missing"
        else
          # get actual values
          chksum_actual = Digest::SHA256.hexdigest(File.read(fp)) if File.file?(fp)
          uid_actual = File.stat(fp).uid
          gid_actual = File.stat(fp).gid
          perms_actual = File.stat(fp).mode.to_s(8)
        end

        if !chksum_expected.nil? && !chksum_actual.nil? && chksum_expected != chksum_actual
          errors << "Checksum doesn't match (Expected: #{chksum_expected}, Actual: #{chksum_actual}"
        end

        if !uid_expected.nil? && !uid_actual.nil? && uid_expected != uid_actual
          errors << "uid doesn't match (Expected: #{uid_expected}, Actual: #{uid_actual}) "
        end

        if !gid_expected.nil? && !gid_actual.nil? && gid_expected != gid_actual
          errors << "gid doesn't match (Expected: #{gid_expected}, Actual: #{gid_actual})"
        end

        if !perms_expected.nil? && !perms_actual.nil? && perms_expected != perms_actual
          errors << "perms doesn't match (Expected: #{perms_expected}, Actual: #{perms_actual})"
        end

        results[fp] = errors
      end
    end
    return results
  end

  def execute_init(options, *moreoptions)
    ret_val = 0
    packages_to_execute_on = []
    if options.is_a?(Hash)
      action = options[:cmd]
      requested_packages = options[:packages]
      requested_init_scripts = options[:scripts]
    else # for backward compatibility
      action = moreoptions[0]
      requested_packages = options
    end

    # if user specified no packages, then assume all
    if requested_packages.nil?
      packages_to_execute_on = installed_packages_that_meet_requirement(nil)
    else
      requested_packages.uniq!
      requested_packages.each do |request|
        req = Tpkg::parse_request(request)
        packages_to_execute_on.concat(installed_packages_that_meet_requirement(req))
      end
    end

    if packages_to_execute_on.empty?
      warn "Warning: Unable to find package(s) \"#{requested_packages.join(",")}\"."
    else
      packages_to_execute_on.each do |pkg|
        ret_val |= execute_init_for_package(pkg, action, requested_init_scripts)
      end
    end
    return ret_val
  end

  def execute_init_for_package(pkg, action, requested_init_scripts = nil)
    ret_val = 0

    # Get init scripts metadata for the given package
    init_scripts_metadata = init_scripts(pkg[:metadata])
    # warn if there's no init script and then return
    if init_scripts_metadata.nil? || init_scripts_metadata.empty?
      warn "Warning: There is no init script for #{pkg[:metadata][:name]}."
      return 1
    end

    # convert the init scripts metadata  to an array of { path => value, start => value}
    # so that we can order them based on their start value. This is necessary because
    # we need to execute the init scripts in correct order.
    init_scripts = []
    init_scripts_metadata.each do | installed_path, init_info |
      init = {}
      init[:path] = installed_path
      init[:start] = init_info[:init][:start] || 0

      # if user requests specific init scripts, then only include those
      if requested_init_scripts.nil? or
         requested_init_scripts && requested_init_scripts.include?(File.basename(installed_path))
        init_scripts << init
      end
    end

    if requested_init_scripts && init_scripts.empty?
      warn "Warning: There are no init scripts that satisfy your request: #{requested_init_scripts.inspect} for package #{pkg[:metadata][:name]}."
    end

    # Reverse order if doing stop.
    if action == "stop"
      ordered_init_scripts = init_scripts.sort{ |a,b| b[:start] <=> a[:start] }
    else
      ordered_init_scripts = init_scripts.sort{ |a,b| a[:start] <=> b[:start] }
    end

    ordered_init_scripts.each do |init_script|
      installed_path = init_script[:path]
      # Warn the user about non-executable files, as system will just
      # silently fail and return if that's the case.
      if !File.executable?(installed_path)
        warn "Warning: init script for #{pkg[:metadata][:name]} is not executable, execution will likely fail"
      end
      system("#{installed_path} #{action}")
      ret_val = INITSCRIPT_ERR if !$?.success?
    end
    return ret_val
  end

  # We can't safely calculate a set of dependencies and install the
  # resulting set of packages if another user is manipulating the installed
  # packages at the same time.  These methods lock and unlock the package
  # system so that only one user makes changes at a time.
  def lock
    if @locks > 0
      @locks += 1
      return
    end
    if File.directory?(@lock_directory)
      if @lockforce
        warn "Forcing lock removal"
        FileUtils.rm_rf(@lock_directory)
      else
        # Remove old lock files on the assumption that they were left behind
        # by a previous failed run
        if File.mtime(@lock_directory) < Time.at(Time.now - 60 * 60 * 2)
          warn "Lock is more than 2 hours old, removing"
          FileUtils.rm_rf(@lock_directory)
        end
      end
    end
    begin
      Dir.mkdir(@lock_directory)
      File.open(@lock_pid_file, 'w') { |file| file.puts($$) }
      @locks = 1
    rescue Errno::EEXIST
      lockpid = ''
      begin
        File.open(@lock_pid_file) { |file| lockpid = file.gets.chomp }
      rescue Errno::ENOENT
      end

      # check that the process is actually running
      # if not, clean up old lock and attemp to obtain lock again
      if Tpkg::process_running?(lockpid)
        raise "tpkg repository locked by another process (with PID #{lockpid})"
      else
        FileUtils.rm_rf(@lock_directory)
        lock
      end
    end
  end

  def unlock
    if @locks == 0
      warn "unlock called but not locked, that probably shouldn't happen"
      return
    end
    @locks -= 1
    if @locks == 0
      FileUtils.rm_rf(@lock_directory)
    end
  end

  # Build a dependency map of currently installed packages
  # For example, if we have pkgB and pkgC which depends on pkgA, then
  # the dependency map would look like this:
  # "pkgA.tpkg" => [{pkgB metadata}, {pkgC metadata}]
  def get_dependency_mapping
    dependency_mapping = {}
    installed_packages.each do | pkg |
      metadata = pkg[:metadata]

      # Get list of pkgs that this pkg depends on
      next if metadata[:dependencies].nil?
      depended_on = []
      metadata[:dependencies].each do |req|
        next if req[:type] == :native
        depended_on |= installed_packages_that_meet_requirement(req)
      end

      # populate the depencency map
      depended_on.each do | req_pkg |
        dependency_mapping[req_pkg[:metadata][:filename]] ||= []
        dependency_mapping[req_pkg[:metadata][:filename]] << pkg
      end
    end
    return dependency_mapping
  end

  # Given a list of packages, return a list of dependents packages
  def get_dependents(pkgs)
    dependents = []
    to_check = pkgs.map { |pkg| pkg[:metadata][:filename] }
    dependency = get_dependency_mapping
    while pkgfile = to_check.pop
      pkgs = dependency[pkgfile.to_s]
      next if pkgs.nil?
      dependents |= pkgs
      to_check |= pkgs.map { |pkg| pkg[:metadata][:filename] }
    end
    return dependents
  end

  # Given a list of packages, return a list of all their prerequisite dependencies
  # Example: If pkgA depends on pkgB, and pkgB depends on pkgC, then calling this
  # method on pkgA will returns pkgB and pkgC
  # Assumption: There is no cyclic dependency
  def get_prerequisites(pkgs)
    pre_reqs = []
    to_check = pkgs.clone
    while pkg = to_check.pop
      next if pkg[:metadata][:dependencies].nil?
      pkg[:metadata][:dependencies].each do | dep |
        pre_req = installed_packages_that_meet_requirement(dep)
        pre_reqs |= pre_req
        to_check |= pre_req
      end
    end
    return pre_reqs
  end

  # print out history packages installation/remove
  def installation_history
    if !File.exists?(File.join(@log_directory,'changes.log'))
      puts "Tpkg history log does not exist."
      return GENERIC_ERR
    end
    IO.foreach(File.join(@log_directory,'changes.log')) do |line|
      puts line
    end
  end

  # Download packages that meet the requests specified by the user.
  # Packages are downloaded into the current directory or into the directory
  # specified in options[:out]
  def download_pkgs(requests, options={})
    output_dir = options[:out] || Dir.pwd
    FileUtils.mkdir_p(output_dir)

    requirements = []
    packages = {}
    original_dir = Dir.pwd

    workdir = Tpkg::tempdir("tpkg_download")
    # FIXME: should use begin/ensure to make sure we chdir back when done
    # But I also wonder why we have to chdir at all...
    Dir.chdir(workdir)
    parse_requests(requests, requirements, packages)
    packages = packages.values.flatten
    if packages.size < 1
      puts "Unable to find any packages that satisfy your request.  Try running with --debug for more info"
      Dir.chdir(original_dir)
      return GENERIC_ERR
    end

    # Confirm with user what packages will be downloaded
    packages.delete_if{|pkg|pkg[:source] !~ /^http/}
    puts "The following packages will be downloaded:"
    packages.each do |pkg|
      puts "#{pkg[:metadata][:filename]} (source: #{pkg[:source]})"
    end
    if @@prompt && !Tpkg::confirm
      Dir.chdir(original_dir)
      return 0
    end

    err_code = 0
    puts "Downloading to #{output_dir}"
    packages.each do |pkg|
      puts "Downloading #{pkg[:metadata][:filename]}"
      begin
        downloaded_file = download(pkg[:source], pkg[:metadata][:filename], Dir.pwd, false)
        # copy downloaded files over to destination
        FileUtils.cp(downloaded_file, output_dir)
      rescue
        warn "Warning: unable to download #{pkg[:metadata][:filename]} to #{output_dir}"
        err_code = GENERIC_ERR
      end
    end

    # clean up working directory
    FileUtils.rm_rf(workdir)

    Dir.chdir(original_dir)
    return err_code
  end

  # TODO: figure out what other methods above can be turned into protected methods
  protected
  # log changes of pkgs that were installed/removed
  def log_changes(options={})
    msg = ""
    user = Etc.getpwuid.name
    newly_installed = removed = []
    newly_installed = options[:newly_installed] if options[:newly_installed]
    removed = options[:removed] if options[:removed]
    removed.each do |pkg|
      msg = "#{msg}#{Time.new} #{pkg[:filename]} was removed by #{user}\n"
    end
    newly_installed.each do |pkg|
      msg = "#{msg}#{Time.new} #{pkg[:filename]} was installed by #{user}\n"
    end

    msg.lstrip!
    unless msg.empty?
      File.open(File.join(@log_directory,'changes.log'), 'a') {|f| f.write(msg) }
    end
  end

  def send_update_to_server(options={})
    request = {"client"=>os.fqdn}
    request[:user] = Etc.getpwuid.name
    request[:tpkg_home] = ENV['TPKG_HOME']

    if options[:currently_installed]
      currently_installed = options[:currently_installed]
    else
      currently_installed = metadata_for_installed_packages.collect{|metadata| metadata.to_hash}
    end

    # Figure out list of packages that were already installed, newly installed and newly removed
    if options[:newly_installed]
      newly_installed = options[:newly_installed]
      request[:newly_installed] = URI.escape(YAML.dump(newly_installed))
      already_installed = currently_installed - newly_installed
    else
      already_installed = currently_installed
    end
    request[:already_installed] = URI.escape(YAML.dump(already_installed))

    if options[:removed]
      removed = options[:removed]
      request[:removed] = URI.escape(YAML.dump(removed))
    end

    begin
      response = nil
      # Need to set timeout otherwise tpkg can hang for a long time when having
      # problem talking to the reporter server.
      # I can't seem get net-ssh timeout to work so we'll just handle the timeout ourselves
      timeout(CONNECTION_TIMEOUT) do
        update_uri =  URI.parse("#{@report_server}")
        http = gethttp(update_uri)
        post = Net::HTTP::Post.new(update_uri.path)
        post.set_form_data(request)
        response = http.request(post)
      end

      case response
      when Net::HTTPSuccess
       puts "Successfully send update to reporter server"
       return 0
      else
        $stderr.puts response.body
        #response.error!
        # just ignore error and give user warning
        puts "Failed to send update to reporter server"
      end
    rescue Timeout::Error
      puts "Timed out when trying to send update to reporter server"
    rescue
      puts "Failed to send update to reporter server"
    end
  end
end
