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
    sort =  params[:sort]
    # If a sort was not defined we'll make one default
    if sort.nil?
      sort = 'name'
    end
    sort_by = sort.split("_")[0]
    sort_direction = sort.split("_")[1]

    system("echo #{sort} >> /tmp/ddaosort")

    @client = Client.find(params[:id])
    @installed_packages = @client.client_packages.collect{ |cp| cp.package}.flatten

    # sort the result
    @installed_packages.sort! do  |a,b|
      a.send(sort_by) != nil ? akey = a.send(sort_by) : akey = ""
      b.send(sort_by) != nil ? bkey = b.send(sort_by) : bkey = ""
      if sort_direction == "reverse"
        bkey <=> akey
      else
        akey <=> bkey
      end
    end

    respond_to do |format|
      format.html
      format.xml  { render :xml => @client.to_xml(:include => :client_packages, :dasherize => false) }
    end
  end
end
