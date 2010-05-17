# This file is auto-generated from the current state of the database. Instead of editing this file, 
# please use the migrations feature of Active Record to incrementally modify your database, and
# then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your database schema. If you need
# to create the application database on another system, you should be using db:schema:load, not running
# all the migrations from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20100306004526) do

  create_table "client_package_histories", :force => true do |t|
    t.integer  "client_id",  :null => false
    t.integer  "package_id", :null => false
    t.string   "action",     :null => false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "user"
    t.string   "comment"
  end

  create_table "client_packages", :force => true do |t|
    t.integer "client_id",  :null => false
    t.integer "package_id", :null => false
    t.string  "tpkg_home"
  end

  create_table "clients", :force => true do |t|
    t.string "name", :null => false
  end

  create_table "packages", :force => true do |t|
    t.string "name",            :null => false
    t.string "version"
    t.string "os"
    t.string "arch"
    t.string "package_version"
    t.string "maintainer",      :null => false
    t.text   "description"
    t.string "filename"
  end

  create_table "uploads", :force => true do |t|
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "upload_file_name"
    t.string   "upload_content_type"
    t.integer  "upload_file_size"
    t.string   "uploader"
  end

  create_table "users", :force => true do |t|
    t.string   "login",                     :limit => 40
    t.string   "name",                      :limit => 100, :default => ""
    t.string   "email",                     :limit => 100
    t.string   "crypted_password",          :limit => 40
    t.string   "salt",                      :limit => 40
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "remember_token",            :limit => 40
    t.datetime "remember_token_expires_at"
    t.string   "activation_code",           :limit => 40
    t.datetime "activated_at"
    t.string   "state",                                    :default => "passive"
    t.datetime "deleted_at"
  end

  add_index "users", ["login"], :name => "index_users_on_login", :unique => true

end
