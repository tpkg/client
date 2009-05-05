class Package < ActiveRecord::Base
  has_many :client_packages
  def self.default_search_attribute
    'name'
  end
end
