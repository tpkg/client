class AddTpkgHomeColumn < ActiveRecord::Migration
  def self.up
    add_column :client_packages, :tpkg_home, :string
  end

  def self.down
    drop_column :client_packages, :tpkg_home
  end
end
