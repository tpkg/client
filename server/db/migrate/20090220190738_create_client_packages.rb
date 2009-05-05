class CreateClientPackages < ActiveRecord::Migration
  def self.up
    create_table :client_packages do |t|
      t.integer "client_id",    :null => false
      t.integer "package_id",   :null => false
#      t.timestamps
    end
  end

  def self.down
    drop_table :client_packages
  end
end
