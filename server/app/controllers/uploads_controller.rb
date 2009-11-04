require 'tpkg'

class UploadsController < ApplicationController
  before_filter :require_login, :except => :swfupload

  # FIXME: Pass sessions through to allow cross-site forgery protection
  protect_from_forgery :except => [:swfupload, :create]

  def index
    @uploads = Upload.paginate(:all, :page => params[:page], :order => "created_at DESC")
    respond_to do |format|
      format.html
      format.xml  { render :xml => @clients.to_xml(:dasherize => false) }
    end
  end

  def show
    @upload = Upload.find(params[:id])
  end

  def new
    @upload = Upload.new
  end

  def create
    # Standard, one-at-a-time, upload action
    @upload = Upload.new(params[:upload])
    @upload.uploader = current_user
    pkgfile = @upload.save!

    # Should do this in a separate thread
    process_uploaded_file(pkgfile)

    #redirect_to uploads_url
    render :text => "Success"
  rescue Exception => e
    render :text => "Failure: #{e}"
  end

  def swfupload
    # swfupload action set in routes.rb
    @upload = Upload.new(:upload => params[:Filedata])
    @upload.uploader = current_user
    pkgfile = @upload.save!

    # Should do this in a separate thread
    process_uploaded_file(pkgfile)

    # This returns the thumbnail url for handlers.js to use to display the thumbnail
    render :text => "Success"
  rescue Exception => e
    redirect_to :action => 'new'
  end

  def destroy
    @upload = Upload.find(params[:id])
    @upload.destroy
    redirect_to uploads_url
  end

  private
  def process_uploaded_file(pkgfile)
    begin
    xml = Tpkg::extract_tpkgxml(pkgfile)
    package = parse_xml_package(xml)[0]
    package['filename'] = File.basename(pkgfile)
    Package.find_or_create(package)
    rescue
      raise "Problem with parsing the package. This is most likely because the package is not of the right format"
    end
  end

  def parse_xml_package(xml, root="")
    #puts xml
    packages = Array.new
    doc = REXML::Document.new(xml)
    doc.elements.each("#{root}tpkg/") do |ele|
      package = Hash.new
      package["name"] = ele.elements["name"].text
      package["version"] = ele.elements["version"].text
      package["os"] = ele.elements["operatingsystem"].text if ele.elements["operatingsystem"]
      package["arch"] = ele.elements["architecture"].text if ele.elements["architecture"]
      package["maintainer"] = ele.elements["maintainer"].text
      package["description"] = ele.elements["description"].text if ele.elements["description"]
      package["package_version"] = ele.elements["package_version"].text if ele.elements["package_version"]
      package["filename"] = ele.attributes["filename"]
      packages << package
    end
    return packages
  end
end

