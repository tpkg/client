class ClientPackageHistory < ActiveRecord::Base
  belongs_to :package
  belongs_to :client
end
