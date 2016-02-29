##############################################################################
# tpkg package management system
# License: MIT (http://www.opensource.org/licenses/mit-license.php)
##############################################################################

# We store this gem in our thirdparty directory. So we need to add it
# it to the search path
$:.unshift(File.join(File.dirname(__FILE__), 'thirdparty/kwalify-0.7.2/lib'))

# Exclude standard libraries and gems from the warnings induced by
# running ruby with the -w flag.  Several of these have warnings and
# there's nothing we can do to fix that.
require 'tpkg/silently'
Silently.silently do
  require 'yaml'           # YAML
  require 'rexml/document' # REXML::Document
  require 'kwalify'        # Kwalify, for validating yaml
end

# This class is taken from the ActiveSupport gem. 
# With yaml, keys are stored as string. But when we convert xml to hash, we store the key as
# symbol. To make it more convenient, we'll be subclassing our metadata hash with this class. 
# That way, we can access our metadata using either string or symbol as the key.
class HashWithAwesomeAccess < Hash
  def initialize(constructor = {})
    if constructor.is_a?(Hash)
      super()
      update(constructor)
    else
      super(constructor)
    end
  end
  
  def default(key = nil)
    if key.is_a?(Symbol) && include?(key = key.to_s)
      self[key]
    else
      super
    end
  end

  alias_method :regular_writer, :[]= unless method_defined?(:regular_writer)
  alias_method :regular_update, :update unless method_defined?(:regular_update)
    
  # Assigns a new value to the hash:
  #
  #   hash = HashWithAwesomeAccess.new
  #   hash[:key] = "value"
  #
  def []=(key, value)
    regular_writer(convert_key(key), convert_value(value))
  end
  
  # Updates the instantized hash with values from the second:
  # 
  #   hash_1 = HashWithAwesomeAccess.new
  #   hash_1[:key] = "value"
  # 
  #   hash_2 = HashWithAwesomeAccess.new
  #   hash_2[:key] = "New Value!"
  # 
  #   hash_1.update(hash_2) # => {"key"=>"New Value!"}
  # 
  def update(other_hash)
    other_hash.each_pair { |key, value| regular_writer(convert_key(key), convert_value(value)) }
    self
  end

  alias_method :merge!, :update

  # Checks the hash for a key matching the argument passed in:
  #
  #   hash = HashWithAwesomeAccess.new
  #   hash["key"] = "value"
  #   hash.key? :key  # => true
  #   hash.key? "key" # => true
  #
  def key?(key)
    super(convert_key(key))
  end

  alias_method :include?, :key?
  alias_method :has_key?, :key?
  alias_method :member?, :key?

  # Fetches the value for the specified key, same as doing hash[key]
  def fetch(key, *extras)
    super(convert_key(key), *extras)
  end

  # Returns an array of the values at the specified indices:
  #
  #   hash = HashWithAwesomeAccess.new
  #   hash[:a] = "x"
  #   hash[:b] = "y"
  #   hash.values_at("a", "b") # => ["x", "y"]
  #
  def values_at(*indices)
    indices.collect {|key| self[convert_key(key)]}
  end

  # Returns an exact copy of the hash.
  def dup
    HashWithAwesomeAccess.new(self)
  end

  # Merges the instantized and the specified hashes together, giving precedence to the values from the second hash
  # Does not overwrite the existing hash.
  def merge(hash)
    self.dup.update(hash)
  end

  # Removes a specified key from the hash.
  def delete(key)
    super(convert_key(key))
  end

  def stringify_keys!; self end
  def symbolize_keys!; self end
  def to_options!; self end

  # Convert to a Hash with String keys.
  def to_hash
    Hash.new(default).merge(self)
  end

  protected
    def convert_key(key)
      key.kind_of?(Symbol) ? key.to_s : key
    end

    def convert_value(value)
      case value
      when Hash
        value.with_awesome_access
      when Array
        value.collect { |e| e.is_a?(Hash) ? e.with_awesome_access : e }
      else
        value
      end
    end
end

module AwesomeAccess 
  def with_awesome_access
    hash = HashWithAwesomeAccess.new(self)
    hash.default = self.default
    hash
  end
end

