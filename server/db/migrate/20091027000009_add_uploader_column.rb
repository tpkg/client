class AddUploaderColumn < ActiveRecord::Migration
  def self.up
    add_column :uploads, :uploader, :string # Who uploaded the file
  end

  def self.down
    remove_column :uploads, :uploader
  end
end
