##############################################################################
# tpkg package management system library
# Copyright 2009, AT&T Interactive
# License: MIT (http://www.opensource.org/licenses/mit-license.php)
##############################################################################

# We need this because when we build the binary for tpkg, we put
# this file in PATH_TO_RUBY_LIB/lib and then the rest of
# the ruby files (versiontype.rb, deployer.rb, etc) into PATH_TO_RUBY_LIB/lib/tpkg
$:.unshift(File.join(File.dirname(__FILE__), 'tpkg'))

require 'facter'         # Facter
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
require 'versiontype'    # Version
require 'deployer'

# clean up "using default DH parameters" warning for https
# http://blog.zenspider.com/2008/05/httpsssl-warning-cleanup.html
class Net::HTTP
  alias :old_use_ssl= :use_ssl=
  def use_ssl= flag
    self.old_use_ssl = flag
    @ssl_context.tmp_dh_callback = proc {}
  end
end

class Tpkg
  
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
        digest << pipe.read
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
  
  # Extracts and returns the metadata from a directory of package files
  def self.metadata_from_directory(directory)
    metadata = []
    Dir.glob(File.join(directory, '*.tpkg')) do |pkg|
      metadata << metadata_from_package(pkg)
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
      metadata_xml.root << md.root
    end
    # And write that out to metadata.xml
    metadata_tmpfile = Tempfile.new('metadata.xml', directory)
    metadata_xml.write(metadata_tmpfile)
    metadata_tmpfile.close
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
  
  def self.extract_operatingsystem_from_metadata(metadata)
    operatingsystems = []
    if metadata.elements['/tpkg/operatingsystem'] && !metadata.elements['/tpkg/operatingsystem'].text.empty?
      operatingsystems = metadata.elements['/tpkg/operatingsystem'].text.split(/\s*,\s*/)
    end
    operatingsystems
  end
  def self.extract_architecture_from_metadata(metadata)
    architectures = []
    if metadata.elements['/tpkg/architecture'] && !metadata.elements['/tpkg/architecture'].text.empty?
      architectures = metadata.elements['/tpkg/architecture'].text.split(/\s*,\s*/)
    end
    architectures
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
    metadata = pkg[:metadata]
    if req[:native] && pkg[:source] != :native_installed && pkg[:source] != :native_available
      # A req for a native package must be satisfied by a native package
      result = false
    elsif !req[:native] && (pkg[:source] == :native_installed || pkg[:source] == :native_available)
      # Likewise a req for a tpkg must be satisfied by a tpkg
      result = false
    elsif metadata.elements['/tpkg/name'].text == req[:name]
      if req[:minimum_version]
        pkgver = Version.new(metadata.elements['/tpkg/version'].text)
        reqver = Version.new(req[:minimum_version])
        if pkgver < reqver
          result = false
        end
      end
      if req[:maximum_version]
        pkgver = Version.new(metadata.elements['/tpkg/version'].text)
        reqver = Version.new(req[:maximum_version])
        if pkgver > reqver
          result = false
        end
      end
      if req[:minimum_package_version]
        pkgver = Version.new(metadata.elements['/tpkg/package_version'].text)
        reqver = Version.new(req[:minimum_package_version])
        if pkgver < reqver
          result = false
        end
      end
      if req[:maximum_package_version]
        pkgver = Version.new(metadata.elements['/tpkg/package_version'].text)
        reqver = Version.new(req[:maximum_package_version])
        if pkgver > reqver
          result = false
        end
      end
      pkgos = extract_operatingsystem_from_metadata(metadata)
      if !pkgos.empty? && !pkgos.include?(get_os)
        result = false
      end
      pkgarch = extract_architecture_from_metadata(metadata)
      if !pkgarch.empty? && !pkgarch.include?(Facter['hardwaremodel'].value)
        result = false
      end
    else
      result = false
    end
    if result
    end
    result
  end
  
  def self.extract_reqs_from_metadata(metadata)
    reqs = []
    metadata.elements.each('/tpkg/dependencies/dependency') do |dep|
      req = {}
      req[:name] = dep.elements['name'].text
      depminversion = dep.elements['minimum_version']
      depmaxversion = dep.elements['maximum_version']
      depminpkgversion = dep.elements['minimum_package_version']
      depmaxpkgversion = dep.elements['maximum_package_version']
      depnative = dep.elements['native']
      if depminversion && !depminversion.text.empty?
        req[:minimum_version] = depminversion.text
      end
      if depmaxversion && !depmaxversion.text.empty?
        req[:maximum_version] = depmaxversion.text
      end
      if depminpkgversion && !depminpkgversion.text.empty?
        req[:minimum_package_version] = depminpkgversion.text
      end
      if depmaxpkgversion && !depmaxpkgversion.text.empty?
        req[:maximum_package_version] = depmaxpkgversion.text
      end
      if depnative
        req[:native] = true
      end
      reqs << req
    end
    reqs
  end
  
  # Define a block for sorting packages in order of desirability
  # Suitable for passing to Array#sort as array.sort(&@@sort_packages)
  @@sort_packages = lambda do |a,b|
    #
    # We first prepare all of the values we wish to compare
    #
    
    # Name
    aname = a[:metadata].elements['/tpkg/name'].text
    bname = b[:metadata].elements['/tpkg/name'].text
    # Currently installed
    # Conflicted about whether this belongs here or not.  The dependencies
    # method handles :currently_installed specially anyway when scoring
    # packages, not sure if other potential users of this sorting system
    # would want to prefer currently installed packages.
    acurrentinstall = 0
    if (a[:source] == :currently_installed || a[:source] == :native_installed) && a[:prefer] == true
      acurrentinstall = 1
    end
    bcurrentinstall = 0
    if (b[:source] == :currently_installed || b[:source] == :native_installed) && b[:prefer] == true
      bcurrentinstall = 1
    end
    # Version
    aversion = Version.new(a[:metadata].elements['/tpkg/version'].text)
    bversion = Version.new(b[:metadata].elements['/tpkg/version'].text)
    # Package version
    apkgver = Version.new(0)
    ametapkgver = a[:metadata].elements['/tpkg/package_version']
    if ametapkgver && !ametapkgver.text.empty?
      apkgver = Version.new(ametapkgver.text)
    end
    bpkgver = Version.new(0)
    bmetapkgver = b[:metadata].elements['/tpkg/package_version']
    if bmetapkgver && !bmetapkgver.text.empty?
      bpkgver = Version.new(bmetapkgver.text)
    end
    # OS
    #  Fewer OSs is better, but zero is least desirable because zero means
    #  the package works on all OSs (i.e. it is the most generic package).
    #  We prefer packages tuned to a particular set of OSs over packages
    #  that work everywhere on the assumption that the package that works
    #  on only a few platforms was tuned more specifically for those
    #  platforms.  We remap 0 to a big number so that the sorting works
    #  properly.
    aoslength = extract_operatingsystem_from_metadata(a[:metadata]).length
    if aoslength == 0
      # See comments above
      aoslength = 1000
    end
    boslength = extract_operatingsystem_from_metadata(b[:metadata]).length
    if boslength == 0
      boslength = 1000
    end
    # Architecture
    #  Same deal here, fewer architectures is better but zero is least desirable
    aarchlength = extract_architecture_from_metadata(a[:metadata]).length
    if aarchlength == 0
      aarchlength = 1000
    end
    barchlength = extract_architecture_from_metadata(b[:metadata]).length
    if barchlength == 0
      barchlength = 1000
    end
    
    #
    # Then compare
    #
    
    # The mixture of a's and b's in these two arrays may seem odd at first,
    # but for some fields bigger is better (versions) but for other fields
    # smaller is better.
    [aname, bcurrentinstall, bversion, bpkgver, aoslength, aarchlength] <=> [bname, acurrentinstall, aversion, apkgver, boslength, barchlength]
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
      raise "Only http/https URIs are supported"
    end
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
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
  def self.parse_request(request)
    # FIXME: Add support for <, <=, >, >=
    req = {}
    parts = request.split('=')
    if parts.length > 2 && parts[-2] =~ /^[\d\.]/ && parts[-1] =~ /^[\d\.]/
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
      @sources.each do |source|
        if !File.exist?(source)
          if source !~ %r{/$}
            source = source + '/'
          end
        end
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
    
    @file_system_root = '/'  # Not sure if this needs to be more portable
    # This option is only intended for use by the test suite
    if options[:file_system_root]
      @file_system_root = options[:file_system_root]
      @base = File.join(@file_system_root, @base)
    end
    
    # Other instance variables
    @metadata = []
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
    
    refresh_metadata
  end
  
  def source_to_local_path(source)
    source_as_directory = source.gsub(/[^a-zA-Z0-9]/, '')
    localpath = File.join(@sources_directory, source_as_directory)
    if !File.exist?(localpath)
      FileUtils.mkdir_p(localpath)
    end
    localpath
  end
  
  # Used by refresh_metadata to stuff all the info about a native
  # package into an XML document to match the structure we pass around
  # internally for tpkgs
  def pkg_for_native_package(name, version, package_version, source)
    metadata = REXML::Document.new('<tpkg></tpkg>')
    name_elem = REXML::Element.new('name')
    name_elem.text = name
    metadata.root.add(name_elem)
    version_elem = REXML::Element.new('version')
    version_elem.text = version
    metadata.root.add(version_elem)
    if package_version
      package_version_elem = REXML::Element.new('package_version')
      package_version_elem.text = package_version
      metadata.root.add(package_version_elem)
    end
    pkg = { :metadata => metadata, :source => source }
    if source == :native_installed
      pkg[:prefer] = true
    end
    pkg
  end
  
  # Populate/refresh our list of available packages
  def refresh_metadata
    @metadata.clear
    
    #
    # Tpkg packages
    #
    
    @sources.each do |source|
      if File.file?(source)
        @metadata << { :metadata => Tpkg::metadata_from_package(source), :source => source }
      else
        uri = URI.join(source, 'metadata.xml')
        http = Tpkg::gethttp(uri)
        
        # Calculate the path to the local copy of the metadata for this URI
        localpath = File.join(source_to_local_path(source), 'metadata.xml')
        localdate = nil
        if File.exist?(localpath)
          localdate = File.mtime(localpath)
        end
        
        # Check if the local copy is out of data
        remotedate = nil
        response = http.head(uri.path)
        case response
        when Net::HTTPSuccess
          remotedate = Time.httpdate(response['Date'])
        else
          puts "Error fetching metadata from #{uri}: #{response.body}"
          response.error!  # Throws an exception
        end
        if !localdate || remotedate != localdate
          response = http.get(uri.path)
          case response
          when Net::HTTPSuccess
            File.open(localpath, 'w') do |file|
              file.puts(response.body)
            end
            File.utime(remotedate, remotedate, localpath)
          else
            puts "Error fetching metadata from #{uri}: #{response.body}"
            response.error!  # Throws an exception
          end
        end
        
        metadata_xml = REXML::Document.new(File.open(localpath))
        metadata_xml.elements.each('/tpkg_metadata/tpkg') do |pkgmetadata|
          # Make a new REXML document for each entry so they function
          # like the document from an individual file source
          @metadata << { :metadata => REXML::Document.new(pkgmetadata.to_s), :source => source }
        end
      end
    end
    if @@debug
      @sources.each do |source|
        puts "Found #{@metadata.select{|m| m[:source] == source}.length} tpkgs from #{source}"
      end
    end
    
    #
    # Native packages
    #
    
    if Tpkg::get_os =~ /RedHat|CentOS/
      [ {:arg => 'installed', :header => 'Installed', :source => :native_installed},
        {:arg => 'available', :header => 'Available', :source => :native_available} ].each do |yum|
        puts "Running 'yum list #{yum[:arg]}' to gather native package info" if @@debug
        IO.popen("yum list #{yum[:arg]}") do |pipe|
          read_packages = false
          pipe.each_line do |line|
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
              @metadata << pkg
            end
          end
        end
        if !$?.success?
          raise "Error running yum to get installed and available native packages"
        end
      end
    elsif Tpkg::get_os =~ /Debian/
      # The default 'dpkg -l' format has an optional third column for
      # errors, which makes it hard to parse reliably.
      puts "Running dpkg-query -W -f='${Package} ${Version} ${Status}\n' to gather installed native packages" if @@debug
      IO.popen("dpkg-query -W -f='${Package} ${Version} ${Status}\n'") do |pipe|
        pipe.each_line do |line|
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
            @metadata << pkg
          end
        end
      end
      if !$?.success?
        raise "Error running dpkg to get installed native packages"
      end
      puts "Running 'apt-cache dumpavail' to gather available native packages" if @@debug
      IO.popen('apt-cache dumpavail') do |pipe|
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
            @metadata << pkg
          end
        end
      end
      if !$?.success?
        raise "Error running apt-cache to get available native packages"
      end
    elsif Tpkg::get_os =~ /Solaris/
      # Example of pkginfo -x output:
      # SUNWzfsu                      ZFS (Usr)
      #                               (i386) 11.10.0,REV=2006.05.18.01.46
      puts "Running 'pkginfo -x' to gather installed native packages" if @@debug
      IO.popen('pkginfo -x') do |pipe|
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
            @metadata << pkg
          end
        end
      end
      if !$?.success?
        raise "Error running pkginfo to get installed native packages"
      end
      if File.exist?('/opt/csw/bin/pkg-get')
        puts "Running '/opt/csw/bin/pkg-get -a' to gather available native packages" if @@debug
        IO.popen('/opt/csw/bin/pkg-get -a') do |pipe|
          pipe.each_line do |line|
            next if line =~ /^#/  # Skip comments
            name, solversion = line.split
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
            @metadata << pkg
          end
        end
      end
    elsif Tpkg::get_os =~ /FreeBSD/
      puts "Running 'pkg_info' to gather installed native packages" if @@debug
      IO.popen("pkg_info") do |pipe|
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
          @metadata << pkg
        end
      end
      if !$?.success?
        raise "Error running pkg_info to get installed native packages"
      end
      # FIXME: FreeBSD available packages
      # We could either poke around in the ports tree (if installed), or
      # try to recreate the URL "pkg_add -r" would use and pull a
      # directory listing.
    end
    if @@debug
      puts "Found #{@metadata.select{|m| m[:source] == :native_installed}.length} installed native packages"
      puts "Found #{@metadata.select{|m| m[:source] == :native_available}.length} available native packages"
    end
  end
  
  # Returns an array of the tpkg.xml metadata for installed packages
  def metadata_for_installed_packages
    metadata = []
    if File.directory?(@installed_directory)
      Dir.foreach(@installed_directory) do |entry|
        next if entry == '.' || entry == '..' || entry == 'metadata'
        # check to see if we already have a saved copy of the meta data
        package_metadata_dir = File.join(@metadata_directory, File.basename(entry, File.extname(entry)))
        metadata_file = File.join(package_metadata_dir, "tpkg.xml")
        if File.exists?(metadata_file)
          metadata << REXML::Document.new(File.open(metadata_file))
        else # otherwise, we have to extract it ourselves. Save it for next time
          tmp = Tpkg::metadata_from_package(File.join(@installed_directory, entry))
          metadata << tmp
          begin
            FileUtils.mkdir_p(package_metadata_dir) if !File.exists?package_metadata_dir
            file = File.new(metadata_file, "w")
            file.write(tmp)
            file.close
          rescue Errno::EACCES
            raise if Process.euid == 0
          end
        end
      end
    end
    metadata
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
    if req
      @metadata.each do |pkg|
        if Tpkg::package_meets_requirement?(pkg, req)
          pkgs << pkg
        end
      end
    else
      pkgs = @metadata.dup
    end
    pkgs
  end
  def installed_packages_that_meet_requirement(req=nil)
    pkgs = []
    metadata_for_installed_packages.each do |metadata|
      pkg = {:metadata => metadata}
      if req
        if Tpkg::package_meets_requirement?(pkg, req)
          pkgs << pkg
        end
      else
        pkgs << pkg
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
        package_files << metadata.root.attributes['filename']
      end
    end
    metadata_for_installed_packages.each do |metadata|
      package_file = metadata.root.attributes['filename']
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
  # available packages.  Both the packages parameter and the return value
  # are in the form of a hash with package names as keys pointing to
  # arrays of package specs (our standard hash of package metadata and
  # source).  The return value will be an array of package specs.
  def best_solution(requirements, packages)
    solutions = solve_dependencies(requirements, packages)
    
    # Score solutions and pick the best one
    bestscore = nil
    bestsol = nil
    if solutions
      solutions.each do |sol|
        total = 0
        count = 0
        sol.each do |pkgname, pkgs|
          count += 1
          # Sanity check
          if pkgs.length != 1
            raise "Solution contains #{pkgs.length} pkgs for #{pkgname}, should be 1"
          end
          pkg = pkgs.first
          pkgscore = nil
          if (pkg[:source] == :currently_installed || pkg[:source] == :native_installed) && pkg[:prefer] == true
            pkgscore = 0
          else
            # Packages added due to dependencies won't have populated lists
            # of possible packages in our copy of the possible packages list.
            # Populate that now so that we can score this solution's package
            # against all possible packages.
            if !packages[pkgname]
              req = {:name => pkgname}
              if pkg[:source] == :native_available || pkg[:source] == :native_installed
                req[:native] = true
              end
              packages[pkgname] = available_packages_that_meet_requirement(req)
              if pkg[:source] == :currently_installed || pkg[:source] == :native_installed
                packages[pkgname] << pkg
              end
            end
            allpkgs = packages[pkgname].sort(&@@sort_packages)
            # +1 the score here so that currently installed packages are
            # preferred.  I.e. the best score a package can get here is 1,
            # but preferred, currently installed packages get 0.
            pkgscore = allpkgs.index(pkg) + 1
          end
          total += pkgscore
        end
        # to_f forces floating point math
        score = total.to_f / count
        if !bestscore || score < bestscore
          bestscore = score
          bestsol = sol
        end
      end
    end
    
    if @@debug
      puts "best_solution picks: #{bestsol.inspect}"
    end
    #bestsol
    # Return just a list of the packages rather than the solution structure,
    # which isn't really useful to the user
    packages = nil
    if bestsol
      packages = []
      bestsol.each_value { |pkgs| packages << pkgs.first }
    end
    packages
  end
  
  # Recursive function used by best_solution method to get possible
  # solutions to package requirements
  def solve_dependencies(requirements, packages)
    # Find an unsolved requirement
    unsolved = requirements.detect { |req| !req[:solved] }
    
    # If there are no unsolved reqs return an indication that we've
    # found a solution
    if !unsolved
      if @@debug
        puts "solve_dependencies found a solution: #{packages.inspect}"
      end
      return [packages]
    end
    
    # Initialize the list of packages for this req if necessary
    filtered_packages = nil
    if !packages[unsolved[:name]]
      packages[unsolved[:name]] = available_packages_that_meet_requirement(unsolved)
      filtered_packages = packages
    else
      # Loop over possible packages and eliminate ones that don't work for
      # this requirement
      filtered_packages = packages.dup
      filtered_packages[unsolved[:name]] = packages[unsolved[:name]].select { |pkg| Tpkg::package_meets_requirement?(pkg, unsolved) }
    end
    
    # If there are no possible packages left return an indication that we
    # didn't find a solution
    if filtered_packages[unsolved[:name]].empty?
      return nil
    end
    
    # Mark the req as solved, loop over the remaining possible packages,
    # pick each one, extract dependency requirements for that particular
    # package, and recurse to test if that particular package works
    # as part of a complete solution
    solutions = []
    unsolved[:solved] = true
    possible_packages = filtered_packages[unsolved[:name]]
    possible_packages.each do |pkg|
      filtered_packages[unsolved[:name]] = [pkg]
      updated_requirements = requirements.dup
      updated_requirements.concat(Tpkg::extract_reqs_from_metadata(pkg[:metadata]))
      solution = solve_dependencies(updated_requirements.dup, filtered_packages.dup)
      if solution
        solutions.concat(solution)
      end
    end
    unsolved[:solved] = false
    
    # Return any solutions we found
    solutions
  end
  
  def download(source, path)
    http = Tpkg::gethttp(URI.parse(source))
    localpath = File.join(source_to_local_path(source), File.basename(path))
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
    Tpkg::verify_package_checksum(tmpfile.path)
    File.rename(tmpfile.path, localpath)
    localpath
  end
  
  # Given a package's metadata return a hash of init scripts in the
  # package and where they need to be linked to on the system
  def init_links(metadata)
    links = {}
    metadata.elements.each('/tpkg/files/file') do |tpkgfile|
      if tpkgfile.elements['init']
        tpkg_path = tpkgfile.elements['path'].text
        installed_path = nil
        if tpkg_path[0,1] == File::SEPARATOR
          installed_path = File.join(@file_system_root, tpkg_path)
        else
          installed_path = File.join(@base, tpkg_path)
        end
        
        # SysV-style init
        if Tpkg::get_os =~ /RedHat|CentOS/ ||
           Tpkg::get_os =~ /Debian/ ||
           Tpkg::get_os =~ /Solaris/
          start = '99'
          if tpkgfile.elements['init/start']
            start = tpkgfile.elements['init/start'].text
          end
          levels = nil
          if Tpkg::get_os =~ /RedHat|CentOS/ ||
             Tpkg::get_os =~ /Debian/
            levels = ['2', '3', '4', '5']
          elsif Tpkg::get_os =~ /Solaris/
            levels = ['2', '3']
          end
          if tpkgfile.elements['init/levels']
            levels = tpkgfile.elements['init/levels'].text.split(//)
          end
          init_directory = nil
          if Tpkg::get_os =~ /RedHat|CentOS/
            init_directory = File.join(@file_system_root, 'etc', 'rc.d')
          elsif Tpkg::get_os =~ /Debian/ ||
                Tpkg::get_os =~ /Solaris/
            init_directory = File.join(@file_system_root, 'etc')
          end
          levels.each do |level|
            links[File.join(init_directory, "rc#{level}.d", 'S' + start + File.basename(installed_path))] = installed_path
          end
        elsif Tpkg::get_os =~ /FreeBSD/
          init_directory = File.join(@file_system_root, 'usr', 'local', 'etc', 'rc.d') 
          links[File.join(init_directory, File.basename(installed_path))] = installed_path
        else
          raise "No init script support for #{Tpkg::get_os}"
        end
      end
    end
    links
  end
  
  # Given a package's metadata return a hash of crontabs in the
  # package and where they need to be installed on the system
  def crontab_destinations(metadata)
    destinations = {}
    metadata.elements.each('/tpkg/files/file') do |tpkgfile|
      if tpkgfile.elements['crontab']
        tpkg_path = tpkgfile.elements['path'].text
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
          if tpkgfile.elements['crontab/user']
            user = tpkgfile.elements['crontab/user'].text
            if Tpkg::get_os =~ /FreeBSD/
              destinations[installed_path][:file] = File.join(@file_system_root, 'var', 'cron', 'tabs', user)
            elsif Tpkg::get_os =~ /Solaris/
              destinations[installed_path][:file] = File.join(@file_system_root, 'var', 'spool', 'cron', 'crontabs', user)
            elsif Tpkg::get_os =~ /Darwin/
              destinations[installed_path][:file] = File.join(@file_system_root, 'usr', 'lib', 'cron', 'tabs', user)
            end
          else
            raise "No user specified for crontab in #{metadata.root.attributes['filename']}"
          end
        # Systems that support cron.d style
        elsif Tpkg::get_os =~ /RedHat|CentOS/ ||
              Tpkg::get_os =~ /Debian/
          # If a user is specified go the per-user route
          if tpkgfile.elements['crontab/user']
            user = tpkgfile.elements['crontab/user'].text
            if Tpkg::get_os =~ /RedHat|CentOS/
              destinations[installed_path][:file] = File.join(@file_system_root, 'var', 'spool', 'cron', user)
            elsif Tpkg::get_os =~ /Debian/
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
  
  # Unpack the files from a package into place, decrypt as necessary, set
  # permissions and ownership, etc.  Does not check for conflicting
  # files or packages, etc.  Those checks (if desired) must be done before
  # calling this method.
  def unpack(package_file, passphrase=nil)
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
 
    # Since we're stuck with unpacking to a temporary folder take
    # advantage of that to handle permissions, ownership and decryption
    # tasks before moving the files into their final location.
    metadata = Tpkg::metadata_from_package(package_file)
    
    # Handle any default permissions and ownership
    if metadata.elements['/tpkg/files/file_defaults']
      if metadata.elements['/tpkg/files/file_defaults/posix']
        if metadata.elements['/tpkg/files/file_defaults/posix/owner'] ||
           metadata.elements['/tpkg/files/file_defaults/posix/group'] ||
           metadata.elements['/tpkg/files/file_defaults/posix/perms']
           
          uid = nil
          if metadata.elements['/tpkg/files/file_defaults/posix/owner']
            owner = metadata.elements['/tpkg/files/file_defaults/posix/owner'].text
            uid = Tpkg::lookup_uid(owner)
          end
          gid = nil
          if metadata.elements['/tpkg/files/file_defaults/posix/group']
            group = metadata.elements['/tpkg/files/file_defaults/posix/group'].text
            gid = Tpkg::lookup_gid(group)
          end
          perms = nil
          if metadata.elements['/tpkg/files/file_defaults/posix/perms']
            perms = metadata.elements['/tpkg/files/file_defaults/posix/perms'].text.oct
          end

          Find.find(root_dir, reloc_dir) do |f|
            # If the package doesn't contain either of the top level
            # directory we need to skip them, find will pass them to us
            # even if they don't exist.
            next if !File.exist?(f)

            if uid || gid
              begin
                File.chown(uid, gid, f)
              rescue Errno::EPERM
                raise if Process.euid == 0
              end
            end
            # The XML syntax currently only takes one set of permissions, so
            # we only apply those to files.  If folks want to set directory
            # permissions as well we'd have to expand the XML syntax to
            # support a seperate directory permissions field, or get fancier
            # with letting the user specify a umask or something.
            if perms && File.file?(f) && !File.symlink?(f)
              File.chmod(perms, f)
            #  posix["perms"] = File.stat(f).mode.to_s(8)
            else
            #  posix["perms"] = ""
            end
          end
        end
      elsif metadata.elements['/tpkg/files/file_defaults/posix_acl']
        raise "FIXME posix_acl defaults"
      elsif metadata.elements['/tpkg/files/file_defaults/windows_acl']
        raise "FIXME windows_acl defaults"
      end
    end
    # Handle any decryption and ownership/permissions on specific files
    metadata.elements.each('/tpkg/files/file') do |tpkgfile|
      tpkg_path = tpkgfile.elements['path'].text
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
      if tpkgfile.elements['posix']
        if tpkgfile.elements['posix/owner'] || tpkgfile.elements['posix/group']
          uid = nil
          if tpkgfile.elements['posix/owner']
            owner = tpkgfile.elements['posix/owner'].text
            uid = Tpkg::lookup_uid(owner)
          end
          gid = nil
          if tpkgfile.elements['posix/group']
            group = tpkgfile.elements['posix/group'].text
            gid = Tpkg::lookup_gid(group)
          end
          begin
            File.chown(uid, gid, working_path)
          rescue Errno::EPERM
            raise if Process.euid == 0
          end
        end
        if tpkgfile.elements['posix/perms']
          perms = tpkgfile.elements['posix/perms'].text.oct
          File.chmod(perms, working_path)
        end
      elsif tpkgfile.elements['posix_acl']
        raise "FIXME posix_acl"
      elsif tpkgfile.elements['windows_acl']
        raise "FIXME windows_acl"
      end
      
      # Decrypt any files marked for decryption
      if tpkgfile.elements['encrypt']
        if passphrase.nil?
          # If the user didn't supply a passphrase then just remove the
          # encrypted file.  This allows users to install packages that
          # contain encrypted files for which they don't have the
          # passphrase.  They end up with just the non-encrypted files,
          # potentially useful for development or QA environments.
          File.delete(working_path)
        else
          Tpkg::decrypt(metadata.elements['/tpkg/name'].text, working_path, passphrase)
          #digest = Digest::SHA256.file(working_path).hexdigest
          digest = Digest::SHA256.hexdigest(File.read(working_path))
          # get checksum for the decrypted file. Will be used for creating file_metadata.xml
          checksums_of_decrypted_files[tpkg_path] = digest 
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

    # pre/postinstall scripts might need to adjust things for relocatable
    # packages based on the base directory.  Set $TPKG_HOME so those
    # scripts know what base directory is being used.
    ENV['TPKG_HOME'] = @base
    
    # Run preinstall script
    if File.exist?(File.join(workdir, 'tpkg', 'preinstall'))
      # Warn the user about non-executable files, as system will just
      # silently fail and exit if that's the case.
      if !File.executable?(File.join(workdir, 'tpkg', 'preinstall'))
        warn "Warning: preinstall script for #{File.basename(package_file)} is not executable, execution will likely fail"
      end
      system(File.join(workdir, 'tpkg', 'preinstall')) || abort("Error: preinstall for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
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
          (1..9).to_a.each do |i|
            begin
              File.symlink(init_script, link + i.to_s)
              break
            rescue Errno::EEXIST
            end
            # If we get here (i.e. we never reached the break) then we
            # failed to create any of the possible link names.
            raise "Failed to install init script for #{File.basename(package_file)}"
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
            (1..9).to_a.each do |i|
              begin
                File.symlink(crontab, destination[:link] + i.to_s)
                break
              rescue Errno::EEXIST
              end
              # If we get here (i.e. we never reached the break) then we
              # failed to create any of the possible link names.
              raise "Failed to install crontab for #{File.basename(package_file)}"
            end
          end
        elsif destination[:file]
          if !File.exist?(File.dirname(destination[:file]))
            FileUtils.mkdir_p(File.dirname(destination[:file]))
          end
          tmpfile = Tempfile.new(File.basename(destination[:file]), File.dirname(destination[:file]))
          # Insert the contents of the current crontab file
          if File.exist?(destination[:file])
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
          # FIXME: On Solaris we should bounce cron, otherwise it won't
          # pick up the changes
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
    metadata.write(metadata_file)
    metadata_file.close    
    # Save file_metadata.xml for this pkg
    file_metadata = File.join(workdir, 'tpkg', 'file_metadata.xml') 
    if !File.exist?(file_metadata)
      warn "Warning: package does not include file_metadata.xml"
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
        digest = checksums_of_decrypted_files[file_ele.elements["path"].text]
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
  
  # Adds/modifies requirements and packages arguments to add requirements
  # and package entries for currently installed packages
  # Note: the requirements and packages arguments are modified by this method
  def requirements_for_currently_installed_packages(requirements, packages)
    metadata_for_installed_packages.each do |installed_xml|
      name = installed_xml.elements['/tpkg/name'].text
      version = installed_xml.elements['/tpkg/version'].text
      # For each currently installed package we insert a requirement for
      # at least that version of the package
      req = { :name => name, :minimum_version => version }
      requirements << req
      # Initialize the list of possible packages for this req
      if !packages[name]
        packages[name] = available_packages_that_meet_requirement(req)
      end
      # Insert an entry for the already installed package into the list of
      # possible packages
      packages[name] << { :metadata => installed_xml, :source => :currently_installed, :prefer => true }
    end
  end
  
  # Define requirements for requested packages
  # Takes an array of packages (files, URLs or basic package specs ('foo' or 'foo=1.0'))
  # Adds/modifies requirements and packages arguments based on parsing those requests
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
      if request =~ /^[\w=<>\d\.]+$/ && !File.file?(request)  # basic package specs ('foo' or 'foo=1.0')
        req = Tpkg::parse_request(request)
        newreqs << req
        # Initialize the list of possible packages for this req
        if !packages[req[:name]]
          packages[req[:name]] = available_packages_that_meet_requirement(req)
          if packages[req[:name]].empty?
            raise "Unable to find any packages which satisfy #{request}"
          end
        end
      else  # User specified a file or URI
        req = {}
        metadata = nil
        source = nil
        if File.file?(request)
          metadata = Tpkg::metadata_from_package(request)
          source = request
        else
          uri = URI.parse(request)  # This just serves as a sanity check
          # Using these File methods on a URI seems to work but is probably fragile
          source = File.dirname(request)
          pkgfile = File.basename(request)
          localpath = download(source, pkgfile)
          metadata = Tpkg::metadata_from_package(localpath)
        end
        req[:name] = metadata.elements['/tpkg/name'].text
        newreqs << req
        # The user specified a particular package, so it is the only package
        # that can be used to meet the requirement
        packages[req[:name]] = [{ :metadata => metadata, :source => source }]
      end
    end
    
    requirements.concat(newreqs)
    newreqs
  end
  
  CHECK_INSTALL = 1
  CHECK_UPGRADE = 2
  CHECK_REMOVE  = 3
  def conflicting_files(package_file, mode=CHECK_INSTALL)
    metadata = Tpkg::metadata_from_package(package_file)
    pkgname = metadata.elements['/tpkg/name'].text
    
    conflicts = {}
    
    installed_files = files_for_installed_packages

    # Pull out the normalized paths, skipping appropriate packages based
    # on the requested mode
    installed_files_normalized = {}
    installed_files.each do |pkgfile, files|
      # Skip packages with the same name if the user is performing an upgrade
      if mode == CHECK_UPGRADE && files[:metadata].elements['/tpkg/name'].text == pkgname
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
  
  # See parse_requests for format of requests
  def install(requests, passphrase=nil)
    requirements = []
    packages = {}
    lock
    
    # FIXME: circular dependency detection
    requirements_for_currently_installed_packages(requirements, packages)
    parse_requests(requests, requirements, packages)
    
    solution_packages = best_solution(requirements.dup, packages.dup)
    if !solution_packages
      raise "Unable to resolve dependencies"
    end
   
    solution_packages.each do |pkg|
      if pkg[:source] == :currently_installed || pkg[:source] == :native_installed
        # Nothing to do for packages currently installed
      else
        if pkg[:source] != :native_available
          pkgfile = nil
          if File.exist?(pkg[:source])
            pkgfile = pkg[:source]
          else
            pkgfile = download(pkg[:source], pkg[:metadata].root.attributes['filename'])
          end
          if File.exist?(File.join(@installed_directory, File.basename(pkgfile)))
            warn "Skipping #{File.basename(pkgfile)}, already installed"
          else
            if prompt_for_conflicting_files(pkgfile)
              unpack(pkgfile, passphrase)
            end
          end
        else
          if Tpkg::get_os =~ /RedHat|CentOS/
            name = pkg[:metadata].elements['/tpkg/name'].text
            version = pkg[:metadata].elements['/tpkg/version'].text
            package_version = pkg[:metadata].elements['/tpkg/package_version'].text
            # RPMs always have a release/package_version
            pkgname = "#{name}-#{version}-#{package_version}"
            puts "Running 'yum -y install #{pkgname}' to install native package" if @@debug
            system("yum -y install #{pkgname}")
          elsif Tpkg::get_os =~ /Debian/
            name = pkg[:metadata].elements['/tpkg/name'].text
            version = pkg[:metadata].elements['/tpkg/version'].text
            pkgname = "#{name}-#{version}"
            if pkg[:metadata].elements['/tpkg/package_version']
              package_version = pkg[:metadata].elements['/tpkg/package_version'].text
              pkgname << "-#{package_version}"
            end
            puts "Running 'apt-get -y install #{pkgname}' to install native package" if @@debug
            system("apt-get -y install #{pkgname}")
          elsif Tpkg::get_os =~ /Solaris/
            name = pkg[:metadata].elements['/tpkg/name'].text
            version = pkg[:metadata].elements['/tpkg/version'].text
            pkgname = "#{name}-#{version}"
            if pkg[:metadata].elements['/tpkg/package_version']
              package_version = pkg[:metadata].elements['/tpkg/package_version'].text
              pkgname << ",REV=#{package_version}"
            end
            if File.exist?('/opt/csw/bin/pkg-get')
              puts "Running '/opt/csw/bin/pkg-get -i #{pkgname}' to install native package" if @@debug
              system("/opt/csw/bin/pkg-get -i #{pkgname}")
            else
              raise "No native package installation tool available"
            end
          elsif Tpkg::get_os =~ /FreeBSD/
            name = pkg[:metadata].elements['/tpkg/name'].text
            version = pkg[:metadata].elements['/tpkg/version'].text
            pkgname = "#{name}-#{version}"
            if pkg[:metadata].elements['/tpkg/package_version']
              package_version = pkg[:metadata].elements['/tpkg/package_version'].text
              pkgname << "_#{package_version}"
            end
            puts "Running 'pkg_add -r #{pkgname}' to install native package" if @@debug
            system("pkg_add -r #{pkgname}")
          else
            raise "No native package installation support for #{Tpkg::get_os}"
          end
        end
      end
    end

    send_update_to_server unless @report_server.nil?
    unlock
  end

  def upgrade(requests=nil, passphrase=nil)
    requirements = []
    packages = {}
    
    # If the user specified some specific packages to upgrade in requests
    # then we look for upgrades for just those packages (and any necessary
    # dependency upgrades).  If the user did not specify specific packages
    # then we look for upgrades for all currently installed packages.
    
    lock
    
    # FIXME: circular dependency detection
    requirements_for_currently_installed_packages(requirements, packages)
    newreqs = nil
    if requests
      newreqs = parse_requests(requests, requirements, packages)
    end
    
    if !newreqs
      # Remove preference for currently installed package in all cases
      packages.each do |name, pkgs|
        pkgs.each do |pkg|
          if pkg[:source] == :currently_installed
            pkg[:prefer] = false
          end
        end
      end
    else
      # Remove preference for currently installed package for just the
      # packages we've been asked to upgrade
      newreqs.each do |newreq|
        packages[newreq[:name]].each do |pkg|
          if pkg[:source] == :currently_installed
            pkg[:prefer] = false
          end
        end
      end
    end
    
    solution_packages = best_solution(requirements.dup, packages.dup)
    installed_files = files_for_installed_packages
    solution_packages.each do |pkg|
      if pkg[:source] == :currently_installed || pkg[:source] == :native_installed
        # Nothing to do for packages currently installed
      elsif pkg[:source] != :native_available
        pkgfile = nil
        if File.exist?(pkg[:source])
          pkgfile = pkg[:source]
        else
          pkgfile = download(pkg[:source], pkg[:metadata].root.attributes['filename'])
        end
        if prompt_for_conflicting_files(pkgfile, CHECK_UPGRADE)
          metadata = Tpkg::metadata_from_package(pkgfile)
          remove([metadata.elements['/tpkg/name'].text], :upgrade => true)
          unpack(pkgfile, passphrase)
        end
      else  # pkg[:source] == :native_available
        if Tpkg::get_os =~ /RedHat|CentOS/
          name = pkg[:metadata].elements['/tpkg/name'].text
          version = pkg[:metadata].elements['/tpkg/version'].text
          package_version = pkg[:metadata].elements['/tpkg/package_version'].text
          # RPMs always have a release/package_version
          pkgname = "#{name}-#{version}-#{package_version}"
          puts "Running 'yum -y update #{pkgname}' to upgrade native package" if @@debug
          system("yum -y update #{pkgname}")
        elsif Tpkg::get_os =~ /Debian/
          name = pkg[:metadata].elements['/tpkg/name'].text
          version = pkg[:metadata].elements['/tpkg/version'].text
          pkgname = "#{name}-#{version}"
          if pkg[:metadata].elements['/tpkg/package_version']
            package_version = pkg[:metadata].elements['/tpkg/package_version'].text
            pkgname << "-#{package_version}"
          end
          puts "Running 'apt-get -y upgrade #{pkgname}' to upgrade native package" if @@debug
          system("apt-get -y upgrade #{pkgname}")
        elsif Tpkg::get_os =~ /Solaris/
          name = pkg[:metadata].elements['/tpkg/name'].text
          version = pkg[:metadata].elements['/tpkg/version'].text
          pkgname = "#{name}-#{version}"
          if pkg[:metadata].elements['/tpkg/package_version']
            package_version = pkg[:metadata].elements['/tpkg/package_version'].text
            pkgname << ",REV=#{package_version}"
          end
          if File.exist?('/opt/csw/bin/pkg-get')
            puts "Running '/opt/csw/bin/pkg-get -u #{pkgname}' to upgrade native package" if @@debug
            system("/opt/csw/bin/pkg-get -u #{pkgname}")
          else
            raise "No native package upgrade tool available"
          end
        elsif Tpkg::get_os =~ /FreeBSD/
          name = pkg[:metadata].elements['/tpkg/name'].text
          version = pkg[:metadata].elements['/tpkg/version'].text
          pkgname = "#{name}-#{version}"
          if pkg[:metadata].elements['/tpkg/package_version']
            package_version = pkg[:metadata].elements['/tpkg/package_version'].text
            pkgname << "_#{package_version}"
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
        else
          raise "No native package upgrade support for #{Tpkg::get_os}"
        end
      end
    end
    
    send_update_to_server unless @report_server.nil?
    unlock
  end
  
  def remove(requests, options={})
    lock
    
    packages_to_remove = []
    requests.each do |request|
      req = Tpkg::parse_request(request)
      packages_to_remove.concat(installed_packages_that_meet_requirement(req))
    end
    
    if packages_to_remove.empty?
      puts "No matching packages"
      return
    end
    
    # Check that this doesn't leave any dependencies unresolved
    if !options[:upgrade]
      pkg_files_to_remove = packages_to_remove.map { |pkg| pkg[:metadata].root.attributes['filename'] }
      metadata_for_installed_packages.each do |metadata|
        next if pkg_files_to_remove.include?(metadata.root.attributes['filename'])
        Tpkg::extract_reqs_from_metadata(metadata).each do |req|
          # We ignore native dependencies because there is no way a removal
          # can break a native dependency, we don't support removing native
          # packages.
          if !req[:native]
            if installed_packages_that_meet_requirement(req).all? { |pkg| pkg_files_to_remove.include?(pkg[:metadata].root.attributes['filename']) }
              raise "Package #{metadata.root.attributes['filename']} depends on #{req[:name]}"
            end
          end
        end
      end
    end
    
    # Confirm with the user
    if @@prompt
      puts "The following packages will be removed:"
      packages_to_remove.each do |pkg|
        puts pkg[:metadata].root.attributes['filename']
      end
      print "Confirm? [y/N] "
      response = $stdin.gets
      if response !~ /^y/i
        return
      end
    end
    
    # pre/postremove scripts might need to adjust things for relocatable
    # packages based on the base directory.  Set $TPKG_HOME so those
    # scripts know what base directory is being used.
    ENV['TPKG_HOME'] = @base
    
    # Remove the packages
    packages_to_remove.each do |pkg|
      pkgname = pkg[:metadata].elements['/tpkg/name'].text
      package_file = File.join(@installed_directory, pkg[:metadata].root.attributes['filename'])
      
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
        system(File.join(workdir, 'tpkg', 'preremove')) || abort("Error: preremove for #{File.basename(package_file)} failed with exit value #{$?.exitstatus}")
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
              # FIXME: On Solaris we should bounce cron, otherwise it won't
              # pick up the changes
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

  def deploy_install(package, abort_on_fail, max_worker, servers)
    deployer = Deployer.new
    deployer.deploy(package, false, max_worker, servers, "install")
  end

  def deploy_remove(package, abort_on_fail, max_worker, servers)
    deployer = Deployer.new
    deployer.deploy(package, false, max_worker, servers, "remove")
  end

  def deploy_upgrade(package, abort_on_fail, max_worker, servers)
    deployer = Deployer.new
    deployer.deploy(package, false, max_worker, servers, "upgrade")
  end

  def deploy_start(package, abort_on_fail, max_worker, servers)
    deployer = Deployer.new
    deployer.deploy(package, false, max_worker, servers, "start")
  end

  def deploy_stop(package, abort_on_fail, max_worker, servers)
    deployer = Deployer.new
    deployer.deploy(package, false, max_worker, servers, "stop")
  end

  def deploy_restart(package, abort_on_fail, max_worker, servers)
    deployer = Deployer.new
    deployer.deploy(package, false, max_worker, servers, "restart")
  end

  def verify_file_metadata(requests)
    results = {}
    packages = []
    # parse request to determine what packages the user wants to verify
    requests.each do |request|
      req = Tpkg::parse_request(request)
      packages.concat(installed_packages_that_meet_requirement(req).collect { |pkg| pkg[:metadata].root.attribute('filename').value })
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
    metadatas = installed_packages_that_meet_requirement(Tpkg::parse_request(requests)).collect { |pkg| pkg[:metadata] }
    metadatas.each do | metadata |
      init_links(metadata).each do |link, init_script|
        system("#{link} #{action}")
        break
      end 
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
      raise "tpkg repository locked by another process (with PID #{lockpid})"
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
     xml += metadata.root.to_s
    end
    xml += "</packages>"

    begin
      add_uri =  URI.parse("#{@report_server}/packages/client_update_xml/")
      http = Tpkg::gethttp(add_uri)
      request = {"xml"=>URI.escape(xml), "client"=>Facter['fqdn'].value}
      post = Net::HTTP::Post.new(add_uri.path)
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
end

