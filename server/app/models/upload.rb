class Upload < ActiveRecord::Base
  UPLOAD_PATH="/auto/tpkg/"
  #UPLOAD_PATH="/tmp/tpkg/"
  has_attached_file :upload, :path => "#{UPLOAD_PATH}:basename.:extension"

  def save!
    if File.exists?(File.join(UPLOAD_PATH, upload_file_name))
      raise "File already exists."
    else
      super
    end
    return File.join(UPLOAD_PATH, upload_file_name)
  end
end
