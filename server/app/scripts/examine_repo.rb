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
    puts "Looking at #{file}"
    metadata = Tpkg::metadata_from_package(File.join(AppConfig.upload_path, file))
    package = PkgUtils::metadata_to_db_package(metadata)
    package['filename'] = file
    Package.find_or_create(package)

    upload = Upload.new
    upload.upload_file_name = file
    upload.save
    upload.created_at = File.mtime(File.join(AppConfig.upload_path, file))
    upload.uploader = "unknown"
    upload.save
  end
end
