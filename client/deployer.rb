# We store these gems in our thirdparty directory. So we need to add it
# it to the search path
$:.unshift(File.join(File.dirname(__FILE__), 'thirdparty/net-ssh-2.0.11/lib'))
$:.unshift(File.join(File.dirname(__FILE__), 'thirdparty/highline-1.5.1/lib'))

$debug = true

require 'thread_pool'
require 'net/ssh'
#require 'highline/import'

class Deployer
#  def self.new
#    begin
#      require 'rubygems'
#      require 'net/ssh'
#      require 'highline/import'
#    rescue LoadError
#      raise LoadError, "In order to use the deployment feature, you must have rubygems installed. Additionally, you need to install the following gems: net-ssh, highline"
#    else
#      super
#    end
#  end

  def initialize(options = nil)
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
    end
  end

  def prompt
    user = prompt_username
    password = prompt_password
    return user, password
  end

  def prompt_username
    print "Username: "
    user = $stdin.gets.chomp
    return user
  end     
         
  def prompt_password
    password = ask("SSH Password (leave blank if using ssh key): ", true) 
    return password 
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

  $sudo_pw = nil
  def get_sudo_pw
    @mutex.synchronize {
      if $sudo_pw.nil?
        $sudo_pw = ask("Sudo password: ", true)
      else
        return $sudo_pw
      end    
    }
  end

  $passphrases = {}
  def get_passphrase(package)
    @mutex.synchronize {
      if $passphrases[package].nil?
      #  $stdout.write package
      #  $stdout.flush
      #  $passphrases[package] = $stdin.gets.chomp
        $passphrases[package] = ask(package, true)
      else
        return $passphrases[package]
      end   
    }
  end

  def ssh_execute(server, username, password, cmd)
    return lambda { 
      exit_status = 0
      result = []

      begin
        Net::SSH.start(server, username, :password => password) do |ssh|
          puts "Connecting to #{server}"
          ch = ssh.open_channel do |channel|
            # now we request a "pty" (i.e. interactive) session so we can send data
            # back and forth if needed. it WILL NOT WORK without this, and it has to
            # be done before any call to exec.
  
            channel.request_pty do |ch, success|
              raise "Could not obtain pty (i.e. an interactive ssh session)" if !success
            end
  
            channel.exec(cmd) do |ch, success|
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
              channel.on_data do |ch, data|
                if data == "Password:"
                  #sudo_password = (!password.nil && password != "" && password) ||  get_sudo_pw
                  password = get_sudo_pw unless !password.nil? && password != ""
                  channel.send_data "#{password}\n"
                elsif data  =~ /^Passphrase for/ 
                  passphrase = get_passphrase(data)  
                  channel.send_data "#{passphrase}\n"
                else
#                  print "#{server}: #{data}" if $debug
                  # ssh channels can be treated as a hash for the specific purpose of
                  # getting values out of the block later
#                channel[:result] ||= ""
#                channel[:result] << data
                  result << data unless data.nil? or data.empty?
                end
              end
  
              channel.on_extended_data do |ch, type, data|
                print "SSH command returned on stderr: #{data}"
              end
  
              channel.on_request "exit-status" do |ch, data| 
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
  # servers is an array or a callback that list the remote servers where we want to deploy to
  def deploy(deploy_params, servers)
    params = deploy_params.join(" ")  
    cmd = "tpkg #{params} -n"
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
    else
      deploy_to = servers
    end

    deploy_to.each do | server |
      tp.process do
        status = ssh_execute(server, @user, @password, cmd).call
        statuses[server] = status
      end
    end
    tp.shutdown
    puts "Exit statuses: "
    puts statuses.inspect
    
    return statuses
  end
end
