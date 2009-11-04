class CreateClientPackageHistories < ActiveRecord::Migration
  def self.up
    create_table :client_package_histories do |t|
      t.integer "client_id",    :null => false
      t.integer "package_id",   :null => false
      t.string "action",        :null => false
      t.timestamps
    end
  end

  def self.down
    drop_table :client_package_histories
  end
end
