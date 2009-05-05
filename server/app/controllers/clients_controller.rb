class ClientsController < ApplicationController

  # list out the clients
  def index
    @mainmodel = Client

    conditions_query = []
    conditions_values = []
    params.each_pair do |key, value|
      next if key == 'action'
      next if key == 'controller'
      next if key == 'format'
      next if key == 'page'
      next if key == 'sort'

      if key == @mainmodel.default_search_attribute
        conditions_query << "name LIKE ?"
        conditions_values << '%' + value + '%'
      end
    end

    if conditions_query.empty?
      @clients = Client.paginate(:all,
                                 #:include => includes,
                                 :page => params[:page])
    else
      conditions_string = conditions_query.join(' AND ')
      @clients = Client.paginate(:all,
                                 #:include => includes,
                                 :conditions => [ conditions_string, *conditions_values ],
                                 :page => params[:page])
    end

    respond_to do |format|
      format.html
      format.xml  { render :xml => @clients.to_xml(:dasherize => false) }
    end
  end

  def show
    @client = Client.find(params[:id])
    @installed_packages = @client.client_packages.collect{ |cp| cp.package}.flatten
    respond_to do |format|
      format.html 
      format.xml  { render :xml => @client.to_xml(:include => :client_packages, :dasherize => false) }
    end
  end
end
