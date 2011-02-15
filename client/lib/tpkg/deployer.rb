##############################################################################
# tpkg package management system
# Copyright 2009, 2010, 2011 AT&T Interactive
# License: MIT (http://www.opensource.org/licenses/mit-license.php)
##############################################################################

# We store these gems in our thirdparty directory. So we need to add it
# it to the search path
$:.unshift(File.join(File.dirname(__FILE__), 'thirdparty/net-ssh-2.1.0/lib'))

$debug = true

# Exclude standard libraries and gems from the warnings induced by
# running ruby with the -w flag.  If any of these had warnings there's
# nothing we could do to fix that.
require 'tpkg/silently'
Silently.silently do
  begin
    # Try loading net-ssh w/o gems first so that we don't introduce a
    # dependency on gems if it is not needed.
    require 'net/ssh'
  rescue LoadError
    require 'rubygems'
    require 'net/ssh'
  end
end
require 'tpkg/thread_pool'

class Deployer
  
  def initialize(options = nil)
    @sudo_pw = nil
    @pw_prompts = {}
    @mutex = Mutex.new
    @max_worker = 4
    @abort_on_failure = false
    @use_ssh_key = false
    @user = Etc.getlogin
    @password = nil
    unless options.nil?
      @user = options["deploy-as"] unless options["deploy-as"].nil?
      @password = options["deploy-password"] unless options["deploy-password"].nil?
      @max_worker = options["max-worker"]
      @abort_on_failure = options["abort-on-failure"]
      @use_ssh_key = options["use-ssh-key"]
      @ssh_key = options["ssh-key"]
    end
  end
  
  def prompt_username
    ask("Username: ")
  end
  
  def prompt_password
    ask("SSH Password (leave blank if using ssh key): ", true)
  end
  
  def ask(str,mask=false)
    begin
      system 'stty -echo;' if mask
      print str
      input = STDIN.gets.chomp
    ensure
      system 'stty echo; echo ""'
    end
    return input
  end
  
  def get_sudo_pw
    @mutex.synchronize {
      if @sudo_pw.nil?
        @sudo_pw = ask("Sudo password: ", true)
      else
        return @sudo_pw
      end
    }
  end
  
  # Prompt user for input and cache it. If in the future, we see
  # the same prompt again, we can reuse the existing inputs. This saves
  # the users from having to type in a bunch of inputs (such as password)
  def get_input_for_pw_prompt(prompt)
    @mutex.synchronize {
      if @pw_prompts[prompt].nil?
        @pw_prompts[prompt] = ask(prompt, true)
      end
      return @pw_prompts[prompt]
    }
  end
  
  # Return a block that can be used for executing a cmd on the remote server
  def ssh_execute(server, username, password, key, cmd)
    return lambda {
      exit_status = 0
      result = []
      
      params = {}
      params[:password] = password if password
      params[:keys] = [key] if key
      
      begin
        Net::SSH.start(server, username, params) do |ssh|
          puts "Connecting to #{server}"
          ch = ssh.open_channel do |channel|
            # now we request a "pty" (i.e. interactive) session so we can send data
            # back and forth if needed. it WILL NOT WORK without this, and it has to
            # be done before any call to exec.
            
            channel.request_pty do |ch_pty, success|
              raise "Could not obtain pty (i.e. an interactive ssh session)" if !success
            end
            
            channel.exec(cmd) do |ch_exec, success|
              puts "Executing #{cmd} on #{server}"
              # 'success' isn't related to bash exit codes or anything, but more
              # about ssh internals (i think... not bash related anyways).
              # not sure why it would fail at such a basic level, but it seems smart
              # to do something about it.
              abort "could not execute command" unless success
              
              # on_data is a hook that fires when the loop that this block is fired
              # in (see below) returns data. This is what we've been doing all this
              # for; now we can check to see if it's a password prompt, and
              # interactively return data if so (see request_pty above).
              channel.on_data do |ch_data, data|
                if data =~ /Password:/
                  password = get_sudo_pw unless !password.nil? && password != ""
                  channel.send_data "#{password}\n"
                elsif data =~ /password/i or data  =~ /passphrase/i or
                      data =~ /pass phrase/i or data =~ /incorrect passphrase/i
                  input = get_input_for_pw_prompt(data)
                  channel.send_data "#{input}\n"
                else
                  result << data unless data.nil? or data.empty?
                end
              end
              
              channel.on_extended_data do |ch_onextdata, type, data|
                print "SSH command returned on stderr: #{data}"
              end
              
              channel.on_request "exit-status" do |ch_onreq, data|
                exit_status = data.read_long
              end
            end
          end
          ch.wait
          ssh.loop
        end
        if $debug
          puts "==================================================\nResult from #{server}:"
          puts result.join
          puts "=================================================="
        end
      rescue Net::SSH::AuthenticationFailed
        exit_status = 1
        puts "Bad username/password combination"
      rescue Exception => e
        exit_status = 1
        puts e.inspect
        puts e.backtrace
        puts "Can't connect to server"
      end
      
      return exit_status
    }
  end
  
  # deploy_params is an array that holds the list of paramters that is used when invoking tpkg on to the remote
  # servers where we want to deploy to.
  # 
  # servers is an array, a filename or a callback that list the remote servers where we want to deploy to
  def deploy(deploy_params, servers)
    params = deploy_params.join(" ")
    cmd = nil
    if ENV['TPKG_HOME']
      # Preserve TPKG_HOME when deploying to remote systems so that users can
      # perform operations against different tpkg base directories.
      cmd = "tpkg #{params} --base #{ENV['TPKG_HOME']} -n"
    else
      cmd = "tpkg #{params} -n"
    end
    user = @user
    
    if @user.nil?  && !@use_ssh_key
      @user = prompt_username
    end
    
    if @password.nil? && !@use_ssh_key
      @password = prompt_password
    end
    
    tp = ThreadPool.new(@max_worker)
    statuses = {}
    deploy_to = []
    if servers.kind_of?(Proc)
      deploy_to = servers.call
    elsif servers.size == 1 && File.exists?(servers[0])
      puts "Reading server list from file #{servers[0]}"
      File.open(servers[0], 'r') do |f|
        while line = f.gets
          deploy_to << line.chomp.split(",")
        end
      end
      deploy_to.flatten!
    else
      deploy_to = servers
    end
    
    deploy_to.each do | server |
      tp.process do
        status = ssh_execute(server, @user, @password, @ssh_key, cmd).call
        statuses[server] = status
      end
    end
    tp.shutdown
    puts "Exit statuses: "
    puts statuses.inspect
    
    return statuses
  end
end

