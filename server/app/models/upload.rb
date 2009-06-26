class Upload < ActiveRecord::Base
  has_attached_file :upload,
  :path => "/auto/tpkg/:basename.:extension"
  #:path => "/tmp/tpkg/:basename.:extension"
end
