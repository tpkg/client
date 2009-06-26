class UploadsController < ApplicationController
  before_filter :require_login, :except => :swfupload

  # FIXME: Pass sessions through to allow cross-site forgery protection
  protect_from_forgery :except => [:swfupload, :create]

  def index
    @uploads = Upload.find_all_by_parent_id(nil)
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
    @upload.save!
    #redirect_to uploads_url
    render :text => "Success"
  rescue
    render :text => "Failure"
    #render :action => :new
  end

  def swfupload
    # swfupload action set in routes.rb
#    @upload = Upload.new :uploaded_data => params[:Filedata]
#    @upload.save!

    @upload = Upload.create(:upload => params[:Filedata])

    # This returns the thumbnail url for handlers.js to use to display the thumbnail
    render :text => "Success"
  rescue
    render :text => "Error"
  end

  def destroy
    @upload = Upload.find(params[:id])
    @upload.destroy
    redirect_to uploads_url
  end

end

