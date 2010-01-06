class UploadsController < ApplicationController
  before_filter :login_required, :except => :swfupload

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
    @upload.uploader = session[:username]
    pkgfile = @upload.save!

    #redirect_to uploads_url
    render :text => "Success"
  rescue Exception => e
    render :text => "Failure: #{e}"
  end

  def swfupload
    # swfupload action set in routes.rb
    @upload = Upload.new(:upload => params[:Filedata])
    @upload.uploader = session[:username]
    pkgfile = @upload.save!

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
end

