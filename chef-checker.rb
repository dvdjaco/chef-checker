#!/usr/bin/env ruby

require "time"
require 'optparse'
#require 'debugger' # Uncomment to use debugger

class ChefClientStatus

  def initialize()
    # Parse command line options and set default values
    opts = Hash.new
    opts[:log_file] = "/var/log/chef/client.log"
    opts[:debug] = false
  
    oparse = OptionParser.new do |o|
      o.banner = "Usage: chef-checker.rb [options]"
      o.separator ""
      o.separator "Specific options:"
      
      o.on("-vv", "Turn debug mode on") do |b|
         opts[:debug] = b
      end
      o.on("-w WARNTIME",
      "Exit with Warning status if elapsed time since last",
      " chef-client run exceeds WARNTIME") do |secs|
        opts[:warn_time] = secs.to_i
      end
      o.on('-c CRITTIME',
      "Exit with Critical status if elapsed time since last",
      " chef-client run exceeds CRITTIME") do |secs|
        opts[:crit_time] = secs.to_i
      end
      o.on('-l LOG_FILE') { |filename| opts[:log_file] = filename }
      
      o.separator ""
      o.separator "Common options:"
      
      o.on('-h', '--help', "This message") { puts o; exit }
    end
    
    begin
      oparse.parse!
      mandatory = [:warn_time, :crit_time]
      missing = mandatory.select{ |par| opts[par].nil?}
      if not missing.empty?
        puts "Missing options: #{missing.join(", ")}"
        puts oparse
        exit
      end
    end
      
    
    @service_status = {
      0 => "OK",
      1 => "Warning",
      2 => "Critical",
      3 => "Unknown"
    }
    
    @logfile = opts[:log_file]
    @debug = opts[:debug]
    @warn_time = opts[:warn_time]
    @crit_time = opts[:crit_time]
    @status = {
      :state_code => 3,  # initial status is "Unknown"
      :state_info => ""      
    }
   	logfile = opts[:log_file]
    @hostname = `/bin/hostname`.chomp
    
    # typical chef-client runs in www servers are ~350 lines
    tail_lines = 1000    
    cmd = "/usr/bin/tail -n" + " " + tail_lines.to_s +  " " + logfile
    log_tail = `#{cmd}`
    log_tail_a = []
    @last_run = []
    
    # save the last run
    log_tail.lines{ |line| @last_run << line.chomp}
    @last_run = @last_run[@last_run.rindex{ |x| x["*** Chef"]}..-1]
  end
    
  def run
    process()
    output()
  end
  
  def process()
    # extract the date from the last line of the log
    date_s = @last_run[-1].split(']')[0][1..-1]
    t_lastrun = Time.parse(date_s)
    t_now = Time.new
    
    # search for ERROR or FATAL messages in the log
    @last_run.each do |line|
      if ((line["ERROR"]) or (line["FATAL"]))
        @status[:state_code] = 2  # set the state to Critical
        @status[:state_info] = "The last run failed"
        @status[:state_extinfo] = "First error message: \"#{line}\""
        return
      end
    end
    
    # check the time elapsed since last run ended
    elapsed_time = t_now - t_lastrun
    if (elapsed_time > @warn_time)
      h = (elapsed_time/3600).to_i
      m = (elapsed_time/60 - h*60).to_i
      s = (elapsed_time - m*60 - h*3600).to_i
      @status[:state_code] = 1  # set state to Warning
      @status[:state_info] = "Last run finished #{h}h #{m}m ago"
      @status[:state_extinfo] = elapsed_time.to_i.to_s + "s"
      if (elapsed_time > @crit_time)
          @status[:state_code] = 2  # set state to Critical
      end
      return      
    end
    
    @status[:state_code] = 0 # Status is OK    
  end
  
  def output()
    service_status = @service_status[@status[:state_code]] 
    data = "chef-client #{service_status} - #{@status[:state_info]}|#{@status[:state_extinfo]}\n"
    if(@debug)
        puts "The status of the service is #{@status[:state_code].to_s}."
        puts "The state info is: #{@status[:state_info]}"
        puts "Log file analysed: #{@logfile}"
    else
        puts data
    end
  end
end

if __FILE__ == $0
  chef_client_status = ChefClientStatus.new()
  chef_client_status.run
end
