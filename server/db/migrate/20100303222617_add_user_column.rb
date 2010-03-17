class AddUserColumn < ActiveRecord::Migration
  def self.up
    add_column :client_package_histories, :user, :string
    add_column :client_package_histories, :comment, :string
  end

  def self.down
    remove_column :client_package_histories, :user
    remove_column :client_package_histories, :comment
  end
end
