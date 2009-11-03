require 'digest/sha2'    # Digest::SHA256#hexdigest, etc.
require 'ostruct'

##
# Hold meta data for a particular file
#
class FileMetadata
  attr_accessor :path, :gid, :uid, :perms, :checksum, :relocatable, :modified, :base, :file_system_root
  def initialize(options = {})
    @checksum = OpenStruct.new()
    @checksum.digest = []
    @base = options[:base]
    @file_system_root = options[:file_system_root]
    @gid = nil
    @uid = nil
    @perm= nil
  end

  def normalize_path
    if @relocatable && @base
      return File.join(base, @path)
    elsif @file_system_root
      return File.join(file_system_root, @path)
    else
      return @path
    end    
  end

  def to_s
    "path=#{path}, modified=#{modified}, reloctable=#{relocatable}, perms=#{perms}, checksum=#{checksum}"
  end

  # Write out file metadata as xml to the given file
  def to_xml(file)
    xml = "
  <file relocatable='#{relocatable}'>
    <path>#{path}</path>"

    if @checksum.algorithm
      xml = "#{xml}
    <checksum>
      <algorithm>#{@checksum.algorithm}</algorithm>"

      @checksum.digest.each do |digest|
        xml = "#{xml}
      <digest#{ if digest.encrypted; ' encrypted=\'true\'';end; if digest.decrypted; ' decrypted=\'true\'';end}>#{digest.value}</digest>"
      end
    end

    if @checksum.algorithm
      xml = "#{xml}
    </checksum>"      
    end

    xml = "#{xml}
    <uid>#{@uid}</uid><gid>#{@gid}</gid><perms>#{perms}</perms>
  </file> " 

    file.puts xml
  end

end

#
#  Hold array of file metadata for files that belong to a particular package
#
class FileMetadataWrapper
  attr_accessor :file_metadata, :package_file
  def initialize(package_file = nil)
    @package_file = package_file
    @file_metadata = []
  end

  # Write out file metadata as xml to the given file
  def to_xml(file)
    file.puts "<files package_file='#{@package_file}'>"

    @file_metadata.each do | f |  
      f.to_xml(file)
    end

    file.puts "</files>"
  end 
end

# Streaming parser class for parsing file metadata
class FileMetadataParser
  attr_accessor :result
  ROOT = "files"
  FILE_TAG_NAME = "file"
  DIGEST_TAG_NAME = "digest"
  ALGORITHM_TAG_NAME = "algorithm"
  PATH_TAG_NAME = "path"

  # options
  #   include => ["gid", "perms", "checksum"]
  #   include_files => list of files to extract file metadata for
  #   checksum - flag to tell parser to check expected chksum vs actual chksum & 
  #                    record if they match up or not
  #   base, file_system_root
  def initialize(options = {})
    @result = FileMetadataWrapper.new(options[:package_file])
    @current_file = nil
    @current_property = nil
    @options = options
    @options[:normalize_path] = @options[:normalize_path] || false
  end

  def tag_start( property, attributes )
    case property
      when ROOT
        @result.package_file ||= attributes["package_file"] 
      when FILE_TAG_NAME
        @current_file = FileMetadata.new(@options)
        @current_file.relocatable = attributes["relocatable"]
      when DIGEST_TAG_NAME
        @current_digest = OpenStruct.new()
        @current_digest.encrypted = attributes["encrypted"]
        @current_digest.decrypted = attributes["decrypted"]
        @current_property = property
      else
        @current_property = property
    end
  end

  def text( str )
    if @current_file && @current_property == ALGORITHM_TAG_NAME
      @current_file.checksum.algorithm = str
    elsif @current_file && @current_property == DIGEST_TAG_NAME
      @current_digest.value = str
      @current_file.checksum.digest << @current_digest
    elsif @current_file && @current_property == PATH_TAG_NAME
      @current_file.path = str

      # Don't include this file if it's not in the include option
      if !@options[:include_files].nil? && !@options[:include_files].include?(@current_file.normalize_path)
        @current_file = nil
      end
    elsif @current_file && @current_property && @current_property != "checksum"
      @current_file.send( @current_property.to_s + "=", str ) 
    end
  end

  def tag_end( property )
    if property == FILE_TAG_NAME && @current_file

      # verify checksum
      if @options[:checksum] && @current_file.path && File.file?(@current_file.normalize_path)
        chksum_actual = Digest::SHA256.hexdigest(File.read(@current_file.normalize_path))
        chksum_expected = nil
        chksum_expected_decrypted = nil

        if @current_file.checksum
          @current_file.checksum.digest.each do | digest |
             chksum_expected = digest.value
             chksum_expected_decrypted = digest.value if digest.decrypted
          end
          checksum_expected = chksum_expected_decrypted if chksum_expected_decrypted
        end

        if chksum_expected && chksum_expected != chksum_actual
          @current_file.modified = true
        end
      end 

      @result.file_metadata << @current_file
      @current_file = nil
    else
      @current_property = nil
    end
  end
end

#require 'rexml/document'
#parser = FileMetadataParser.new({:base => "/home/t", :file_system_root => "/", :checksum => true})
#parser = FileMetadataParser.new({:base => "/home/t", :file_system_root => "/", :include_files => ["/home/t/file"], :checksum => true})

#REXML::Document.parse_stream(File.new('file_metadata.xml'), parser )

#puts parser.result.to_xml