# modules with some handy methods for dealing with hash. taken from
# ActiveSupport and Facets
module HashUtils
  # Return a new hash with all keys converted to strings.
  def stringify_keys
    inject({}) do |options, (key, value)|
      options[key.to_s] = value
      options
    end
  end

  # Return a new hash with all keys converted to symbols.
  def symbolize_keys
    inject({}) do |options, (key, value)|
      options[(key.to_sym rescue key) || key] = value
      options
    end
  end

  def recursively(&block)
    h = inject({}) do |hash, (key, value)|
      if value.is_a?(Hash)
        hash[key] = value.recursively(&block)
      elsif value.is_a?(Array)
        array = []
        value.each do |val|
          if val.is_a?(Hash)
            array << val.recursively(&block) 
          else
            array << val
          end
        end
        hash[key] = array
      else
        hash[key] = value
      end
      hash
    end
    yield h
  end

  def rekey(*args, &block)
    result = {}
    # for backward comptability (TODO: DEPRECATE).
    block = args.pop.to_sym.to_proc if args.size == 1
    # if no args use block.
    if args.empty?
      block = lambda{|k| k.to_sym} unless block
      keys.each do |k|
        nk = block[k]
        result[nk]=self[k] if nk
      end
    else
      raise ArgumentError, "3 for 2" if block
      to, from = *args
      result[to] = self[from]
    end
    result
  end
end

# Adding new capabilities to hash
class Hash
  include AwesomeAccess
  include HashUtils
end

# This is needed for backward compatibility
# We were using SymbolizeKeys rather than the HashWithAwesomeAccess
# class
module SymbolizeKeys 
  def self.extended(hash)
    hash.extend(HashWithAwesomeAccess)
  end
end

