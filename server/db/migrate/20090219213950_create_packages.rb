class CreatePackages < ActiveRecord::Migration
  def self.up
    create_table :packages do |t|
      t.string :name, :null => false
      t.string :version
      t.string :os
      t.string :arch
      t.string :package_version
      t.string :maintainer, :null => false
      t.text   :description
#      t.timestamps
    end
  end

  def self.down
    drop_table :packages
  end
end
