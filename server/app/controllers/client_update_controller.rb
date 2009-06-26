require 'rexml/document'

class ClientUpdateController < ApplicationController
  skip_before_filter :verify_authenticity_token

  # used by the clients to report back the list
  # of installed packages (in xml format)
  def create
    client_name = params[:client]
    
    # parse the xml POST data and generate a list of packages installed
    # on this client
    packages = parse_xml_package(URI.unescape(params[:xml]))

    # insert into DB if the packages are not there
    packages_id = Array.new
    packages.each do | package |
      packages_id << Package.find_or_create(package).id
    end

    client = Client.find_or_create({"name"=>client_name})
   
    prev_packages = client.client_packages
    prev_packages_id = Array.new
    prev_packages.each do | package |
      prev_packages_id << package.package_id
    end

    # insert newly installed packages
    new_packages_id = packages_id - prev_packages_id
    new_packages_id.each do |package_id|
       clientpackage = ClientPackage.new(:client_id => client.id, :package_id => package_id)
       clientpackage.save!
    end
   
    # remove uninstalled packages
    packages_to_be_removed = prev_packages_id - packages_id 
    packages_to_be_removed.each do |package_id|
       ClientPackage.delete_all(["client_id = ? AND package_id = ?", client.id, package_id])
    end
    
    puts "Here are the final result #{client.client_packages.inspect}"

    # update DB for client_packages
    render :text => "OK"
  end

  protected
  def parse_xml_package(xml)
    puts xml
    packages = Array.new
    doc = REXML::Document.new(xml)
    doc.elements.each('packages/tpkg/') do |ele|
      package = Hash.new
      package["name"] = ele.elements["name"].text
      package["version"] = ele.elements["version"].text
      package["os"] = ele.elements["operatingsystem"].text if ele.elements["operatingsystem"]
      package["arch"] = ele.elements["architecture"].text if ele.elements["architecture"]
      package["maintainer"] = ele.elements["maintainer"].text 
      package["description"] = ele.elements["description"].text if ele.elements["description"]
      package["package_version"] = ele.elements["package_version"].text if ele.elements["package_version"]
      packages << package
    end
    return packages
  end
end
