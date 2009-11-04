# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  include ExceptionNotifiable 
  helper :all # include all helpers, all the time

  # See ActionController::RequestForgeryProtection for details
  # Uncomment the :secret if you're not using the cookie session store
  protect_from_forgery # :secret => '6f341ac14ba3f458f8420d3a2a879084'
  
  # See ActionController::Base for details 
  # Uncomment this to filter the contents of submitted sensitive data parameters
  # from your application log (in this case, all fields with names like "password"). 
  # filter_parameter_logging :password


protected

  protected
  def get_statuses
    @vmstatus = VMStatus.get_statuses
  end

  def require_login
      if @sso = sso_auth
        render :template => 'layouts/403', :status => 403 unless current_user && authorized?
      end
  end

  def optional_login
      if @sso = sso_auth(:redirect => false)
        current_user
      end
  end

  def current_user
    if @sso = sso_auth()
      @sso[:user]
    else
      nil
    end
  end

  def logged_in?
    !current_user.nil?
  end

  def admin?
    logged_in? && current_user.admin?
  end

  def authorized?; true; end

end
