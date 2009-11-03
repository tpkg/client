##############################################################################
# tpkg package management system library
# Copyright 2009, AT&T Interactive
# License: MIT (http://www.opensource.org/licenses/mit-license.php)
##############################################################################

STDOUT.sync = STDERR.sync = true # All outputs/prompts to the kernel ASAP

# When we build the tpkg packages we put this file in
# /usr/lib/ruby/site_ruby/1.8/ or similar and then the rest of the ruby
# files (versiontype.rb, deployer.rb, etc) into
# /usr/lib/ruby/site_ruby/1.8/tpkg/
# We need to tell Ruby to search that tpkg subdirectory.
# The alternative is to specify the subdirectory in the require
# (require 'tpkg/versiontype' for example), but tpkg is also the name
# of the executable script so we can't create a subdirectory here named
# tpkg.  If we put the subdir in the require lines then users couldn't
# run tpkg directly from an svn working copy.
tpkglibdir = File.join(File.dirname(__FILE__), 'tpkg')
if File.directory?(tpkglibdir)
  $:.unshift(tpkglibdir)
end

begin
  # Try loading facter w/o gems first so that we don't introduce a
  # dependency on gems if it is not needed.
  require 'facter'         # Facter
rescue LoadError
  require 'rubygems'
  require 'facter'
end
require 'digest/sha2'    # Digest::SHA256#hexdigest, etc.
require 'uri'            # URI
require 'net/http'       # Net::HTTP
require 'net/https'      # Net::HTTP#use_ssl, etc.
require 'time'           # Time#httpdate
require 'rexml/document' # REXML::Document
require 'fileutils'      # FileUtils.cp, rm, etc.
require 'tempfile'       # Tempfile
require 'find'           # Find
require 'etc'            # Etc.getpwnam, getgrnam
require 'openssl'        # OpenSSL
require 'open3'          # Open3
require 'versiontype'    # Version
require 'deployer'
require 'set'

class Tpkg
  
  VERSION = '1.13'
  
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
  TARNAMES = ['tar', 'gtar', 'gnutar', 'bsdtar']
  def self.find_tar
    if !@@tar
      catch :tar_found do
        ENV['PATH'].split(':').each do |path|
          TARNAMES.each do |tarname|
            if File.executable?(File.join(path, tarname))
              IO.popen("#{File.join(path, tarname)} --version 2>/dev/null") do |pipe|
                pipe.each_line do |line|
                  if line.include?('GNU tar') || line.include?('bsdtar')
                    @@tar = File.join(path, tarname)
                    throw :tar_found
                  end
                end
              end
            end
          end
        end
        # Raise an exception if we didn't find a suitable tar
        raise "Unable to find GNU tar or bsdtar in PATH"
      end
    end
    @@tar.dup
  end
  def self.clear_cached_tar
    @@tar = nil
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
    end
    tmpfile.write(MAGIC)
    tmpfile.write(salt)
    tmpfile.write(c.update(IO.read(filename)) + c.final)
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
    end
    tmpfile.write(c.update(file.read) + c.final)
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
  REQUIRED_FIELDS = ['name', 'version', 'maintainer']
  def self.make_package(pkgsrcdir, passphrase=nil)
    pkgfile = nil
    
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
      
      # Open the main package config file
      tpkg_xml = REXML::Document.new(File.open(File.join(tpkgdir, 'tpkg.xml')))
      
      # Raise an exception if any required fields are not in tpkg.xml or empty
      # This doesn't serve any real purpose (since a user could make a package
      # through other means), it just helps warn the user that they're making
      # a bad package.
      REQUIRED_FIELDS.each do |reqfield|
        if !tpkg_xml.elements["/tpkg/#{reqfield}"]
          raise "Required field #{reqfield} not found"
        elsif !tpkg_xml.elements["/tpkg/#{reqfield}"].text ||
              tpkg_xml.elements["/tpkg/#{reqfield}"].text.empty?
          raise "Required field #{reqfield} is empty"
        end
      end
     
      filemetadata_xml = get_filemetadata_from_directory(tpkgdir) 
      file = File.new(File.join(tpkgdir, "file_metadata.xml"), "w")      
      filemetadata_xml.write(file)
      file.close
      
      tpkg_xml.elements.each('/tpkg/files/file') do |tpkgfile|
        tpkg_path = tpkgfile.elements['path'].text
        working_path = nil
        if tpkg_path[0,1] == File::SEPARATOR
          working_path = File.join(tpkgdir, 'root', tpkg_path)
        else
          working_path = File.join(tpkgdir, 'reloc', tpkg_path)
        end
        # Raise an exception if any files listed in tpkg.xml can't be found
        if !File.exist?(working_path) && !File.symlink?(working_path)
          raise "File #{tpkgfile.elements['path'].text} referenced in tpkg.xml but not found"
        end
        
        # Encrypt any files marked for encryption
        if tpkgfile.elements['encrypt']
          if tpkgfile.elements['encrypt'].attribute('precrypt') &&
             tpkgfile.elements['encrypt'].attribute('precrypt').value == 'true'
            verify_precrypt_file(working_path)
          else
            if passphrase.nil?
              raise "Package requires encryption but supplied passphrase is nil"
            end
            encrypt(tpkg_xml.elements['/tpkg/name'].text, working_path, passphrase)
          end
        end
      end
      
      # Make up a final filename and directory name for the package
      name = tpkg_xml.elements['/tpkg/name'].text
      if name =~ /\s/
        raise "Package name cannot contain whitespace. Consider changing \"#{name}\" to \"#{name.gsub(/\s+/, "_")}\"."
      end
      version = tpkg_xml.elements['/tpkg/version'].text
      packageversion = nil
      if tpkg_xml.elements['/tpkg/package_version'] && !tpkg_xml.elements['/tpkg/package_version'].text.empty?
        packageversion = tpkg_xml.elements['/tpkg/package_version'].text
      end
      package_filename = "#{name}-#{version}"
      if packageversion
        package_filename << "-#{packageversion}"
      end
      package_directory = File.join(workdir, package_filename)
      Dir.mkdir(package_directory)
      pkgfile = File.join(File.dirname(pkgsrcdir), package_filename + '.tpkg')
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
      
      # Tar up the tpkg directory
      tpkgfile = File.join(package_directory, 'tpkg.tar')
      system("#{find_tar} -C #{workdir} -cf #{tpkgfile} tpkg") || raise("tpkg.tar creation failed")
      
      # Checksum the tarball
      # Older ruby version doesn't support this
      # digest = Digest::SHA256.file(tpkgfile).hexdigest 
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
    # FIXME: This is so lame, to read the whole package to get the
    # first filename.  Blech.
    IO.popen("#{find_tar} -tf #{package_file}") do |pipe|
      toplevel = pipe.gets.chomp
      # Avoid SIGPIPE, if we don't sink the rest of the output from tar
      # then tar ends up getting SIGPIPE when it tries to write to the
      # closed pipe and exits with error, which causes us to throw an
      # exception down below here when we check the exit status.
      pipe.read
    end
    if !$?.success?
      raise "Error reading top level directory from #{package_file}"
    end
    # Strip off the trailing slash
    toplevel.sub!(Regexp.new("#{File::SEPARATOR}$"), '')
    if toplevel.include?(File::SEPARATOR)
      raise "Package directory structure of #{package_file} unexpected, top level is more than one directory deep"
    end
    toplevel
  end

  def self.get_filemetadata_from_directory(tpkgdir)
    filemetadata_xml = REXML::Document.new
    filemetadata_xml << REXML::Element.new('files')

    # create file_metadata.xml that stores list of files and their checksum
    # will be used later on to check whether installed files have been changed
    root_dir = File.join(tpkgdir, "root")
    reloc_dir = File.join(tpkgdir, "reloc")
    Find.find(root_dir, reloc_dir) do |f|
      next if !File.exist?(f)
      relocatable = "false"

      # check if it's from root dir or reloc dir
      if f =~ /^#{root_dir}/
        short_fn = f[root_dir.length ..-1]
      else
        short_fn = f[reloc_dir.length + 1..-1]
        relocatable = "true"
      end

      next if short_fn.nil? or short_fn.empty?

      file_ele = filemetadata_xml.root.add_element("file", {"relocatable" => relocatable})
      path_ele = file_ele.add_element("path")
      path_ele.add_text(short_fn)

      # only do checksum for file
      if File.file?(f)
        # this doesn't work for older ruby version
        #digest = Digest::SHA256.file(f).hexdigest
        digest = Digest::SHA256.hexdigest(File.read(f))
        chksum_ele = file_ele.add_element("checksum")
        alg_ele = chksum_ele.add_element("algorithm")
        alg_ele.add_text("SHA256")
        digest_ele = chksum_ele.add_element("digest")
        digest_ele.add_text(digest)
      end
    end
    return filemetadata_xml
  end
  
  def self.verify_package_checksum(package_file)
    topleveldir = package_toplevel_directory(package_file)
    # Extract checksum.xml from the package
    checksum_xml = nil
    IO.popen("#{find_tar} -xf #{package_file} -O #{File.join(topleveldir, 'checksum.xml')}") do |pipe|
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
      IO.popen("#{find_tar} -xf #{package_file} -O #{File.join(topleveldir, 'tpkg.tar')}") do |pipe|
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
  def self.metadata_from_package(package_file)
    topleveldir = package_toplevel_directory(package_file)
    # Verify checksum
    verify_package_checksum(package_file)
    # Extract and parse tpkg.xml
    tpkg_xml = nil
    IO.popen("#{find_tar} -xf #{package_file} -O #{File.join(topleveldir, 'tpkg.tar')} | #{find_tar} -xf - -O #{File.join('tpkg', 'tpkg.xml')}") do |pipe|
      tpkg_xml = REXML::Document.new(pipe.read)
    end
    if !$?.success?
      raise "Extracting tpkg.xml from #{package_file} failed"
    end
    # Insert an attribute on the root element with the package filename
    tpkg_xml.root.attributes['filename'] = File.basename(package_file)
    # Return
    tpkg_xml
  end

  # Extracts the data out of the metadata XML document into a hash for
  # faster access.
  def self.metadata_xml_to_hash(metadata_xml)
    metadata_hash = {}
    metadata_hash[:filename] = metadata_xml.root.attributes['filename']
    metadata_hash[:xml] = metadata_xml
    REQUIRED_FIELDS.each do |reqfield|
      metadata_hash[reqfield.to_sym] =
        metadata_xml.elements["/tpkg/#{reqfield}"].text
    end
    [:package_version, :description, :bugreporting].each do |optfield|
      if metadata_xml.elements["/tpkg/#{optfield.to_s}"]
        metadata_hash[optfield] =
          metadata_xml.elements["/tpkg/#{optfield.to_s}"].text
      end
    end
    [:operatingsystem, :architecture].each do |arrayfield|
      array = []
      # In the tpkg design docs I wrote that the user would specify
      # multiple OSs or architectures by specifying the associated XML
      # element more than once:
      # <tpkg>
      # <operatingsystem>RedHat-4</operatingsystem>
      # <operatingsystem>CentOS-4</operatingsystem>
      # </tpkg>
      # However, I wrote the initial code and built my initial packages
      # using comma separated values in a single instance of the
      # element:
      # <tpkg>
      # <operatingsystem>RedHat-4,CentOS-4</operatingsystem>
      # </tpkg>
      # So we support both.
      metadata_xml.elements.each("/tpkg/#{arrayfield.to_s}") do |af|
        array.concat(af.text.split(/\s*,\s*/))
      end
      metadata_hash[arrayfield] = array
    end
    
    deps = []
    metadata_xml.elements.each('/tpkg/dependencies/dependency') do |depxml|
      dep = {}
      dep[:name] = depxml.elements['name'].text
      [:minimum_version, :maximum_version,
       :minimum_package_version, :maximum_package_version].each do |depfield|
        if depxml.elements[depfield.to_s]
          dep[depfield] = depxml.elements[depfield.to_s].text
        end
      end
      if depxml.elements['native']
        dep[:type] = :native
      end
      deps << dep
    end
    metadata_hash[:dependencies] = deps

    conflicts = []
    metadata_xml.elements.each('/tpkg/conflicts/conflict') do |conflictxml|
      conflict = {}
      conflict[:name] = conflictxml.elements['name'].text
      [:minimum_version, :maximum_version,
       :minimum_package_version, :maximum_package_version].each do |conflictfield|
        if conflictxml.elements[conflictfield.to_s]
          conflict[conflictfield] = conflictxml.elements[conflictfield.to_s].text
        end
      end
      if conflictxml.elements['native']
        conflict[:type] = :native
      end
      conflicts << conflict
    end
    metadata_hash[:conflicts] = conflicts
    
    externals = []
    metadata_xml.elements.each('/tpkg/externals/external') do |extxml|
      external = {}
      external[:name] = extxml.elements['name'].text
      if extxml.elements['data']
        external[:data] = extxml.elements['data'].text
      elsif extxml.elements['datafile']
        # We don't have access to the package contents here, so we just save
        # the name of the file and leave it up to others to read the file
        # when the package contents are available.
        external[:datafile] = extxml.elements['datafile'].text
      elsif extxml.elements['datascript']
        # We don't have access to the package contents here, so we just save
        # the name of the script and leave it up to others to run the script
        # when the package contents are available.
        external[:datascript] = extxml.elements['datascript'].text
      end
      externals << external
    end
    metadata_hash[:externals] = externals
    
    file_defaults = {}
    if metadata_xml.elements['/tpkg/files/file_defaults/posix']
      posix = {}
      if metadata_xml.elements['/tpkg/files/file_defaults/posix/owner']
        owner =
          metadata_xml.elements['/tpkg/files/file_defaults/posix/owner'].text
