require 'rexml/document'

class ClientUpdateController < ApplicationController
  skip_before_filter :verify_authenticity_token


  def create
    # This is to support old client 
    if params[:xml] or params[:yml]
      return legacy_create(params)
    end

    removed = newly_installed = already_installed = []

    # parse the data sent from tpkg client
    client_name = params[:client]
    client = Client.find_or_create({"name"=>client_name})
    tpkg_home = params[:tpkg_home]
    user = params[:user] || "unknown"

    if params[:removed]
      removed =PkgUtils::pkgs_metadata_to_db_objects(URI.unescape(params[:removed]))
    end
    if params[:newly_installed]
      newly_installed =PkgUtils::pkgs_metadata_to_db_objects(URI.unescape(params[:newly_installed]))
    end
    if params[:already_installed]
      already_installed =PkgUtils::pkgs_metadata_to_db_objects(URI.unescape(params[:already_installed]))      
    end

    process_removed_pkgs(removed, client, {:user => user, :tpkg_home => tpkg_home})
    process_installed_pkgs(newly_installed, client, {:user => user, :tpkg_home => tpkg_home})

    currently_installed_pkgs = [] | already_installed | newly_installed
    prev_installed_packages = []
    client.client_packages.each do |client_package|
      prev_installed_packages << client_package.package if client_package.tpkg_home == tpkg_home
    end

    packages_to_be_removed = prev_installed_packages - currently_installed_pkgs
    process_removed_pkgs(packages_to_be_removed, client, {:tpkg_home => tpkg_home})

    new_packages = currently_installed_pkgs - prev_installed_packages
    process_installed_pkgs(new_packages, client, {:tpkg_home => tpkg_home})

    render :text => "OK"
  end

  # used by the clients to report back the list
  # of installed packages (in xml format)
  def legacy_create(params)
    client_name = params[:client]
    client = Client.find_or_create({"name"=>client_name})
   
    # parse the POST data and generate a list of packages installed
    # on this client
    if params[:yml]
      packages = PkgUtils::parse_yml_packages(URI.unescape(params[:yml]))
    else
      packages = PkgUtils::parse_xml_package(URI.unescape(params[:xml]))
    end

    # insert into DB if the packages are not there
    packages_id = Array.new
    packages.each do | package |
      packages_id << Package.find_or_create(package).id
    end

   
    prev_packages = client.client_packages
    prev_packages_id = Array.new
    prev_packages.each do | package |
      prev_packages_id << package.package_id
    end

    # remove uninstalled packages
    packages_to_be_removed = prev_packages_id - packages_id 
    packages_to_be_removed.each do |package_id|
       ClientPackage.delete_all(["client_id = ? AND package_id = ?", client.id, package_id])

       clientpackagehistory = ClientPackageHistory.new(:client_id => client.id, :package_id => package_id, :action => "REMOVED")
       clientpackagehistory.save!
    end

    # insert newly installed packages
    new_packages_id = packages_id - prev_packages_id
    new_packages_id.each do |package_id|
       clientpackage = ClientPackage.new(:client_id => client.id, :package_id => package_id)
       clientpackage.save!
 
       clientpackagehistory = ClientPackageHistory.new(:client_id => client.id, :package_id => package_id, :action => "INSTALLED")
       clientpackagehistory.save!
    end
   
    #puts "Here are the final result #{client.client_packages.inspect}"

    # update DB for client_packages
    render :text => "OK"
  end

  protected
  def process_removed_pkgs(pkgs, client, options={})
    user = options[:user] || "unknown"
    tpkg_home = options[:tpkg_home]
    comment = "TPKG_HOME=#{tpkg_home}"
    pkgs.each do |pkg|
      ClientPackage.delete_all(["client_id = ? AND package_id = ? AND tpkg_home = ?", client.id, pkg.id, tpkg_home])
      clientpackagehistory = ClientPackageHistory.new(:client_id => client.id, :package_id => pkg.id, 
                                                      :action => "REMOVED", :user => user, :comment => comment)
      clientpackagehistory.save!
    end
  end

  def process_installed_pkgs(pkgs, client, options={})
    user = options[:user] || "unknown"
    tpkg_home = options[:tpkg_home]
    comment = "TPKG_HOME=#{tpkg_home}"
    pkgs.each do |pkg|
      clientpackage = ClientPackage.new(:client_id => client.id, :package_id => pkg.id, :tpkg_home => tpkg_home)
      clientpackage.save!
      clientpackagehistory = ClientPackageHistory.new(:client_id => client.id, :package_id => pkg.id, 
                                                      :action => "INSTALLED", :user => user, :comment => comment)
      clientpackagehistory.save!
    end
  end
end
