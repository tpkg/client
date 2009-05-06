$debug = true

class Deployer
  def self.new
    begin
      require 'rubygems'
      require 'thread_pool'
      require 'net/ssh'
    rescue LoadError
      raise LoadError, "must have net/ssh gem installed"
    else
      super
    end
  end

  def initialize
    @mutex = Mutex.new
  end

  def prompt
    print "Username: "
    user = $stdin.gets.chomp

    print "Password (leave blank if using ssh key): "
    password = $stdin.gets.chomp
    return user, password
  end

  $sudo_pwd = nil?
  def get_sudo_pw
    @mutex.synchronize {
      if $sudo_pw.nil?
        puts "Sudo password: "
        $sudo_pw = $stdin.gets
      else
        return $sudo_pw
      end    
    }
  end

  $passphrases = {}
  def get_passphrase(package)
    @mutex.synchronize {
      if $passphrases[package].nil?
        $stdout.write package
        $stdout.flush
        $passphrases[package] = $stdin.gets.chomp
      else
        return $passphrases[package]
      end   
    }
  end

  def ssh_execute(server, username, password, cmd)
    return lambda { 
      exit_status = 0
      result = []
      Net::SSH.start(server, username, :password => password) do |ssh|
      #Net::SSH.start(server, username) do |ssh|
        ch = ssh.open_channel do |channel|
          # now we request a "pty" (i.e. interactive) session so we can send data
          # back and forth if needed. it WILL NOT WORK without this, and it has to
          # be done before any call to exec.
  
          channel.request_pty do |ch, success|
            raise "Could not obtain pty (i.e. an interactive ssh session)" if !success
          end
  
          channel.exec(cmd) do |ch, success|
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
                channel.send_data "#{password}\n"
              elsif data  =~ /^Passphrase for/ 
                passphrase = get_passphrase(data)  
                channel.send_data "#{passphrase}\n"
              else
#                print "#{server}: #{data}" if $debug
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

      return exit_status
    }
  end

  def deploy(packages, abort_on_fail, max_worker, servers, action)
    if action == "install"
      cmd = "sudo tpkg -i #{packages.join(",")}"
#      cmd = "sudo ruby /tmp/tpkg/tpkg -i #{packages.join(",")}"
    elsif action == "remove"
      cmd = "sudo tpkg -r #{packages.join(",")} -n"
#      cmd = "sudo ruby /tmp/tpkg/tpkg -r #{packages.join(",")} -n"
    elsif action == "upgrade"
      cmd = "sudo tpkg -u #{packages.join(",")} -n"
#      cmd = "sudo ruby /tmp/tpkg/tpkg -u #{packages.join(",")} -n"
    elsif action == "start"
      cmd = "sudo tpkg --start #{packages.join(",")}"
#      cmd = "sudo ruby /tmp/tpkg/tpkg --start #{packages.join(",")}"
    elsif action == "stop"
      cmd = "sudo tpkg --stop #{packages.join(",")}"
#      cmd = "sudo ruby /tmp/tpkg/tpkg --stop #{packages.join(",")}"
    elsif action == "restart"
      cmd = "sudo tpkg --restart #{packages}"
#      cmd = "sudo ruby /tmp/tpkg/tpkg --restart #{packages}"
    end

    user, password = prompt
    tp = ThreadPool.new(max_worker)
    statuses = {}
    deploy_to = []
    if servers.kind_of?(Proc)
      deploy_to = servers.call
    else
      deploy_to = servers
    end

    deploy_to.each do | server |
      tp.process do
        status = ssh_execute(server, user, password, cmd).call
        statuses[server] = status 
      end
    end
    tp.shutdown
    puts "Exit statuses: "
    puts statuses.inspect
  end
end