#        posix[:owner] = Tpkg::lookup_uid(owner)
        posix[:owner] = owner
     
      end
      gid = nil
      if metadata_xml.elements['/tpkg/files/file_defaults/posix/group']
        group =
          metadata_xml.elements['/tpkg/files/file_defaults/posix/group'].text
#	posix[:group] = Tpkg::lookup_gid(group)
        posix[:group] = group
      end
      perms = nil
      if metadata_xml.elements['/tpkg/files/file_defaults/posix/perms']
        perms =
          metadata_xml.elements['/tpkg/files/file_defaults/posix/perms'].text
        posix[:perms] = perms.oct
      end
      file_defaults[:posix] = posix
    end
    metadata_hash[:file_defaults] = file_defaults
 
    dir_defaults = {}
    if metadata_xml.elements['/tpkg/files/dir_defaults/posix']
      posix = {}
      if metadata_xml.elements['/tpkg/files/dir_defaults/posix/owner']
        owner =
          metadata_xml.elements['/tpkg/files/dir_defaults/posix/owner'].text
#        posix[:owner] = Tpkg::lookup_uid(owner)
        posix[:owner] = owner
      end
      gid = nil
      if metadata_xml.elements['/tpkg/files/dir_defaults/posix/group']
        group =
          metadata_xml.elements['/tpkg/files/dir_defaults/posix/group'].text
        #posix[:group] = Tpkg::lookup_gid(group)
        posix[:group] = group
      end
      perms = nil
      if metadata_xml.elements['/tpkg/files/dir_defaults/posix/perms']
        perms =
          metadata_xml.elements['/tpkg/files/dir_defaults/posix/perms'].text
        posix[:perms] = perms.oct
      end
      dir_defaults[:posix] = posix
    end
    metadata_hash[:dir_defaults] = dir_defaults
    
    files = []
    metadata_xml.elements.each('/tpkg/files/file') do |filexml|
      file = {}
      file[:path] = filexml.elements['path'].text
      if filexml.elements['encrypt']
        encrypt = {}
        if filexml.elements['encrypt'].attribute('precrypt') &&
           filexml.elements['encrypt'].attribute('precrypt').value == 'true'
          encrypt[:precrypt] = true
        end
        file[:encrypt] = encrypt
      end
      if filexml.elements['init']
        init = {}
        if filexml.elements['init/start']
          init[:start] = filexml.elements['init/start'].text
        end
        if filexml.elements['init/levels']
          if filexml.elements['init/levels'].text
            # Split '234' into ['2','3','4'], for example
            init[:levels] = filexml.elements['init/levels'].text.split(//)
          else
            # If the element is empty in the XML (<levels/> or
            # <levels></levels>) then we get nil back from the .text
            # call, interpret that as no levels
            init[:levels] = []
          end
        end
        file[:init] = init
      end
      if filexml.elements['crontab']
        crontab = {}
        if filexml.elements['crontab/user']
          crontab[:user] = filexml.elements['crontab/user'].text
        end
        file[:crontab] = crontab
      end
      if filexml.elements['posix']
        posix = {}
        if filexml.elements['posix/owner']
          owner = filexml.elements['posix/owner'].text
          #posix[:owner] = Tpkg::lookup_uid(owner)
          posix[:owner] = owner
        end
        gid = nil
        if filexml.elements['posix/group']
          group = filexml.elements['posix/group'].text
          #posix[:group] = Tpkg::lookup_gid(group)
          posix[:group] = group
        end
        perms = nil
        if filexml.elements['posix/perms']
          perms = filexml.elements['posix/perms'].text
          posix[:perms] = perms.oct
        end
        file[:posix] = posix
      end
      files << file
    end
    metadata_hash[:files] = files
    
    metadata_hash
  end
  
  # Extracts and returns the metadata from a directory of package files
  def self.metadata_from_directory(directory)
    metadata = []

    # if metadata.xml already exists, then go ahead and
    # parse it
    existing_metadata_file = File.join(directory, 'metadata.xml')
    existing_metadata = {}
    if File.exists?(existing_metadata_file)
      tpkg_metadata_xml = REXML::Document.new(File.open(existing_metadata_file))

      tpkg_metadata_xml.root.elements.each do | metadata_xml |
        existing_metadata[metadata_xml.attributes['filename']] = metadata_xml
      end
    end

    # Populate the metadata array with metadata for all of the packages
    # in the given directory. Reuse existing metadata if possible.
    Dir.glob(File.join(directory, '*.tpkg')) do |pkg|
      if existing_metadata[File.basename(pkg)]
        metadata << existing_metadata[File.basename(pkg)] 
      else
        metadata << metadata_from_package(pkg).root
      end
    end
    metadata
  end
  
  # Extracts the metadata from a directory of package files and saves it
  # to metadata.xml in that directory
  def self.extract_metadata(directory)
    metadata = metadata_from_directory(directory)
    # Combine all of the individual metadata files into one XML document
    metadata_xml = REXML::Document.new
    metadata_xml << REXML::Element.new('tpkg_metadata')
    metadata.each do |md|
      metadata_xml.root << md
    end
    # And write that out to metadata.xml
    metadata_tmpfile = Tempfile.new('metadata.xml', directory)
    metadata_xml.write(metadata_tmpfile)
    metadata_tmpfile.close
    File.chmod(0644, metadata_tmpfile.path)
    File.rename(metadata_tmpfile.path, File.join(directory, 'metadata.xml'))
  end
  
  # Haven't found a Ruby method for creating temporary directories,
  # so create a temporary file and replace it with a directory.
  def self.tempdir(basename, tmpdir=Dir::tmpdir)
    tmpfile = Tempfile.new(basename, tmpdir)
    tmpdir = tmpfile.path
    tmpfile.close!
    Dir.mkdir(tmpdir)
    tmpdir
  end
  
  # Returns a string representing the OS of this box of the form:
  # "OSname-OSmajorversion".  The OS name is currently whatever facter
  # returns for the 'operatingsystem' fact.  The major version is a bit
  # messier, as we try on a per-OS basis to come up with something that
  # represents the major version number of the OS, where binaries are
  # expected to be compatible across all versions of the OS with that
  # same major version number.  Examples include RedHat-5, CentOS-5,
  # FreeBSD-7, Darwin-10.5, and Solaris-5.10
  @@os = nil
  def self.get_os
    if !@@os
      # Tell facter to load everything, otherwise it tries to dynamically
      # load the individual fact libraries using a very broken mechanism
      Facter.loadfacts
      
      operatingsystem = Facter['operatingsystem'].value
      osver = nil
      if Facter['lsbmajdistrelease'] &&
         Facter['lsbmajdistrelease'].value &&
         !Facter['lsbmajdistrelease'].value.empty?
        osver = Facter['lsbmajdistrelease'].value
      elsif Facter['kernel'] &&
            Facter['kernel'].value == 'Darwin' &&
            Facter['macosx_productversion'] &&
            Facter['macosx_productversion'].value &&
            !Facter['macosx_productversion'].value.empty?
        macver = Facter['macosx_productversion'].value
        # Extract 10.5 from 10.5.6, for example
        osver = macver.split('.')[0,2].join('.')
      elsif Facter['operatingsystem'] &&
            Facter['operatingsystem'].value == 'FreeBSD'
        # Extract 7 from 7.1-RELEASE, for example
        fbver = Facter['operatingsystemrelease'].value
        osver = fbver.split('.').first
      elsif Facter['operatingsystemrelease'] &&
            Facter['operatingsystemrelease'].value &&
            !Facter['operatingsystemrelease'].value.empty?
        osver = Facter['operatingsystemrelease'].value
      else
        raise "Unable to determine proper OS value on this platform"
      end
      @@os = "#{operatingsystem}-#{osver}"
    end
    @@os.dup
  end
  
  # pkg is a standard Hash format used in the library to represent an
  # available package
  # req is a standard Hash format used in the library to represent package
  # requirements
  def self.package_meets_requirement?(pkg, req)
    result = true
    puts "pkg_meets_req checking #{pkg.inspect} against #{req.inspect}" if @@debug
    metadata = pkg[:metadata]
    if req[:type] == :native && pkg[:source] != :native_installed && pkg[:source] != :native_available
      # A req for a native package must be satisfied by a native package
      puts "Package fails native requirement" if @@debug
      result = false
    elsif (!req[:type] || req[:type] == :tpkg) &&
          (pkg[:source] == :native_installed || pkg[:source] == :native_available)
      # Likewise a req for a tpkg must be satisfied by a tpkg
      puts "Package fails non-native requirement" if @@debug
      result = false
    elsif metadata[:name] == req[:name]
      same_min_ver_req = false
      same_max_ver_req = false
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
      if same_min_ver_req && req[:minimum_package_version]
        pkgver = Version.new(metadata[:package_version])
        reqver = Version.new(req[:minimum_package_version])
        if pkgver < reqver
          puts "Package fails minimum_package_version (#{pkgver} < #{reqver})" if @@debug
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
      # The empty? check ensures that a package with no operatingsystem
      # field matches all clients.
      if metadata[:operatingsystem] &&
         !metadata[:operatingsystem].empty? &&
         !metadata[:operatingsystem].include?(get_os)
        puts "Package fails operatingsystem" if @@debug
        result = false
      end
      # Same deal with empty? here
      if metadata[:architecture] &&
         !metadata[:architecture].empty? &&
         !metadata[:architecture].include?(Facter['hardwaremodel'].value)
        puts "Package fails architecture" if @@debug
        result = false
      end
    else
      puts "Package fails name" if @@debug
      result = false
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
  
  def self.files_in_package(package_file)
    files = {}
    files[:root] = []
    files[:reloc] = []
    topleveldir = package_toplevel_directory(package_file)
    IO.popen("#{find_tar} -xf #{package_file} -O #{File.join(topleveldir, 'tpkg.tar')} | #{find_tar} -tf -") do |pipe|
      pipe.each do |file|
        file.chomp!
        if file =~ Regexp.new(File.join('tpkg', 'root'))
          files[:root] << file.sub(Regexp.new(File.join('tpkg', 'root')), '')
        elsif file =~ Regexp.new(File.join('tpkg', 'reloc', '.'))
          files[:reloc] << file.sub(Regexp.new(File.join('tpkg', 'reloc', '')), '')
        end
      end
    end
    if !$?.success?
      raise "Extracting file list from #{package_file} failed"
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
  
  def self.gethttp(uri)
    if uri.scheme != 'http' && uri.scheme != 'https'
      # It would be possible to add support for FTP and possibly
      # other things if anyone cares
      raise "Only http/https URIs are supported, got: '#{uri}'"
    end
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
      # Eliminate the OpenSSL "using default DH parameters" warning
      if File.exist?('/etc/tpkg/dhparams')
        dh = OpenSSL::PKey::DH.new(IO.read('/etc/tpkg/dhparams'))
        Net::HTTP.ssl_context_accessor(:tmp_dh_callback)
        http.tmp_dh_callback = proc { dh }
      end
      http.use_ssl = true
      if File.exist?('/etc/tpkg/ca.pem')
        http.ca_file = '/etc/tpkg/ca.pem'
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      elsif File.directory?('/etc/tpkg/ca')
        http.ca_path = '/etc/tpkg/ca'
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end
    end
    http.start
    http
  end
  
  # foo
  # foo=1.0
  # foo=1.0=1
  # foo-1.0-1.tpkg	
  def self.parse_request(request, installed_dir = nil)
    # FIXME: Add support for <, <=, >, >=
    req = {}
    parts = request.split('=')

    # upgrade/remove/query options should take package filenames
    # First, look inside installed dir to see if we can find the request package. This is to support
    # request that uses package filename rather than package name
    if installed_dir && File.exists?(File.join(installed_dir, request))
      metadata_xml = Tpkg::metadata_from_package(File.join(installed_dir, request))
      req[:name] = metadata_xml.elements['/tpkg/name'].text
      req[:minimum_version] = metadata_xml.elements['/tpkg/version'].text
      req[:maximum_version] = metadata_xml.elements['/tpkg/version'].text
      if metadata_xml.elements['/tpkg/package_version']
        req[:minimum_package_version] = metadata_xml.elements['/tpkg/package_version'].text 
        req[:maximum_package_version] = metadata_xml.elements['/tpkg/package_version'].text
      end
    elsif parts.length > 2 && parts[-2] =~ /^[\d\.]/ && parts[-1] =~ /^[\d\.]/
      package_version = parts.pop
      version = parts.pop
      req[:name] = parts.join('-')
      req[:minimum_version] = version
      req[:maximum_version] = version
      req[:minimum_package_version] = package_version
      req[:maximum_package_version] = package_version
    elsif parts.length > 1 && parts[-1] =~ /^[\d\.]/
      version = parts.pop
      req[:name] = parts.join('-')
      req[:minimum_version] = version
      req[:maximum_version] = version
    else
      req[:name] = parts.join('-')
    end
    req
  end

  # deploy_options is used for configuration the deployer. It is a map of option_names => option_values. Possible
  # options are: use-ssh-key, deploy-as, worker-count, abort-on-fail
  # 
  # deploy_params is an array that holds the list of paramters that is used when invoking tpkg on to the remote
  # servers where we want to deploy to. 
  # 
  # servers is an array or a callback that list the remote servers where we want to deploy to
  def self.deploy(deploy_params, deploy_options, servers)
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
  
  #
  # Instance methods
  #
  
  DEFAULT_BASE = '/home/t'
  
  def initialize(options)
    # Options
    @base = options[:base]
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
    
    @file_system_root = '/'  # Not sure if this needs to be more portable
    # This option is only intended for use by the test suite
    if options[:file_system_root]
      @file_system_root = options[:file_system_root]
      @base = File.join(@file_system_root, @base)
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
        if Tpkg::get_os =~ /Darwin/
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
    if !File.exist?(@installed_directory)
      begin
        FileUtils.mkdir_p(@installed_directory)
      rescue Errno::EACCES
        raise if Process.euid == 0
      end
    end
    @metadata_directory = File.join(@installed_directory, 'metadata')
    if !File.exist?(@metadata_directory)
      begin
        FileUtils.mkdir_p(@metadata_directory)
      rescue Errno::EACCES
        raise if Process.euid == 0
      end
    end
    @sources_directory = File.join(@var_directory, 'sources')
    if !File.exist?(@sources_directory)
      begin
        FileUtils.mkdir_p(@sources_directory)
      rescue Errno::EACCES
        raise if Process.euid == 0
      end
    end
    @external_directory = File.join(@var_directory, 'externals')
    if !File.exist?(@external_directory)
      begin
        FileUtils.mkdir_p(@external_directory)
      rescue Errno::EACCES
        raise if Process.euid == 0
      end
    end
    @tmp_directory = File.join(@var_directory, 'tmp')
    if !File.exist?(@tmp_directory)
      begin
        FileUtils.mkdir_p(@tmp_directory)
      rescue Errno::EACCES
        raise if Process.euid == 0
      end
    end
    @tar = Tpkg::find_tar
    @lock_directory = File.join(@var_directory, 'lock')
    @lock_pid_file = File.join(@lock_directory, 'pid')
    @locks = 0
    @installed_metadata = {}
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
          metadata_xml = Tpkg::metadata_from_package(source)
          name = metadata_xml.elements['/tpkg/name'].text
          metadata[name] = [] if !metadata[name]
          # Less than ideal that we'll have to re-parse this XML again
          # later if this package needs to be considered, but an
          # individual package source isn't likely to be too common.  Need
          # to think later if there's a way to structure things so that
          # this isn't necessary.
          metadata[name] << { :metadata => metadata_xml.to_s,
                              :source => source }
        elsif File.directory?(source)
          if !File.exists?(File.join(source, 'metadata.xml'))
            warn "Warning: the source directory #{source} has no metadata.xml file. Try running tpkg -x #{source} first."
            next
          end
          tpkg_metadata = REXML::Document.new(File.open(File.join(source, 'metadata.xml')))
          tpkg_metadata.elements.each('/tpkg_metadata/tpkg') do |metadata_xml|
            name = metadata_xml.elements['name'].text
            metadata[name] = [] if !metadata[name]
            metadata[name] << { :metadata => metadata_xml.to_s,
                                :source => source }
          end
        else
          uri = URI.join(source, 'metadata.xml')
          http = Tpkg::gethttp(uri)
          
          # Calculate the path to the local copy of the metadata for this URI
          localdir = source_to_local_directory(source)
          localpath = File.join(localdir, 'metadata.xml')
          localdate = nil
          if File.exist?(localpath)
            localdate = File.mtime(localpath)
          end
          
          # Check if the local copy is out of data
          remotedate = nil
          if localdate
            response = http.head(uri.path)
            case response
            when Net::HTTPSuccess
              remotedate = Time.httpdate(response['Date'])
            else
              puts "Error fetching metadata from #{uri}: #{response.body}"
              response.error!  # Throws an exception
            end
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
                if !File.exist?(localdir)
                  FileUtils.mkdir_p(localdir)
                end
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
          
          # At this stage we just break up the metadata.xml document into
          # per-package chunks and save them for further parsing later.
          # This allows us to parse the whole metadata.xml just once, and
          # saves us from having to further parse and convert the
          # per-package chunks until if/when they are needed.
          tpkg_metadata = REXML::Document.new(metadata_contents)
          tpkg_metadata.elements.each('/tpkg_metadata/tpkg') do |metadata_xml|
            name = metadata_xml.elements['name'].text
            metadata[name] = [] if !metadata[name]
            metadata[name] << { :metadata => metadata_xml.to_s,
                                :source => source }
          end
        end
      end
      @metadata = metadata
      if @@debug
        @sources.each do |source|
          count = metadata.inject(0) do |memo,m|
                    # metadata is a hash of pkgname => array of metadata
                    # hashes
                    # Thus m is a 2 element array of [pkgname, array of
                    # metadata hashes]  And thus m[1] is the array of
                    # metadata hashes.  And metadata hashes are themselves
                    # a hash of XML metadata and source.
                    memo + m[1].select{|mh| mh[:source] == source}.length
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
          @metadata[name].each do |metadata_hash|
            metadata_xml = REXML::Document.new(metadata_hash[:metadata])
            metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
            packages << { :metadata => metadata,
                          :source => metadata_hash[:source] }
          end
        end
        @available_packages[name] = packages
        if @@debug
          puts "Loaded #{@available_packages[name].size} available packages for #{name}"
        end
      end
    else
      # Load all packages
      @metadata.each do |pkgname, metadata_hashes|
        if !@available_packages[pkgname]
          packages = []
          metadata_hashes.each do |metadata_hash|
            metadata_xml = REXML::Document.new(metadata_hash[:metadata])
            metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
            packages << { :metadata => metadata,
                          :source => metadata_hash[:source] }
          end
          @available_packages[pkgname] = packages
        end
      end
    end
  end

  # Used by load_available_native_packages to stuff all the info about a
  # native package into a hash to match the structure we pass around
  # internally for tpkgs
  def pkg_for_native_package(name, version, package_version, source)
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
  
  def load_available_native_packages(pkgname)
    if !@available_native_packages[pkgname]
      native_packages = []
      if Tpkg::get_os =~ /RedHat|CentOS|Fedora/
        [ {:arg => 'installed', :header => 'Installed', :source => :native_installed},
          {:arg => 'available', :header => 'Available', :source => :native_available} ].each do |yum|
          puts "available_native_packages running 'yum list #{yum[:arg]} #{pkgname}'" if @@debug
          stderr_first_line = nil
          Open3.popen3("yum list #{yum[:arg]} #{pkgname}") do |stdin, stdout, stderr|
            stdin.close
            read_packages = false
            stdout.each_line do |line|
              if line =~ /#{yum[:header]} Packages/
                # Skip the header lines until we get to this line
                read_packages = true
              elsif read_packages
                name_and_arch, ver_and_release, repo = line.split
                # In the end we ignore the architecture.  Anything that
                # shows up in yum should be installable on this box, and
                # the chance of a mismatch between facter's idea of the
                # architecture and RPM's idea is high.  I.e. i386 vs i686
                # or i32e vs x86_64 or whatever.
                name, arch = name_and_arch.split('.')
                # This is prone to error, as both the version and release
                # (what we call package version) could contain '-', so
                # there's no reliable way to parse the combined value.
                # RPM can show them separately, but seemingly not yum.
                # We could use rpm to list installed packages, but we
                # have to use yum to get available packages so we're
                # stuck with the problem.
                verparts = ver_and_release.split('-')
                package_version = verparts.pop
                version = verparts.join('-')
                # Create the pkg structure
                pkg = pkg_for_native_package(name, version, package_version, yum[:source])
                native_packages << pkg
              end
            end
            stderr_first_line = stderr.gets
          end
          if !$?.success?
            # Ignore 'no matching packages', raise anything else
            if stderr_first_line != "Error: No matching Packages to list\n"
              raise "available_native_packages error running yum"
            end
          end
        end
      elsif Tpkg::get_os =~ /Debian|Ubuntu/
        # The default 'dpkg -l' format has an optional third column for
        # errors, which makes it hard to parse reliably.
        puts "available_native_packages running dpkg-query -W -f='${Package} ${Version} ${Status}\n' #{pkgname}" if @@debug
        stderr_first_line = nil
        Open3.popen3("dpkg-query -W -f='${Package} ${Version} ${Status}\n' #{pkgname}") do |stdin, stdout, stderr|
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
            if status =~ /installed/
              pkg = pkg_for_native_package(name, version, package_version, :native_installed)
              native_packages << pkg
            end
          end
          stderr_first_line = stderr.gets
        end
        if !$?.success?
          # Ignore 'no matching packages', raise anything else
          if stderr_first_line !~ 'No packages found matching'
            raise "available_native_packages error running dpkg-query"
          end
        end
        puts "available_native_packages running 'apt-cache show #{pkgname}'" if @@debug
        IO.popen("apt-cache show #{pkgname}") do |pipe|
          name = nil
          version = nil
          package_version = nil
          pipe.each_line do |line|
            if line =~ /^Package: (.*)/
              name = $1
              version = nil
              package_version = nil
            elsif line =~ /^Version: (.*)/
              debversion = $1
              # Seems to be Debian convention that if the package has a
              # package version you seperate that from the upstream version
              # with a hyphen.
              if debversion =~ /-/
                version, package_version = debversion.split('-', 2)
              else
                version = debversion
              end
              pkg = pkg_for_native_package(name, version, package_version, :native_available)
              native_packages << pkg
            end
          end
        end
        if !$?.success?
          raise "available_native_packages error running apt-cache"
        end
      elsif Tpkg::get_os =~ /Solaris/
        # Example of pkginfo -x output:
        # SUNWzfsu                      ZFS (Usr)
        #                               (i386) 11.10.0,REV=2006.05.18.01.46
        puts "available_native_packages running 'pkginfo -x #{pkgname}'" if @@debug
        IO.popen("pkginfo -x #{pkgname}") do |pipe|
          name = nil
          version = nil
          package_version = nil
          pipe.each_line do |line|
            if line =~ /^\w/
              name = line.split(' ')
              version = nil
              package_version = nil
            else
              arch, solversion = line.split(' ')
              # Lots of Sun and some third party packages (including CSW)
              # seem to use this REV= convention in the version.  I've
              # never seen it documented, but since it seems to be a
              # widely used convention we'll go with it.
              if solversion =~ /,REV=/
                version, package_version = solversion.split(',REV=')
              else
                version = solversion
              end
              pkg = pkg_for_native_package(name, version, package_version, :native_installed)
              native_packages << pkg
            end
          end
        end
        if !$?.success?
          raise "available_native_packages error running pkginfo"
        end
        if File.exist?('/opt/csw/bin/pkg-get')
          puts "available_native_packages running '/opt/csw/bin/pkg-get -a'" if @@debug
          IO.popen('/opt/csw/bin/pkg-get -a') do |pipe|
            pipe.each_line do |line|
              next if line =~ /^#/  # Skip comments
              name, solversion = line.split
              # pkg-get doesn't have an option to only show available
              # packages matching a specific name, so we have to look over
              # all available packages and pick out the ones that match.
              next if name != pkgname
              # Lots of Sun and some third party packages (including CSW)
              # seem to use this REV= convention in the version.  I've
              # never seen it documented, but since it seems to be a
              # widely used convention we'll go with it.
              version = nil
              package_version = nil
              if solversion =~ /,REV=/
                version, package_version = solversion.split(',REV=')
              else
                version = solversion
              end
              pkg = pkg_for_native_package(name, version, package_version, :native_available)
              native_packages << pkg
            end
          end
        end
      elsif Tpkg::get_os =~ /FreeBSD/
        puts "available_native_packages running 'pkg_info #{pkgname}'" if @@debug
        IO.popen("pkg_info #{pkgname}") do |pipe|
          pipe.each_line do |line|
            name_and_version = line.split(' ', 3)
            nameparts = name_and_version.split('-')
            fbversion = nameparts.pop
            name = nameparts.join('-')
            # Seems to be FreeBSD convention that if the package has a
            # package version you seperate that from the upstream version
            # with an underscore.
            version = nil
            package_version = nil
            if fbversion =~ /_/
              version, package_version = fbversion.split('_', 2)
            else
              version = fbversion
            end
            pkg = pkg_for_native_package(name, version, package_version, :native_installed)
            package_version << pkg
          end
        end
        if !$?.success?
          raise "available_native_packages error running pkg_info"
        end
        # FIXME: FreeBSD available packages
        # We could either poke around in the ports tree (if installed), or
        # try to recreate the URL "pkg_add -r" would use and pull a
        # directory listing.
      else
        puts "Unknown value for OS: #{Tpkg::get_os}"
      end
      @available_native_packages[pkgname] = native_packages
      if @@debug
        nicount = native_packages.select{|pkg| pkg[:source] == :native_installed}.length
        nacount = native_packages.select{|pkg| pkg[:source] == :native_available}.length
        puts "Found #{nicount} installed native packages for #{pkgname}"
        puts "Found #{nacount} available native packages for #{pkgname}"
      end
    end
  end
  
  # Returns an array of the tpkg.xml metadata for installed packages
  def metadata_for_installed_packages
    metadata = {}
    if File.directory?(@installed_directory)
      Dir.foreach(@installed_directory) do |entry|
        next if entry == '.' || entry == '..' || entry == 'metadata'
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
          metadata_file = File.join(package_metadata_dir, "tpkg.xml")
          m = nil
          if File.exists?(metadata_file)
            m = REXML::Document.new(File.open(metadata_file))
          # No cached metadata found, we have to extract it ourselves
          # and save it for next time
          else
            m = Tpkg::metadata_from_package(
                  File.join(@installed_directory, entry))
            begin
              FileUtils.mkdir_p(package_metadata_dir)
              File.open(metadata_file, "w") do |file|
                file.write(m)
              end
            rescue Errno::EACCES
              raise if Process.euid == 0
            end
          end
          metadata[entry] = { :timestamp => timestamp,
                              :metadata => Tpkg::metadata_xml_to_hash(m) }
        end
      end
    end
    @installed_metadata = metadata
    # FIXME: dup the array we return?
    @installed_metadata.collect { |im| im[1][:metadata] }
  end
  
  # Convert metadata_for_installed_packages into pkg hashes
  def installed_packages
    instpkgs = []
    metadata_for_installed_packages.each do |metadata|
      instpkgs << { :metadata => metadata,
                    :source => :currently_installed,
                    # It seems reasonable for this to default to true
                    :prefer => true }
    end
    instpkgs
  end
  
  # Returns a hash of file_metadata for installed packages
  def file_metadata_for_installed_packages
    file_metadata = {}

    if File.directory?(@metadata_directory)
      Dir.foreach(@metadata_directory) do |entry|
        next if entry == '.' || entry == '..' 
        file = File.join(@metadata_directory, entry, "file_metadata.xml")
        if File.exists? file
          file_metadata_xml = REXML::Document.new(File.open(file)) 
          file_metadata[file_metadata_xml.root.attributes["package_file"]] = file_metadata_xml
        end
      end
    end
    return file_metadata
  end

  # Returns an array of packages which meet the given requirement
  def available_packages_that_meet_requirement(req=nil)
    pkgs = []
    puts "avail_pkgs_that_meet_req checking for #{req.inspect}" if @@debug
    if req
      if req[:type] == :native
        load_available_native_packages(req[:name])
        @available_native_packages[req[:name]].each do |pkg|
          if Tpkg::package_meets_requirement?(pkg, req)
            pkgs << pkg
          end
        end
      else
        load_available_packages(req[:name])
        @available_packages[req[:name]].each do |pkg|
          if Tpkg::package_meets_requirement?(pkg, req)
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
    pkgs
  end
  def installed_packages_that_meet_requirement(req=nil)
    pkgs = []
    if req && req[:type] == :native
      load_available_native_packages(req[:name])
      @available_native_packages[req[:name]].each do |pkg|
        if pkg[:source] == :native_installed &&
           Tpkg::package_meets_requirement?(pkg, req)
          pkgs << pkg
        end
      end
    else
      installed_packages.each do |pkg|
        if req
          if Tpkg::package_meets_requirement?(pkg, req)
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
        fip = Tpkg::files_in_package(File.join(@installed_directory, package_file))
        normalize_paths(fip)
        fip[:metadata] = metadata
        files[package_file] = fip
      end
    end
    files
  end
  
  # Returns the best solution that meets the given requirements.  Some
  # or all packages may be optionally pre-selected and specified via the
  # packages parameter, otherwise packages are picked from the set of
  # available packages.  The packages parameter is in the form of a hash
  # with package names as keys pointing to arrays of package specs (our
  # standard hash of package metadata and source).  The return value
  # will be an array of package specs.
  MAX_POSSIBLE_SOLUTIONS_TO_CHECK = 10000
  def best_solution(requirements, packages, core_packages)
    # Dup objects passed to us so that resolve_dependencies is free to
    # change them without potentially messing up our caller
    result = resolve_dependencies(requirements.dup, packages.dup, core_packages.dup)
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
  def resolve_dependencies(requirements, packages, core_packages, number_of_possible_solutions_checked=0)
    # Make sure we have populated package lists for all requirements.
    # Filter the package lists against the requirements and
    # ensure we can at least satisfy the initial requirements.
    requirements.each do |req|
      if !packages[req[:name]]
        puts "resolvedeps initializing packages for #{req.inspect}" if @@debug
        packages[req[:name]] =
          available_packages_that_meet_requirement(req)
      else
        # Loop over packages and eliminate ones that don't work for
        # this requirement
        puts "resolvedeps filtering packages for #{req.inspect}" if @@debug
        packages[req[:name]] =
          packages[req[:name]].select do |pkg|
            # When this method is called recursively there might be a
            # nil entry inserted into packages by the sorting code
            # below.  We need to skip those.
            if pkg != nil
              Tpkg::package_meets_requirement?(pkg, req)
            end
          end
      end
      if packages[req[:name]].empty?
        if @@debug
          puts "No packages matching #{req.inspect}"
        end
        return {:number_of_possible_solutions_checked => number_of_possible_solutions_checked}
      end
    end
    # Sort the packages
    packages.each do |pkgname, pkgs|
      pkgs.sort!(&SORT_PACKAGES)
      # Only currently installed packages are allowed to score 0.
      # Anything else can score 1 at best.  This ensures
      # that we prefer the solution which leaves the most
      # currently installed packages alone.
      if pkgs[0][:source] != :currently_installed &&
         pkgs[0][:source] != :native_installed
        pkgs.unshift(nil)
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
    corepkgs = packages.reject{|pkgname, pkgs| !core_packages.include?(pkgname)}
    noncorepkgs = packages.reject{|pkgname, pkgs| core_packages.include?(pkgname)}
    
    # Calculate total package depth, the sum of the lengths (or rather
    # the max array index) of each array of packages.
    coretotaldepth = corepkgs.inject(0) {|memo, pkgs| memo + pkgs[1].length - 1}
    noncoretotaldepth = noncorepkgs.inject(0) {|memo, pkgs| memo + pkgs[1].length - 1}
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
                  if noncorepkgs.empty?
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
                      noncorepkgs.each do |ncpkgname, ncpkgs|
                        puts "resolvedeps noncorepkg #{ncpkgname}: #{ncpkgs.inspect}" if @@debug
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
                              if sol[:pkgs].length == packages.length
                                puts "resolvedeps complete pkg set: #{sol.inspect}" if @@debug
                                # Solutions with remaining depth are duplicates of
                                # solutions we already checked at lower depth levels
                                if sol[:remaining_noncoredepth] == 0
                                  result = check_solution(sol, requirements, packages, core_packages, number_of_possible_solutions_checked)
                                  if result[:solution]
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
        core_solutions = new_core_solutions
      end
    end
    # No solutions found
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
      puts "checksol checking #{solution.inspect}"
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
        if packages[newreq[:name]]
          pkg = solution[:pkgs].find{|solpkg| solpkg[:metadata][:name] == newreq[:name]}
          puts "checksol newreq pkg: #{pkg.inspect}" if @@debug
          if Tpkg::package_meets_requirement?(pkg, newreq)
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
        result = resolve_dependencies(requirements+newreqs_that_need_packages, packages.dup, core_packages, number_of_possible_solutions_checked)
        if result[:solution]
          return result
        else
          number_of_possible_solutions_checked = result[:number_of_possible_solutions_checked]
        end
      end
    end
    return {:number_of_possible_solutions_checked => number_of_possible_solutions_checked}
  end
 
  def download(source, path, downloaddir = nil)
    http = Tpkg::gethttp(URI.parse(source))
    localdir = source_to_local_directory(source)
    localpath = File.join(localdir, File.basename(path))

    # Don't download again if file is already there from previous installation
    # and still has valid checksum
    if File.file?(localpath)
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
      if !File.exist?(localdir) 
        FileUtils.mkdir_p(localdir)
      end
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
      raise "Unable to download and/or verify the package."
    end

    localpath
  end
  
  # Given a package's metadata return a hash of init scripts in the
  # package and the entry for that file from the metadata
  def init_scripts(metadata)
    init_scripts = {}
    metadata[:files].each do |tpkgfile|
      if tpkgfile[:init]
        tpkg_path = tpkgfile[:path]
        installed_path = nil
        if tpkg_path[0,1] == File::SEPARATOR
          installed_path = File.join(@file_system_root, tpkg_path)
        else
          installed_path = File.join(@base, tpkg_path)
        end
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
      # SysV-style init
      if Tpkg::get_os =~ /RedHat|CentOS|Fedora/ ||
         Tpkg::get_os =~ /Debian|Ubuntu/ ||
         Tpkg::get_os =~ /Solaris/
        start = '99'
        if tpkgfile[:init][:start]
          start = tpkgfile[:init][:start]
        end
        levels = nil
        if Tpkg::get_os =~ /RedHat|CentOS|Fedora/ ||
           Tpkg::get_os =~ /Debian|Ubuntu/
          levels = ['2', '3', '4', '5']
        elsif Tpkg::get_os =~ /Solaris/
          levels = ['2', '3']
        end
        if tpkgfile[:init][:levels]
          levels = tpkgfile[:init][:levels]
        end
        init_directory = nil
        if Tpkg::get_os =~ /RedHat|CentOS|Fedora/
          init_directory = File.join(@file_system_root, 'etc', 'rc.d')
        elsif Tpkg::get_os =~ /Debian|Ubuntu/ ||
              Tpkg::get_os =~ /Solaris/
          init_directory = File.join(@file_system_root, 'etc')
        end
        levels.each do |level|
          links[File.join(init_directory, "rc#{level}.d", 'S' + start + File.basename(installed_path))] = installed_path
        end
      elsif Tpkg::get_os =~ /FreeBSD/
        init_directory = File.join(@file_system_root, 'usr', 'local', 'etc', 'rc.d') 
        if tpkgfile[:init][:levels] && tpkgfile[:init][:levels].empty?
          # User doesn't want the init script linked in to auto-start
        else
          links[File.join(init_directory, File.basename(installed_path))] = installed_path
        end
      else
        raise "No init script support for #{Tpkg::get_os}"
      end
    end
    links
  end
  
  # Given a package's metadata return a hash of crontabs in the
  # package and where they need to be installed on the system
  def crontab_destinations(metadata)
    destinations = {}
    metadata[:files].each do |tpkgfile|
      if tpkgfile[:crontab]
        tpkg_path = tpkgfile[:path]
        installed_path = nil
        if tpkg_path[0,1] == File::SEPARATOR
          installed_path = File.join(@file_system_root, tpkg_path)
        else
          installed_path = File.join(@base, tpkg_path)
        end
        destinations[installed_path] = {}
        
        # Decide whether we're going to add the file to a per-user
        # crontab or link it into a directory of misc. crontabs.  If the
        # system only supports per-user crontabs we have to go the
        # per-user route.  If the system supports both we decide based on
        # whether the package specifies a user for the crontab.
        # Systems that only support per-user style
        if Tpkg::get_os =~ /FreeBSD/ ||
           Tpkg::get_os =~ /Solaris/ ||
           Tpkg::get_os =~ /Darwin/
          if tpkgfile[:crontab][:user]
            user = tpkgfile[:crontab][:user]
            if Tpkg::get_os =~ /FreeBSD/
              destinations[installed_path][:file] = File.join(@file_system_root, 'var', 'cron', 'tabs', user)
            elsif Tpkg::get_os =~ /Solaris/
              destinations[installed_path][:file] = File.join(@file_system_root, 'var', 'spool', 'cron', 'crontabs', user)
            elsif Tpkg::get_os =~ /Darwin/
              destinations[installed_path][:file] = File.join(@file_system_root, 'usr', 'lib', 'cron', 'tabs', user)
            end
          else
            raise "No user specified for crontab in #{metadata[:filename]}"
          end
        # Systems that support cron.d style
        elsif Tpkg::get_os =~ /RedHat|CentOS|Fedora/ ||
              Tpkg::get_os =~ /Debian|Ubuntu/
          # If a user is specified go the per-user route
          if tpkgfile[:crontab][:user]
            user = tpkgfile[:crontab][:user]
            if Tpkg::get_os =~ /RedHat|CentOS|Fedora/
              destinations[installed_path][:file] = File.join(@file_system_root, 'var', 'spool', 'cron', user)
            elsif Tpkg::get_os =~ /Debian|Ubuntu/
              destinations[installed_path][:file] = File.join(@file_system_root, 'var', 'spool', 'cron', 'crontabs', user)
            end
          # Otherwise go the cron.d route
          else
            destinations[installed_path][:link] = File.join(@file_system_root, 'etc', 'cron.d', File.basename(installed_path))
          end
        else
          raise "No crontab support for #{Tpkg::get_os}"
        end
      end
    end
    destinations
  end
  
  def run_external(pkgfile, operation, name, data)
    externalpath = File.join(@external_directory, name)
    if !File.executable?(externalpath)
      raise "External #{externalpath} does not exist or is not executable"
    end
    case operation
    when :install
      IO.popen("#{externalpath} '#{pkgfile}' install", 'w') do |pipe|
        pipe.write(data)
      end
    when :remove
      IO.popen("#{externalpath} '#{pkgfile}' remove", 'w') do |pipe|
        pipe.write(data)
      end
    else
      raise "Bug, unknown external operation #{operation}"
    end
  end
  
  # Unpack the files from a package into place, decrypt as necessary, set
  # permissions and ownership, etc.  Does not check for conflicting
  # files or packages, etc.  Those checks (if desired) must be done before
  # calling this method.
  def unpack(package_file, passphrase=nil, options={})
    metadata_xml = Tpkg::metadata_from_package(package_file)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
    
    # Unpack files in a temporary directory
    # I'd prefer to unpack on the fly so that the user doesn't need to
    # have disk space to hold three copies of the package (the package
    # file itself, this temporary unpack, and the final copy of the
    # files).  However, I haven't figured out a way to get that to work,
    # since we need to strip several layers of directories out of the
    # directory structure in the package.
    topleveldir = Tpkg::package_toplevel_directory(package_file)
    workdir = Tpkg::tempdir(topleveldir, @tmp_directory)
    system("#{@tar} -xf #{package_file} -O #{File.join(topleveldir, 'tpkg.tar')} | #{@tar} -C #{workdir} -xpf -")
    files_info = {} # store perms, uid, gid, etc. for files
    checksums_of_decrypted_files = {}
    root_dir = File.join(workdir, 'tpkg', 'root')
    reloc_dir = File.join(workdir, 'tpkg', 'reloc')
    rel_root_dir = File.join('tpkg', 'root')
    rel_reloc_dir = File.join('tpkg', 'reloc')
 
    # Get list of conflicting files/directories & store their perm/ownership. That way, we can
    # set them to the correct values later on in order to preserve them.
    # TODO: verify this command works on all platforms
    files = `#{@tar} -xf #{package_file} -O #{File.join(topleveldir, 'tpkg.tar')} | #{@tar} -tf -`
    files = files.split("\n")
    conflicting_files = {}
    files.each do | file |
      if file =~ /^#{rel_root_dir}/
        possible_conflicting_file = "{@file_system_root}/#{file[rel_root_dir.length ..-1]}"
      elsif file =~ /^#{rel_reloc_dir}/
        possible_conflicting_file = "#{@base}/#{file[rel_reloc_dir.length + 1..-1]}"
      end
      if possible_conflicting_file && (File.exists?(possible_conflicting_file) && !File.symlink?(possible_conflicting_file))
         conflicting_files[File.join(workdir, file)] = File.stat(possible_conflicting_file)
      end
    end
    
    # Run preinstall script
    if File.exist?(File.join(workdir, 'tpkg', 'preinstall'))
      # Warn the user about non-executable files, as system will just
      # silently fail and exit if that's the case.
      if !File.executable?(File.join(workdir, 'tpkg', 'preinstall'))
        warn "Warning: preinstall script for #{File.basename(package_file)} is not executable, execution will likely fail"
      end
      if @force
        system(File.join(workdir, 'tpkg', 'preinstall')) || warn("Warning: preinstall for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
      else
        system(File.join(workdir, 'tpkg', 'preinstall')) || raise("Error: preinstall for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
      end
    end
    
    # Run any externals
    metadata[:externals].each do |external|
      # If the external references a datafile or datascript then read/run it
      # now that we've unpacked the package contents and have the file/script
      # available.  This will get us the data for the external.
      if external[:datafile] || external[:datascript]
        pwd = Dir.pwd
        # chdir into the working directory so that the user can specify a
        # relative path to their file/script.
        Dir.chdir(File.join(workdir, 'tpkg'))
        if external[:datafile]
          # Read the file
          external[:data] = IO.read(external[:datafile])
          # Drop the datafile key so that we don't waste time re-reading the
          # datafile again in the future.
          external.delete(:datafile)
        elsif external[:datascript]
          # Run the script
          IO.popen(external[:datascript]) do |pipe|
            external[:data] = pipe.read
          end
          # Drop the datascript key so that we don't waste time re-running the
          # datascript again in the future.
          external.delete(:datascript)
        end
        # Switch back to our previous directory
        Dir.chdir(pwd)
      end
      if !options[:externals_to_skip] || !options[:externals_to_skip].include?(external)
        run_external(metadata[:filename], :install, external[:name], external[:data])
      end
    end
    
    # Since we're stuck with unpacking to a temporary folder take
    # advantage of that to handle permissions, ownership and decryption
    # tasks before moving the files into their final location.
    
    # Handle any default permissions and ownership
    default_uid = 0
    default_gid = 0
    default_perms = nil

    if metadata[:file_defaults]
      if metadata[:file_defaults][:posix]
        if metadata[:file_defaults][:posix][:owner]
          default_uid = Tpkg::lookup_uid(metadata[:file_defaults][:posix][:owner])
        end
        if metadata[:file_defaults][:posix][:group]
          default_gid = Tpkg::lookup_gid(metadata[:file_defaults][:posix][:group])
        end
        if metadata[:file_defaults][:posix][:perms]
          default_perms = metadata[:file_defaults][:posix][:perms]
        end
      end
    end

    # Set default dir uid/gid to be same as for file.
    default_dir_uid = default_uid 
    default_dir_gid = default_gid
    default_dir_perms = 0755

    if metadata[:dir_defaults]
      if metadata[:dir_defaults][:posix]
        if metadata[:dir_defaults][:posix][:owner]
          default_dir_uid = Tpkg::lookup_uid(metadata[:dir_defaults][:posix][:owner])
        end
        if metadata[:dir_defaults][:posix][:group]
          default_dir_gid = Tpkg::lookup_gid(metadata[:dir_defaults][:posix][:group])
        end
        if metadata[:dir_defaults][:posix][:perms]
          default_dir_perms = metadata[:dir_defaults][:posix][:perms]
        end
      end
    end

    Find.find(root_dir, reloc_dir) do |f|
      # If the package doesn't contain either of the top level
      # directories we need to skip them, find will pass them to us
      # even if they don't exist.
      next if !File.exist?(f)

      begin
        if File.directory?(f)
          File.chown(default_dir_uid, default_dir_gid, f)
        else
          File.chown(default_uid, default_gid, f)
        end
      rescue Errno::EPERM
        raise if Process.euid == 0
      end
      if File.file?(f) && !File.symlink?(f)
        if default_perms
          File.chmod(default_perms, f)
        end
      elsif File.directory?(f) && !File.symlink?(f)
        File.chmod(default_dir_perms, f)
      end
    end

    # Reset the permission/ownership of the conflicting files as how they were before.
    # This needs to be done after the default permission/ownership is applied, but before
    # the handling of ownership/permissions on specific files
    conflicting_files.each do | file, stat |
      File.chmod(stat.mode, file)
      File.chown(stat.uid, stat.gid, file)
    end
    
    # Handle any decryption and ownership/permissions on specific files
    metadata[:files].each do |tpkgfile|
      tpkg_path = tpkgfile[:path]
      working_path = nil
      if tpkg_path[0,1] == File::SEPARATOR
        working_path = File.join(workdir, 'tpkg', 'root', tpkg_path)
      else
        working_path = File.join(workdir, 'tpkg', 'reloc', tpkg_path)
      end
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
            File.chown(uid, gid, working_path)
          rescue Errno::EPERM
            raise if Process.euid == 0
          end
        end
        if tpkgfile[:posix][:perms]
          perms = tpkgfile[:posix][:perms]
          File.chmod(perms, working_path)
        end
      end
      
      # Decrypt any files marked for decryption
      if tpkgfile[:encrypt]
        if passphrase.nil?
          # If the user didn't supply a passphrase then just remove the
          # encrypted file.  This allows users to install packages that
          # contain encrypted files for which they don't have the
          # passphrase.  They end up with just the non-encrypted files,
          # potentially useful for development or QA environments.
          File.delete(working_path)
        else
          Tpkg::decrypt(metadata[:name], working_path, passphrase)
          #digest = Digest::SHA256.file(working_path).hexdigest
          digest = Digest::SHA256.hexdigest(File.read(working_path))
          # get checksum for the decrypted file. Will be used for creating file_metadata.xml
          checksums_of_decrypted_files[File.expand_path(tpkg_path)] = digest 
        end
      end
    end

    # We should get the perms, gid, uid stuff here since all the files
    # have been set up correctly
    Find.find(root_dir, reloc_dir) do |f|
      # If the package doesn't contain either of the top level
      # directory we need to skip them, find will pass them to us
      # even if they don't exist.
      next if !File.exist?(f)
      next if File.symlink?(f)

      # check if it's from root dir or reloc dir
      if f =~ /^#{root_dir}/
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
    
    # Install any init scripts
    init_links(metadata).each do |link, init_script|
      # We don't have to any anything if there's already symlink to our init script.
      # This can happen if user removes pkg manually without removing
      # init symlink
      next if File.symlink?(link) && File.readlink(link) == init_script
      begin
        if !File.exist?(File.dirname(link))
          FileUtils.mkdir_p(File.dirname(link))
        end
        begin
          File.symlink(init_script, link)
        rescue Errno::EEXIST
          # The link name that init_links provides is not guaranteed to
          # be unique.  It might collide with a base system init script
          # or an init script from another tpkg.  If the link name
          # supplied by init_links results in EEXIST then try appending
          # a number to the end of the link name.
          catch :init_link_done do
            (1..9).to_a.each do |i|
              begin
                File.symlink(init_script, link + i.to_s)
                throw :init_link_done
              rescue Errno::EEXIST
              end
            end
            # If we get here (i.e. we never reached the throw) then we
            # failed to create any of the possible link names.
            raise "Failed to install init script #{init_script} -> #{link} for #{File.basename(package_file)}"
          end
        end
      rescue Errno::EPERM
        # If creating the link fails due to permission problems and
        # we're not running as root just warn the user, allowing folks
        # to run tpkg as a non-root user with reduced functionality.
        if Process.euid == 0
          raise
        else
          warn "Failed to install init script for #{File.basename(package_file)}, probably due to lack of root privileges"
        end
      end
    end
    
    # Install any crontabs
    crontab_destinations(metadata).each do |crontab, destination|
      begin
        if destination[:link]
          next if File.symlink?(destination[:link]) && File.readlink(destination[:link]) == crontab
          if !File.exist?(File.dirname(destination[:link]))
            FileUtils.mkdir_p(File.dirname(destination[:link]))
          end
          begin
            File.symlink(crontab, destination[:link])
          rescue Errno::EEXIST
            # The link name that crontab_destinations provides is not
            # guaranteed to be unique.  It might collide with a base
            # system crontab or a crontab from another tpkg.  If the
            # link name supplied by crontab_destinations results in
            # EEXIST then try appending a number to the end of the link
            # name.
            catch :crontab_link_done do
              (1..9).to_a.each do |i|
                begin
                  File.symlink(crontab, destination[:link] + i.to_s)
                  throw :crontab_link_done
                rescue Errno::EEXIST
                end
              end
              # If we get here (i.e. we never reached the throw) then we
              # failed to create any of the possible link names.
              raise "Failed to install crontab #{crontab} -> #{destination[:link]} for #{File.basename(package_file)}"
            end
          end
        elsif destination[:file]
          if !File.exist?(File.dirname(destination[:file]))
            FileUtils.mkdir_p(File.dirname(destination[:file]))
          end
          tmpfile = Tempfile.new(File.basename(destination[:file]), File.dirname(destination[:file]))
          if File.exist?(destination[:file])
            # Match permissions and ownership of current crontab
            st = File.stat(destination[:file])
            File.chmod(st.mode & 07777, tmpfile.path)
            File.chown(st.uid, st.gid, tmpfile.path)
            # Insert the contents of the current crontab file
            File.open(destination[:file]) { |file| tmpfile.write(file.read) }
          end
          # Insert a header line so we can find this section to remove later
          tmpfile.puts "### TPKG START - #{@base} - #{File.basename(package_file)}"
          # Insert the package crontab contents
          crontab_contents = IO.read(crontab)
          tmpfile.write(crontab_contents)
          # Insert a newline if the crontab doesn't end with one
          if crontab_contents.chomp == crontab_contents
            tmpfile.puts
          end
          # Insert a footer line
          tmpfile.puts "### TPKG END - #{@base} - #{File.basename(package_file)}"
          tmpfile.close
          File.rename(tmpfile.path, destination[:file])
          # FIXME: On Solaris we should bounce cron or use the crontab
          # command, otherwise cron won't pick up the changes
        end
      rescue Errno::EPERM
        # If installing the crontab fails due to permission problems and
        # we're not running as root just warn the user, allowing folks
        # to run tpkg as a non-root user with reduced functionality.
        if Process.euid == 0
          raise
        else
          warn "Failed to install crontab for #{File.basename(package_file)}, probably due to lack of root privileges"
        end
      end
    end
    
    # Run postinstall script
    if File.exist?(File.join(workdir, 'tpkg', 'postinstall'))
      # Warn the user about non-executable files, as system will just
      # silently fail and exit if that's the case.
      if !File.executable?(File.join(workdir, 'tpkg', 'postinstall'))
        warn "Warning: postinstall script for #{File.basename(package_file)} is not executable, execution will likely fail"
      end
      # Note this only warns the user if the postinstall fails, it does
      # not raise an exception like we do if preinstall fails.  Raising
      # an exception would leave the package's files installed but the
      # package not registered as installed, which does not seem
      # desirable.  We could remove the package's files and raise an
      # exception, but this seems the best approach to me.
      system(File.join(workdir, 'tpkg', 'postinstall')) || warn("Warning: postinstall for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
    end
    
    # Save metadata for this pkg
    package_name = File.basename(package_file, File.extname(package_file))
    package_metadata_dir = File.join(@metadata_directory, package_name)
    FileUtils.mkdir_p(package_metadata_dir)
    metadata_file = File.new(File.join(package_metadata_dir, "tpkg.xml"), "w")
    metadata[:xml].write(metadata_file)
    metadata_file.close    
    # Save file_metadata.xml for this pkg
    file_metadata = File.join(workdir, 'tpkg', 'file_metadata.xml') 
    if !File.exist?(file_metadata)
      warn "Warning: package #{File.basename(package_file)} does not include file_metadata.xml"
    else
      FileUtils.cp(file_metadata, package_metadata_dir)
      # update file_metadata.xml with perms, owner and group
      file_metadata_xml = REXML::Document.new(File.open(file_metadata))
      file_metadata_xml.root.attributes['package_file'] = File.basename(package_file)
      file_metadata_xml.elements.each("files/file") do | file_ele |
        acl = files_info[file_ele.elements["path"].text] || ""
        acl.each do | key, value |
          ele = file_ele.add_element(key)
          ele.add_text(value.to_s)
        end
        digest = checksums_of_decrypted_files[File.expand_path(file_ele.elements["path"].text)]
        if digest
          digest_ele = file_ele.elements["checksum/digest"]
          digest_ele.add_attribute("encrypted", "true")
          digest_ele = file_ele.elements["checksum"].add_element("digest", {"decrypted" => "true"})
          digest_ele.add_text(digest)
        end
      end
      file = File.open(File.join(package_metadata_dir, "file_metadata.xml"), "w")
      file_metadata_xml.write(file)
      file.close
    end

    # Copy the package file to the directory for installed packages
    FileUtils.cp(package_file, @installed_directory)
    
    # Cleanup
    FileUtils.rm_rf(workdir)
  end
  
  def requirements_for_currently_installed_package(pkgname=nil)
    requirements = []
    metadata_for_installed_packages.each do |metadata|
      if !pkgname || pkgname == metadata[:name]
        req = { :name => metadata[:name],
                :minimum_version => metadata[:version] }
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
      req = { :name => name, :minimum_version => version }
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
  def parse_requests(requests, requirements, packages)
    newreqs = []
    
    requests.each do |request|
      puts "parse_requests processing #{request.inspect}" if @@debug
      if request =~ /^[-\w=<>\d\.]+$/ && !File.file?(request)  # basic package specs ('foo' or 'foo=1.0')
        puts "parse_requests request looks like package spec" if @@debug

        # Tpkg::parse_request is a class method and doesn't know where packages are installed. 
        # So we have to tell it ourselves.
        req = Tpkg::parse_request(request, @installed_directory)
        newreqs << req

        # Initialize the list of possible packages for this req
        if !packages[req[:name]]
          packages[req[:name]] = available_packages_that_meet_requirement(req)
        end
      else  # User specified a file or URI
        req = {}
        metadata = nil
        source = nil
        localpath = nil
        if File.file?(request)
          puts "parse_requests treating request as a file" if @@debug
          localpath = request
          metadata_xml = Tpkg::metadata_from_package(request)
          metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
          source = request
        else
          puts "parse_requests treating request as a URI" if @@debug
          uri = URI.parse(request)  # This just serves as a sanity check
          # Using these File methods on a URI seems to work but is probably fragile
          source = File.dirname(request) + '/' # dirname chops off the / at the end, we need it in order to be compatible with URI.join
          pkgfile = File.basename(request)
          localpath = download(source, pkgfile, Tpkg::tempdir('download'))
          metadata_xml = Tpkg::metadata_from_package(localpath)
          metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
          # Cleanup temp download dir
          FileUtils.rm_rf(localpath)
        end
        req[:name] = metadata[:name]
        pkg = { :metadata => metadata, :source => source }

        newreqs << req
        # The user specified a particular package, so it is the only package
        # that can be used to meet the requirement
        packages[req[:name]] = [pkg]
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
    packages.each do |name, pkgs |
      if pkgs.empty?
        errors << ["Unable to find any packages which satisfy #{name}"]
        satisfied_all = false
        next
      end

      request_satisfied = false # whether or not this request can be satisfied
      possible_errors = []
      pkgs.each do | pkg |
        metadata = pkg[:metadata]
        req = { :name => metadata[:name] }
        # Quick sanity check that the package can be installed on this machine.  
        if !Tpkg::package_meets_requirement?(pkg, req)
          possible_errors << "  Requested package #{metadata[:filename]} doesn't match this machine's OS or architecture"
          next
        end
        # a sanity check that there is at least one package
        # available for each dependency of this package
        dep_satisfied = true
        metadata[:dependencies].each do |depreq|
          if available_packages_that_meet_requirement(depreq).empty?
            possible_errors << "  Requested package #{metadata[:filename]} depends on #{depreq.inspect}, no packages that satisfy that dependency are available"
            dep_satisfied = false
          end
        end
        request_satisfied = true if dep_satisfied
      end
      if !request_satisfied
        errors << ["Unable to find any packages which satisfy #{name}. Possible error(s):"]
        errors << possible_errors
        all_requests_satisfied = false 
      end
    end  

    if !all_requests_satisfied
      puts errors.join("\n")
      raise "Unable to satisfy the request(s)"
    end
  end
  
  CHECK_INSTALL = 1
  CHECK_UPGRADE = 2
  CHECK_REMOVE  = 3
  def conflicting_files(package_file, mode=CHECK_INSTALL)
    metadata_xml = Tpkg::metadata_from_package(package_file)
    metadata = Tpkg::metadata_xml_to_hash(metadata_xml)
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

  def check_for_conflicting_pkgs(pkgs_to_check)
    # loop through packages that we're interested in, check for conflict listing,
    # see if there are any conflicts among each other
    pkgs_to_check.each do | pkg1 |
      # native package might not have conflicts defined so skip
      next if pkg1[:metadata][:conflicts].nil?
      pkg1[:metadata][:conflicts].each do | conflict |
        pkgs_to_check.each do | pkg2 |
          if Tpkg::package_meets_requirement?(pkg2, conflict)
            raise "Package conflicts between #{pkg2.inspect} and #{pkg1.inspect}"
          end
        end
      end
    end
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
            name = pkg[:metadata][:name]
            version = pkg[:metadata][:version]
            package_version = pkg[:metadata][:package_version]
            puts "Native #{name}=#{version}=#{package_version}"
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
  def install(requests, passphrase=nil)
    requirements = []
    packages = {}
    lock
    
    parse_requests(requests, requirements, packages)
    check_requests(packages)
    core_packages = []
    currently_installed_requirements = []
    requirements.each do |req|
      core_packages << req[:name] if !core_packages.include?(req[:name])
      currently_installed_requirements.concat(
        requirements_for_currently_installed_package(req[:name]))
    end
    requirements.concat(currently_installed_requirements).uniq!
    
    puts "install calling best_solution" if @@debug
    puts "install requirements: #{requirements.inspect}" if @@debug
    puts "install packages: #{packages.inspect}" if @@debug
    puts "install core_packages: #{core_packages.inspect}" if @@debug
    #solution_packages = best_solution(requirements.dup, packages.dup)
    solution_packages = best_solution(requirements, packages, core_packages)
    if !solution_packages
      raise "Unable to resolve dependencies"
    end
    
    check_for_conflicting_pkgs(solution_packages | installed_packages)

    if !prompt_for_install(solution_packages, 'installed')
      unlock
      return false
    end

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
        if Tpkg::get_os =~ /RedHat|CentOS|Fedora/
          name = pkg[:metadata][:name]
          version = pkg[:metadata][:version]
          package_version = pkg[:metadata][:package_version]
          # RPMs always have a release/package_version
          pkgname = "#{name}-#{version}-#{package_version}"
          puts "Running 'yum -y install #{pkgname}' to install native package" if @@debug
          system("yum -y install #{pkgname}")
        elsif Tpkg::get_os =~ /Debian|Ubuntu/
          name = pkg[:metadata][:name]
          version = pkg[:metadata][:version]
          pkgname = "#{name}-#{version}"
          if pkg[:metadata][:package_version]
            pkgname << "-#{pkg[:metadata][:package_version]}"
          end
          puts "Running 'apt-get -y install #{pkgname}' to install native package" if @@debug
          system("apt-get -y install #{pkgname}")
        elsif Tpkg::get_os =~ /Solaris/
          name = pkg[:metadata][:name]
          version = pkg[:metadata][:version]
          pkgname = "#{name}-#{version}"
          if pkg[:metadata][:package_version]
            pkgname << ",REV=#{pkg[:metadata][:package_version]}"
          end
          if File.exist?('/opt/csw/bin/pkg-get')
            puts "Running '/opt/csw/bin/pkg-get -i #{pkgname}' to install native package" if @@debug
            system("/opt/csw/bin/pkg-get -i #{pkgname}")
          else
            raise "No native package installation tool available"
          end
        elsif Tpkg::get_os =~ /FreeBSD/
          name = pkg[:metadata][:name]
          version = pkg[:metadata][:version]
          pkgname = "#{name}-#{version}"
          if pkg[:metadata][:package_version]
            pkgname << "_#{pkg[:metadata][:package_version]}"
          end
          puts "Running 'pkg_add -r #{pkgname}' to install native package" if @@debug
          system("pkg_add -r #{pkgname}")
        else
          raise "No native package installation support for #{Tpkg::get_os}"
        end
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
            unpack(pkgfile, passphrase)
          end
        end
      end

      # If we're down here, it means we have installed the package. So go ahead and 
      # update the list of packages we installed so far
      installed_so_far << pkg[:metadata][:name]
    end  # end while loop

    send_update_to_server unless @report_server.nil?
    unlock
  end

  # This method can also be used for doing downgrade
  def upgrade(requests=nil, passphrase=nil, downgrade=false)
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
              additional_requirements << metadata
            end
          end
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
    #solution_packages = best_solution(requirements.dup, packages.dup)
    solution_packages = best_solution(requirements, packages, core_packages)
  
    if solution_packages.nil?
      raise "Unable to find solution for upgrading. Please verify that you specified the correct package(s) for upgrade."
    end

    check_for_conflicting_pkgs(solution_packages | installed_packages)

    if downgrade
      prompt_action = 'downgrade'
    else
      prompt_action = 'upgrade'
    end
    if !prompt_for_install(solution_packages, prompt_action)
      unlock
      return false
    end
    
    installed_files = files_for_installed_packages
    removed_pkgs = [] # keep track of what we removed so far
    while pkg = solution_packages.shift
#    solution_packages.each do |pkg|
      if pkg[:source] == :currently_installed ||
         pkg[:source] == :native_installed
        # Nothing to do for packages currently installed
      elsif pkg[:source] == :native_available
        if Tpkg::get_os =~ /RedHat|CentOS|Fedora/
          name = pkg[:metadata][:name]
          version = pkg[:metadata][:version]
          package_version = pkg[:metadata][:package_version]
          # RPMs always have a release/package_version
          pkgname = "#{name}-#{version}-#{package_version}"
          puts "Running 'yum -y install #{pkgname}' to upgrade native package" if @@debug
          system("yum -y install #{pkgname}")
          has_updates = true
        elsif Tpkg::get_os =~ /Debian|Ubuntu/
          name = pkg[:metadata][:name]
          version = pkg[:metadata][:version]
          pkgname = "#{name}-#{version}"
          if pkg[:metadata][:package_version]
            pkgname << "-#{pkg[:metadata][:package_version]}"
          end
          puts "Running 'apt-get -y install #{pkgname}' to upgrade native package" if @@debug
          system("apt-get -y install #{pkgname}")
          has_updates = true
        elsif Tpkg::get_os =~ /Solaris/
          name = pkg[:metadata][:name]
          version = pkg[:metadata][:version]
          pkgname = "#{name}-#{version}"
          if pkg[:metadata][:package_version]
            pkgname << ",REV=#{pkg[:metadata][:package_version]}"
          end
          if File.exist?('/opt/csw/bin/pkg-get')
            puts "Running '/opt/csw/bin/pkg-get -i #{pkgname}' to upgrade native package" if @@debug
            system("/opt/csw/bin/pkg-get -i #{pkgname}")
            has_updates = true
          else
            raise "No native package upgrade tool available"
          end
        elsif Tpkg::get_os =~ /FreeBSD/
          name = pkg[:metadata][:name]
          version = pkg[:metadata][:version]
          pkgname = "#{name}-#{version}"
          if pkg[:metadata][:package_version]
            pkgname << "_#{pkg[:metadata][:package_version]}"
          end
          # This is not very ideal.  It would be better to download the
          # new package, and if the download is successful remove the
          # old package and install the new one.  The way we're doing it
          # here we risk leaving the system with neither version
          # installed if the download of the new package fails.
          # However, the FreeBSD package tools don't make it easy to
          # handle things properly.
          puts "Running 'pkg_delete #{name}' and 'pkg_add -r #{pkgname}' to upgrade native package" if @@debug
          system("pkg_delete #{name}")
          system("pkg_add -r #{pkgname}")
          has_updates = true
        else
          raise "No native package upgrade support for #{Tpkg::get_os}"
        end
      else  # tpkg
        pkgfile = nil
        if File.file?(pkg[:source])
          pkgfile = pkg[:source]
        elsif File.directory?(pkg[:source])
          pkgfile = File.join(pkg[:source], pkg[:metadata][:filename])
        else
          pkgfile = download(pkg[:source], pkg[:metadata][:filename])
        end
        if prompt_for_conflicting_files(pkgfile, CHECK_UPGRADE)
          # If the old and new packages have overlapping externals flag them
          # to be skipped so that the external isn't removed and then
          # immediately re-added
          oldpkgs = installed_packages_that_meet_requirement({:name => pkg[:metadata][:name]})
          externals_to_skip = []
          pkg[:metadata][:externals].each do |external|
            if oldpkgs.all? {|oldpkg| oldpkg[:metadata][:externals].include?(external)}
              externals_to_skip << external
            end
          end

          # Remove the old package if we haven't done so
          unless removed_pkgs.include?(pkg[:metadata][:name])
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
          end
          if can_unpack
            unpack(pkgfile, passphrase, :externals_to_skip => externals_to_skip)
          end

          has_updates = true
        end
      end
    end
   
    if !has_updates
      puts "No updates available"
    elsif !@report_server.nil? 
      send_update_to_server 
    end

    unlock
  end
  
  def remove(requests=nil, options={})
    lock
    
    packages_to_remove = nil
    if requests
      packages_to_remove = []
      requests.each do |request|
        req = Tpkg::parse_request(request, @installed_directory)
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
    
    # Check that this doesn't leave any dependencies unresolved
    if !options[:upgrade]
      pkg_files_to_remove = packages_to_remove.map { |pkg| pkg[:metadata][:filename] }
      metadata_for_installed_packages.each do |metadata|
        next if pkg_files_to_remove.include?(metadata[:filename])
        metadata[:dependencies].each do |req|
          # We ignore native dependencies because there is no way a removal
          # can break a native dependency, we don't support removing native
          # packages.
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
    if !options[:upgrade]
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
      system("#{@tar} -xf #{package_file} -O #{File.join(topleveldir, 'tpkg.tar')} | #{@tar} -C #{workdir} -xpf -")
    
      # Run preremove script
      if File.exist?(File.join(workdir, 'tpkg', 'preremove'))
        # Warn the user about non-executable files, as system will just
        # silently fail and exit if that's the case.
        if !File.executable?(File.join(workdir, 'tpkg', 'preremove'))
          warn "Warning: preremove script for #{File.basename(package_file)} is not executable, execution will likely fail"
        end
        if @force
          system(File.join(workdir, 'tpkg', 'preremove')) || warn("Warning: preremove for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
        else
          system(File.join(workdir, 'tpkg', 'preremove')) || raise("Error: preremove for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
        end
      end
    
      # Remove any init scripts
      init_links(pkg[:metadata]).each do |link, init_script|
        # The link we ended up making when we unpacked the package could
        # be any of a series (see the code in unpack for the reasoning),
        # we need to check them all.
        links = [link]
        links.concat((1..9).to_a.map { |i| link + i.to_s })
        links.each do |l|
          if File.symlink?(l) && File.readlink(l) == init_script
            begin
              File.delete(l)
            rescue Errno::EPERM
              if Process.euid == 0
                raise
              else
                warn "Failed to remove init script for #{File.basename(package_file)}, probably due to lack of root privileges"
              end
            end
          end
        end
      end
    
      # Remove any crontabs
      crontab_destinations(pkg[:metadata]).each do |crontab, destination|
        begin
          if destination[:link]
            # The link we ended up making when we unpacked the package could
            # be any of a series (see the code in unpack for the reasoning),
            # we need to check them all.
            links = [destination[:link]]
            links.concat((1..9).to_a.map { |i| destination[:link] + i.to_s })
            links.each do |l|
              if File.symlink?(l) && File.readlink(l) == crontab
                begin
                  File.delete(l)
                rescue Errno::EPERM
                  if Process.euid == 0
                    raise
                  else
                    warn "Failed to remove crontab for #{File.basename(package_file)}, probably due to lack of root privileges"
                  end
                end
              end
            end
          elsif destination[:file]
            if File.exist?(destination[:file])
              tmpfile = Tempfile.new(File.basename(destination[:file]), File.dirname(destination[:file]))
              # Match permissions and ownership of current crontab
              st = File.stat(destination[:file])
              File.chmod(st.mode & 07777, tmpfile.path)
              File.chown(st.uid, st.gid, tmpfile.path)
              # Remove section associated with this package
              skip = false
              IO.foreach(destination[:file]) do |line|
                if line == "### TPKG START - #{@base} - #{File.basename(package_file)}\n"
                  skip = true
                elsif line == "### TPKG END - #{@base} - #{File.basename(package_file)}\n"
                  skip = false
                elsif !skip
                  tmpfile.write(line)
                end
              end
              tmpfile.close
              File.rename(tmpfile.path, destination[:file])
              # FIXME: On Solaris we should bounce cron or use the crontab
              # command, otherwise cron won't pick up the changes
            end
          end
        rescue Errno::EPERM
          # If removing the crontab fails due to permission problems and
          # we're not running as root just warn the user, allowing folks
          # to run tpkg as a non-root user with reduced functionality.
          if Process.euid == 0
            raise
          else
            warn "Failed to remove crontab for #{File.basename(package_file)}, probably due to lack of root privileges"
          end
        end
      end
      
      # Run any externals
      pkg[:metadata][:externals].each do |external|
        if !options[:externals_to_skip] || !options[:externals_to_skip].include?(external)
          run_external(pkg[:metadata][:filename], :remove, external[:name], external[:data])
        end
      end
      
      # Remove files
      files_to_remove = conflicting_files(package_file, CHECK_REMOVE)
      # Reverse the order of the files, as directories will appear first
      # in the listing but we want to remove any files in them before
      # trying to remove the directory.
      files_to_remove.reverse.each do |file|
        begin
          if !File.directory?(file)
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
        end
      end
    
      # Run postremove script
      if File.exist?(File.join(workdir, 'tpkg', 'postremove'))
        # Warn the user about non-executable files, as system will just
        # silently fail and exit if that's the case.
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
      end
    
      File.delete(package_file)

      # delete metadata dir of this package
      package_metadata_dir = File.join(@metadata_directory, File.basename(package_file, File.extname(package_file)))
      FileUtils.rm_rf(package_metadata_dir)

      # Cleanup
      FileUtils.rm_rf(workdir)
    end
    
    send_update_to_server unless @report_server.nil? || options[:upgrade]
    unlock
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

      # get file_metadata.xml from the installed package
      file_metadata = File.join(@metadata_directory, package_full_name, 'file_metadata.xml')
      if File.exist?(file_metadata)
        file_metadata_xml = REXML::Document.new(File.open(file_metadata))
      else 
        errors = []
        errors << "Can't find file_metadata.xml file. Most likely this is because the package was created before the verify feature was added"
        results[package_file] = errors
        return results
      end

      # verify installed files match their checksum 
      file_metadata_xml.elements.each('/files/file') do |file|
        errors = []   
        gid_expected, uid_expected, perms_expected, chksum_expected = nil
        fp = file.elements["path"].text

        # get expected checksum. For files that were encrypted, we're interested in the
        # checksum of the decrypted version 
        if file.elements["checksum"]
          chksum_expected = file.elements["checksum"].elements["digest"].text
          file.elements.each("checksum/digest") do | digest_ele |
            if digest_ele.attributes["decrypted"]
              chksum_expected = digest_ele.text
            end
          end
        end

        # get expected acl values
        if file.elements["uid"]
          uid_expected = file.elements["uid"].text.to_i
        end
        if file.elements["gid"]
          gid_expected = file.elements["gid"].text.to_i
        end
        if file.elements["perms"]
          perms_expected = file.elements["perms"].text
        end 

        # normalize file path
        if file.attributes["relocatable"] == "true"
          fp = File.join(@base, fp)
        else
          fp = File.join(@file_system_root, fp)
        end
  
        # can't handle symlink
        if File.symlink?(fp)
          next
        end
   
        # check if file exist
        if !File.exists?(fp)
          errors << "File is missing"
        else 
          # get actual values 
          #chksum_actual = Digest::SHA256.file(fp).hexdigest if File.file?(fp)
          chksum_actual = Digest::SHA256.hexdigest(File.read(fp)) if File.file?(fp)
          uid_actual = File.stat(fp).uid
          gid_actual = File.stat(fp).gid
          perms_actual = File.stat(fp).mode.to_s(8)
        end

        if !chksum_expected.nil? && !chksum_actual.nil? && chksum_expected != chksum_actual
          errors << "Checksum doesn't match"
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
  
  def execute_init(requests, action)
    packages_to_execute_on = []
    requests.each do |request|
      req = Tpkg::parse_request(request)
      packages_to_execute_on.concat(installed_packages_that_meet_requirement(req))
    end
    
    packages_to_execute_on.each do |pkg|
      execute_init_for_package(pkg, action)
    end 
  end
  
  def execute_init_for_package(pkg, action)
    init_scripts_metadata = init_scripts(pkg[:metadata])

    # warn if there's no init script and then return
    if init_scripts_metadata.nil? || init_scripts_metadata.empty?
      warn "Warning: There is no init script for #{pkg[:metadata][:name]}"
      return
    end

    # convert the init scripts metadata  to an array of { path => value, start => value}
    # so that we can order them based on their start value. This is necessary because
    # we need to execute the init scripts in correct order.
    init_scripts = []
    init_scripts_metadata.each do | installed_path, init_info |
      init = {}
      init[:path] = installed_path
      init[:start] = init_info[:init][:start] || 0
      init_scripts << init
    end

    # Reverse order if doing stop. 
    if action == "stop"
      ordered_init_scripts = init_scripts.sort{ |a,b| b[:start] <=> a[:start] }
    else
      ordered_init_scripts = init_scripts.sort{ |a,b| a[:start] <=> b[:start] }
    end

    ordered_init_scripts.each do |init_script|
      installed_path = init_script[:path]
      system("#{installed_path} #{action}")
    end 
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

  def send_update_to_server
    # put all the packages xml metadata inside a <packages> tag
    xml = "<packages>"
    metadata_for_installed_packages.each do | metadata |
     xml += metadata[:xml].root.to_s
    end
    xml += "</packages>"

    begin
      update_uri =  URI.parse("#{@report_server}")
      http = Tpkg::gethttp(update_uri)
      request = {"xml"=>URI.escape(xml), "client"=>Facter['fqdn'].value}
      post = Net::HTTP::Post.new(update_uri.path)
      post.set_form_data(request)
      response = http.request(post)

      case response
      when Net::HTTPSuccess
#       puts "Response from server:\n'#{response.body}'"
       puts "Successfully send update to reporter server"
      else
        $stderr.puts response.body
        #response.error!
        # just ignore error and give user warning
        puts "Failed to send update to reporter server"
      end
    rescue
      puts "Failed to send update to reporter server"
    end
  end  
  
  def extract_tpkgxml(package_file)
    result = ""
    workdir = ""
    begin
      topleveldir = Tpkg::package_toplevel_directory(package_file)
      workdir = Tpkg::tempdir(topleveldir)
      system("#{@tar} -xf #{package_file} -O #{File.join(topleveldir, 'tpkg.tar')} | #{@tar} -C #{workdir} -xpf -")

      if !File.exist?(File.join(workdir,"tpkg", "tpkg.xml"))
        raise "#{package_file} does not contain tpkg.xml" 
      else
        File.open(File.join(workdir,"tpkg", "tpkg.xml"), "r") do | f |
          result = f.read
        end
      end 
    rescue
      puts "Failed to extract package."
    ensure
      FileUtils.rm_rf(workdir) if workdir
    end
    return result
  end
end

