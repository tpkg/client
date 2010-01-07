require 'tpkg'
require 'utils'

class ExamineRepo < ActiveRecord::Base
  present_files = []
  Dir.glob(File.join(AppConfig.upload_path, '*.tpkg')) do | file |
    present_files << File.basename(file)
  end
  existing_uploads = Upload.find(:all, :select => :upload_file_name).collect{ | upload | upload.upload_file_name}

  missing = present_files - existing_uploads

  missing.each do | file |
    xml = Tpkg::extract_tpkgxml(File.join(Upload::UPLOAD_PATH, file))      
    package = parse_xml_package(xml)[0]
    package['filename'] = file
    Package.find_or_create(package)
   
    upload = Upload.new 
    upload.upload_file_name = file
    upload.save
    upload.created_at = File.mtime(File.join(Upload::UPLOAD_PATH, file))
    puts "Looking at #{file} which has mtime of #{upload.created_at}"
    upload.uploader = "unknown"
    upload.save
  end
end
