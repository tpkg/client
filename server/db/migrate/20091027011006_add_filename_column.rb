class AddFilenameColumn < ActiveRecord::Migration
  def self.up
    add_column :packages, :filename, :string 
  end

  def self.down
    remove_column :packages, :filename
  end
end