# This class is used for storing metadata of a package. The idea behind this class
# is that you can give it a metadata file of any format, such as yaml or xml,
# and it will provide you a uniform interface for accessing/dealing with the metadata.
class Metadata
  attr_reader :text, :format, :file
  attr_accessor :source
  REQUIRED_FIELDS = [:name, :version, :maintainer, :description]

  # Cleans up a string to make it suitable for use in a filename
  def self.clean_for_filename(dirtystring)
    dirtystring.downcase.gsub(/[^\w]/, '')
  end

  # Parse a file containing multiple package metadata documents (such as is
  # generated by Tpkg.extract_metadata) into a hash of Metadata objects
  def self.get_pkgs_metadata_from_yml_doc(yml_doc, metadata=nil, source=nil)
    metadata ||= {} 
    metadata_lists = yml_doc.split("---")
    metadata_lists.each do | metadata_text |
      if metadata_text =~ /^:?name:(.+)/
        name = $1.strip
        metadata[name] ||= []
        metadata[name] << Metadata.new(metadata_text,'yml', nil, source)
      end
    end
    return metadata
  end

  # Given the directory of an unpacked package, returns a Metadata
  # object. The metadata file can be in yml or xml format
  def self.instantiate_from_dir(dir)
    metadata = nil
    if File.exist?(File.join(dir, 'tpkg.yml'))
      metadata = Metadata.new(File.read(File.join(dir, 'tpkg.yml')),
                              'yml',
                              File.join(dir, 'tpkg.yml'))
    elsif File.exists?(File.join(dir, 'tpkg.xml'))
      metadata = Metadata.new(File.read(File.join(dir, 'tpkg.xml')),
                              'xml',
                              File.join(dir, 'tpkg.xml'))
    end
    return metadata
  end

  # text = text representation of the metadata
  # format = yml, xml, json, etc.
  # file = Path to the metadata file that was the source of this metadata
  # source = Source, in the tpkg sense, of the package described by this
  # metadata.  I.e. the filename of an individual package or a directory or
  # URL containing multiple packages and a metadata.yml file.  Used by tpkg to
  # report on how many packages are available from various sources.
  def initialize(text, format, file=nil, source=nil)
    @text = text
    # FIXME: should define enum of supported formats and reject others
    @format = format
    @file = file
    @source = source
    @hash = nil
  end

  def [](key)
    return to_hash[key]
  end

  def []=(key,value)
    to_hash[key]=value
  end
  
  def to_hash
    if @hash  
      return @hash 
    end
    
    if @format == 'yml'
      hash = YAML::load(@text)
      @hash = hash.with_awesome_access
      
      # We need this for backward compatibility. With xml, we specify
      # native dependency as type: :native rather then native: true
      @hash[:dependencies].each do | dep |
        if !dep[:type]
          if dep[:native]
            dep[:type] = :native
          else
            dep[:type] = :tpkg
          end
        end
      end if @hash[:dependencies]
      
      @hash[:files][:files].each do |file|
        # We need to do this for backward compatibility. In the old yml schema,
        # the encrypt field can either be "true" or a string value. Now, it is
        # a hash. We need to use a hash because we need to store info like the 
        # encryption algorithm.
        if file[:encrypt] && !file[:encrypt].is_a?(Hash)
          precrypt = true if file[:encrypt] == 'precrypt'
          file[:encrypt] = {:precrypt => precrypt}
        end
        # perms value are octal, but kwalify might treat it as decimal if it's something like 4550
        # the user might also use string instead of number
        if file[:posix] && file[:posix][:perms] && 
          (file[:posix][:perms].is_a?(String) or file[:posix][:perms] >= 1000)
          file[:posix][:perms] = "#{file[:posix][:perms]}".oct
        end
      end if @hash[:files] && @hash[:files][:files]
    elsif @format == 'xml'
      @hash = metadata_xml_to_hash.with_awesome_access
    else
      raise "Unknown metadata format"
    end
    @hash
  end
  
  # Write the metadata to a file under the specified directory
  # The file will be saved as tpkg.yml, even if originally loaded as XML.
  def write(dir)
    File.open(File.join(dir, "tpkg.yml"), "w") do |file|
      # When we convert xml to hash, we store the key as symbol. So when we
      # write back out to file, we should stringify all the keys for readability.
      data = to_hash.recursively{|h| h.stringify_keys }
      YAML::dump(data, file)
    end
  end
  
  # Add tpkg_version to the existing tpkg.xml or tpkg.yml file
  def add_tpkg_version(version)
    if self[:tpkg_version]
      if self[:tpkg_version] != version
        warn "Warning: tpkg_version is specified as #{self[:tpkg_version]}, which doesn't match with the actual tpkg version being used (#{version})."
      end
    else
      # Add to in-memory data
      self[:tpkg_version] = version
      # Update the metadata source file (if known)
      if @file
        if @format == 'yml'
          File.open(@file, 'a') do |file|
            file.puts "tpkg_version: #{version}"
          end 
        elsif @format == 'xml'
          metadata_xml = REXML::Document.new(@text)
          tpkg_version_ele = REXML::Element.new('tpkg_version')
          tpkg_version_ele.text = version
          metadata_xml.root.add_element(tpkg_version_ele)  
          File.open(@file, 'w') do |file|
            metadata_xml.write(file)
          end
        else
          raise "Unknown metadata format"
        end
      end
    end
  end
  
  def generate_package_filename
    name = to_hash[:name]
    version = to_hash[:version]
    packageversion = nil
    if to_hash[:package_version] && !to_hash[:package_version].to_s.empty?
      packageversion = to_hash[:package_version]
    end
    package_filename = "#{name}-#{version}"
    if packageversion
      package_filename << "-#{packageversion}"
    end


    if to_hash[:operatingsystem] and !to_hash[:operatingsystem].empty?
      if to_hash[:operatingsystem].length == 1
        package_filename << "-#{Metadata::clean_for_filename(to_hash[:operatingsystem].first)}"
      else
        operatingsystems = to_hash[:operatingsystem].dup
        # Genericize any equivalent operating systems
        # FIXME: more generic handling of equivalent OSs is probably called for
        operatingsystems.each do |os|
          os.sub!('CentOS', 'RedHat')
        end
        firstname = operatingsystems.first.split('-').first
        firstversion = operatingsystems.first.split('-').last
        if operatingsystems.all? { |os| os == operatingsystems.first }
          # After genericizing all OSs are the same
          package_filename << "-#{Metadata::clean_for_filename(operatingsystems.first)}"
        elsif operatingsystems.all? { |os| os =~ /#{firstname}-/ }
          # All of the OSs have the same name, just different versions.  It
          # may not be perfect, but name the package after the OS without a
          # version.  I.e. if the package specifies RedHat-4,RedHat-5 then
          # name it "redhat". It might be confusing when it won't install on
          # RedHat-3, but it seems better to me than naming it "multios".
          package_filename << "-#{Metadata::clean_for_filename(firstname)}"
        else
          package_filename << "-multios"
        end
      end
    end
    if to_hash[:architecture] and !to_hash[:architecture].empty?
      if to_hash[:architecture].length == 1
        package_filename << "-#{Metadata::clean_for_filename(to_hash[:architecture].first)}"
      else
        package_filename << "-multiarch"
      end
    end

    return package_filename
  end

  # Validate the metadata against the schema/dtd specified by the user
  # or use the default one in schema_dir
  # Return array of errors (if there are any)
  def validate(schema_dir)
    errors = []
    if @format == 'yml'
      if to_hash[:schema_file] 
        schema_file = File.join(schema_dir, to_hash[:schema_file]) 
      else
        schema_file = File.join(schema_dir, "schema.yml") 
      end
      unless File.exists?(schema_file)
        warn "Warning: unable to validate metadata because #{schema_file} does not exist"
        return
      end 
      errors = verify_yaml(schema_file, @text)
    elsif @format == 'xml'
      # TODO: use DTD to validate XML
      errors = verify_required_fields
    end

    # Verify version and package version begin with a digit
    if to_hash[:version].to_s !~ /^\d/
      errors << "Version must begins with a digit"
    end
    if to_hash[:package_version] && to_hash[:package_version].to_s !~ /^\d/
      errors << "Package version must begins with a digit"
    end
    errors
  end

  # Verify the yaml text against the given schema
  # Return array of errors (if there are any)
  def verify_yaml(schema, yaml_text)
    errors = nil
    # Kwalify generates lots of warnings, silence it
    Silently.silently do
      schema = Kwalify::Yaml.load_file(schema)
      validator = Kwalify::Validator.new(schema.with_awesome_access)
      errors = validator.validate(YAML::load(yaml_text).with_awesome_access)
    end
    errors
  end

  # Once we implement validating the XML using the DTD, we won't need
  # this method anymore
  def verify_required_fields
    errors = []
    REQUIRED_FIELDS.each do |reqfield|
      if to_hash[reqfield].nil?
        errors << "Required field #{reqfield} not found"
      elsif to_hash[reqfield].to_s.empty?
        errors << "Required field #{reqfield} is empty"
      end
    end
    errors
  end

  def metadata_xml_to_hash
    # Don't do anything if metadata is not from xml file
    return if @format != "xml"

    metadata_hash = {}
    metadata_xml = REXML::Document.new(@text)

    if metadata_xml.root.attributes['filename'] # && !metadata_xml.root.attributes['filename'].empty?
      metadata_hash[:filename] = metadata_xml.root.attributes['filename'] 
    end

    REQUIRED_FIELDS.each do |reqfield|
      if metadata_xml.elements["/tpkg/#{reqfield}"]
        metadata_hash[reqfield] = metadata_xml.elements["/tpkg/#{reqfield}"].text 
      end
    end

    [:tpkg_version, :package_version, :description, :bugreporting].each do |optfield|
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
      metadata_hash[arrayfield] = array unless array.empty?
    end

    deps = []
    metadata_xml.elements.each('/tpkg/dependencies/dependency') do |depxml|
      dep = {}
      dep[:name] = depxml.elements['name'].text
      [:allowed_versions, :minimum_version, :maximum_version,
       :minimum_package_version, :maximum_package_version].each do |depfield|
        if depxml.elements[depfield.to_s]
          dep[depfield] = depxml.elements[depfield.to_s].text
        end
      end
      if depxml.elements['native']
        dep[:type] = :native
      else
        dep[:type] = :tpkg
      end
      deps << dep
    end
    metadata_hash[:dependencies] = deps unless deps.empty?
    
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
      else
        conflict[:type] = :tpkg
      end
      conflicts << conflict
    end
    metadata_hash[:conflicts] = conflicts unless conflicts.empty?

    externals = []
    metadata_xml.elements.each('/tpkg/externals/external') do |extxml|
      external = {}
      external[:name] = extxml.elements['name'].text
      if extxml.elements['data']
        # The data element requires special handling.  We want to capture its
        # raw contents, which may be XML.  The "text" method we use for other
        # fields only returns text outside of child XML elements.  That fine
        # for other fields which we don't expect to contain any child
        # elements.  But here there may well be child elements and we need to
        # capture the raw data.
        # I.e. if we have:
        # <data>
        #   <one>Some text</one>
        #   <two>Other text</two>
        # </data>
        # We want to capture:
        # "\n  <one>Some text</one>\n  <two>Other text</two>\n"
        external[:data] = extxml.elements['data'].children.join('')
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
    metadata_hash[:externals] = externals unless externals.empty?

    metadata_hash[:files] = {}
    file_defaults = {}
    if metadata_xml.elements['/tpkg/files/file_defaults/posix']
      posix = {}
      if metadata_xml.elements['/tpkg/files/file_defaults/posix/owner']
        owner =
          metadata_xml.elements['/tpkg/files/file_defaults/posix/owner'].text
        posix[:owner] = owner

      end
      gid = nil
      if metadata_xml.elements['/tpkg/files/file_defaults/posix/group']
        group =
          metadata_xml.elements['/tpkg/files/file_defaults/posix/group'].text
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
    metadata_hash[:files][:file_defaults] = file_defaults unless file_defaults.empty?

    dir_defaults = {}
    if metadata_xml.elements['/tpkg/files/dir_defaults/posix']
      posix = {}
      if metadata_xml.elements['/tpkg/files/dir_defaults/posix/owner']
        owner =
          metadata_xml.elements['/tpkg/files/dir_defaults/posix/owner'].text
        posix[:owner] = owner
      end
      gid = nil
      if metadata_xml.elements['/tpkg/files/dir_defaults/posix/group']
        group =
          metadata_xml.elements['/tpkg/files/dir_defaults/posix/group'].text
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
    metadata_hash[:files][:dir_defaults] = dir_defaults unless dir_defaults.empty?

    files = []
    metadata_xml.elements.each('/tpkg/files/file') do |filexml|
      file = {}
      file[:path] = filexml.elements['path'].text
      file[:config] = true if filexml.elements['config']
      if filexml.elements['encrypt']
        encrypt = {}
        if filexml.elements['encrypt'].attribute('precrypt') &&
           filexml.elements['encrypt'].attribute('precrypt').value == 'true'
          encrypt['precrypt'] = true
        end
        if filexml.elements['encrypt'].attribute('algorithm')
          encrypt['algorithm'] = filexml.elements['encrypt'].attribute('algorithm').value
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
          posix[:owner] = owner
        end
        gid = nil
        if filexml.elements['posix/group']
          group = filexml.elements['posix/group'].text
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
    metadata_hash[:files][:files] = files unless files.empty?

    return metadata_hash
  end
  
  def get_native_deps
    native_deps = []
    if self[:dependencies]
      native_deps = self[:dependencies].select{|dep| dep[:type] == :native}
    end
    native_deps
  end
end

class FileMetadata < Metadata
  # Given the directory from which the file_metadata is saved, returns a FileMetadata
  # object. The file_metadata file can be in binary, yaml or xml.
  def self.instantiate_from_dir(dir)
    file_metadata = nil
    if File.exist?(File.join(dir, 'file_metadata.bin'))
      file_metadata = FileMetadata.new(File.read(File.join(dir, 'file_metadata.bin')), 'bin')
    elsif File.exist?(File.join(dir, 'file_metadata.yml'))
      file_metadata = FileMetadata.new(File.read(File.join(dir, 'file_metadata.yml')), 'yml')
    elsif File.exists?(File.join(dir, 'file_metadata.xml'))
      file_metadata = FileMetadata.new(File.read(File.join(dir, 'file_metadata.xml')), 'xml')
    end
    return file_metadata
  end

  def to_hash
    if @hash
      return @hash
    end

    if @format == 'bin'
      hash = Marshal::load(@text)
      @hash = hash.with_awesome_access
    elsif @format == 'yml'
      hash = YAML::load(@text)
      @hash = hash.with_awesome_access
    elsif @format == 'xml'
      @hash = file_metadata_xml_to_hash
    end
    return @hash
  end

  def file_metadata_xml_to_hash
    return if @format != "xml"

    file_metadata_hash = {}
    files = []
    file_metadata_xml = REXML::Document.new(@text)
    file_metadata_hash[:package_file] = file_metadata_xml.root.attributes['package_file']
    file_metadata_xml.elements.each("files/file") do | file_ele |
      file = {}
      file[:path] = file_ele.elements['path'].text
      file[:relocatable] = file_ele.attributes["relocatable"] == "true"

      if file_ele.elements["checksum"]
        digests = []
        file_ele.elements.each("checksum/digest") do | digest_ele |
          digest = {}
          digest['value'] = digest_ele.text
          digest['encrypted'] = digest_ele.attributes['encrypted'] && digest_ele.attributes['encrypted'] == "true"
          digest['decrypted'] = digest_ele.attributes['decrypted'] && digest_ele.attributes['decrypted'] == "true"
          digests << digest
        end
        checksum = {:digests => digests, :algorithm => file_ele.elements["checksum"].elements["algorithm"]}
      end
      file[:checksum] = checksum
      files << file
    end
    file_metadata_hash[:files] = files
    return file_metadata_hash
  end
end
