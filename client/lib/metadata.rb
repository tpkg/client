require 'yaml'

module SymbolizeKeys

  # converts any current string keys to symbol keys 
  def self.extended(hash)
    hash.each do |key,value|
      if key.is_a?(String)
        hash.delete key
        hash[key] = value #through overridden []= 
      end
      if value.is_a?(Hash)
        hash[key]=value.extend(SymbolizeKeys)
      elsif value.is_a?(Array)
        value.each do |val|
          if val.is_a?(Hash)
            val.extend(SymbolizeKeys)
          end
        end
      end
    end
  end

  # assigns a new key/value pair 
  # converts they key to a symbol if it is a string 
  def []=(*args)
    args[0] = args[0].to_sym if args[0].is_a?(String)
    super
  end

  # returns new hash which is the merge of self and other hashes 
  # the returned hash will also be extended by SymbolizeKeys 
  def merge(*other_hashes , &resolution_proc )
    merged = Hash.new.extend SymbolizeKeys
    merged.merge! self , *other_hashes , &resolution_proc
  end

  # merges the other hashes into self 
  # if a proc is submitted , it's return will be the value for the key 
  def merge!( *other_hashes , &resolution_proc )

    # default resolution: value of the other hash 
    resolution_proc ||= proc{ |key,oldval,newval| newval }

    # merge each hash into self 
    other_hashes.each do |hash|
      hash.each{ |k,v|
        # assign new k/v into self, resolving conflicts with resolution_proc 
        self[k] = self.has_key?(k) ? resolution_proc[k,self[k],v] : v
      }
    end

    self
  end
end

class Metadata
  attr_accessor :source
  REQUIRED_FIELDS = [:name, :version, :maintainer]

  # Cleans up a string to make it suitable for use in a filename
  def self.clean_for_filename(dirtystring)
    dirtystring.downcase.gsub(/[^\w]/, '')
  end

  def self.get_pkgs_metadata_from_yml_doc(yml_doc, metadata=nil, source=nil)
    metadata = {} if metadata.nil?
    metadata_lists = yml_doc.split("---")
    metadata_lists.each do | metadata_text |
      if metadata_text =~ /^:?name:(.+)/
        name = $1.strip
        metadata[name] = [] if !metadata[name]
        metadata[name] << Metadata.new(metadata_text,'yml', source)
      end
    end
    return metadata
  end

  # metadata_text = text representation of the metadata
  # format = yml, xml, json, etc.
  def initialize(metadata_text, format, source=nil)
    @hash = nil
    @metadata_text = metadata_text
    @format = format
    @source = source
  end

  def [](key)
    return hash[key]
  end

  def []=(key,value)
    hash[key]=value
  end

  def hash
    if @hash  
      return @hash 
    end

    if @format == 'yml'
      hash = YAML::load(@metadata_text)
      @hash = hash.extend(SymbolizeKeys)
    else
      @hash = metadata_xml_to_hash
    end
    return @hash
  end

  def write(file)
    YAML::dump(hash, file)
  end

  def get_files_list
  end

  def generate_package_filename
    name = hash[:name]
    version = hash[:version]
    packageversion = nil
    if hash[:package_version] && !hash[:package_version].to_s.empty?
      packageversion = hash[:package_version]
    end
    package_filename = "#{name}-#{version}"
    if packageversion
      package_filename << "-#{packageversion}"
    end


    if hash[:operatingsystem] and !hash[:operatingsystem].empty?
      if hash[:operatingsystem].length == 1
        package_filename << "-#{Metadata::clean_for_filename(hash[:operatingsystem].first)}"
      else
        operatingsystems = hash[:operatingsystem].dup
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
    if hash[:architecture] and !hash[:architecture].empty?
      if hash[:architecture].length == 1
        package_filename << "-#{Metadata::clean_for_filename(hash[:architecture].first)}"
      else
        package_filename << "-multiarch"
      end
    end

    return package_filename
  end

  def verify_required_fields
    REQUIRED_FIELDS.each do |reqfield|
      if hash[reqfield].nil?
        raise "Required field #{reqfield} not found"
      elsif hash[reqfield].to_s.empty?
        raise "Required field #{reqfield} is empty"
      end
    end
  end

  def metadata_xml_to_hash
    # Don't do anything if metadata is from xml file
    return if @format != "xml"

    metadata_hash = {}
    metadata_xml = REXML::Document.new(@metadata_text)
    metadata_hash[:filename] = metadata_xml.root.attributes['filename']

    REQUIRED_FIELDS.each do |reqfield|
      if metadata_xml.elements["/tpkg/#{reqfield}"]
        metadata_hash[reqfield] = metadata_xml.elements["/tpkg/#{reqfield}"].text 
      end
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
      end
      conflicts << conflict
    end
    metadata_hash[:conflicts] = conflicts unless conflicts.empty?

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
      if filexml.elements['encrypt']
        encrypt = true
        if filexml.elements['encrypt'].attribute('precrypt') &&
           filexml.elements['encrypt'].attribute('precrypt').value == 'true'
          encrypt = "precrypt"
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
end

class FileMetadata < Metadata
  def hash
    if @hash
      return @hash
    end

    if @format == 'bin'
      @hash = Marshal::load(@metadata_text)
      @hash = hash.extend(SymbolizeKeys)
    elsif @format == 'yml'
      hash = YAML::load(@metadata_text)
      @hash = hash.extend(SymbolizeKeys)
    elsif @format == 'xml'
      @hash = file_metadata_xml_to_hash
    end
    return @hash
  end

  def file_metadata_xml_to_hash
    return if @format != "xml"

    file_metadata_hash = {}
    files = []
    file_metadata_xml = REXML::Document.new(@metadata_text)
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
