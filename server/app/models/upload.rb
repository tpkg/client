begin
  require 'tpkg'
rescue LoadError
  # This is for when user don't have
  # tpkg client or tpkg library installed
end

class Upload < ActiveRecord::Base
  has_attached_file :upload, :path => "#{AppConfig.upload_path}:basename.:extension"

  before_post_process  :pre_process

  def pre_process
    if AppConfig.verify_upload
      unless defined? Tpkg::metadata_from_package
        raise "Unable to verify package because tpkg client/lib is not installed on the server."
      end
      # Need to do a rough validation for the uploaded file
      begin
        metadata = Tpkg::metadata_from_package(upload.queued_for_write[:original].path)
        if metadata[:name].nil?
          raise "Unable to extract metadata from the package. Most likely your package is not of the correct format, or it has been corrupted during the upload process."
        end
      rescue
        raise "Unable to extract metadata from the package. Most likely your package is not of the correct format, or it has been corrupted during the upload process."
      end
    else
      return true
    end
  end

  def save!
    if File.exists?(File.join(AppConfig.upload_path, upload_file_name))
      raise "File already exists."
    else
      super
    end
    return File.join(AppConfig.upload_path, upload_file_name)
  end
end
