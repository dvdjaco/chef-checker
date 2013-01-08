#!/usr/bin/env ruby

require "time"
require 'optparse'

class ChefClientStatus

  def initialize()
    # Parse command line options and set default values
    opts = Hash.new
    opts[:debug] = false
    opts[:max_time] = 1800
    opts[:status_file] = "chef-status"
    opts[:log_file] = "/var/log/chef/client.log"
  
    OptionParser.new do |o|
      o.on('-d') { |b| opts[:debug] = b }
      o.on('-m MAXTIME') { |secs| opts[:max_time] = secs }
      o.on('-s STATUS_FILE') { |filename| opts[:status_file] = filename }
      o.on('-l LOG_FILE') { |filename| opts[:log_file] = filename }
      o.on('-h') { puts o; exit }
      o.parse!
    end

    @debug = opts[:debug]
    @max_elapsed_time = opts[:max_time]
    @status = {
      :state_code => 0,
      :state_info => ""      
    }
   	logfile = opts[:log_file]
    @status_file = opts[:status_file]
    @hostname = `hostname`.chomp
    
    # typical chef-client runs in www servers are ~350 lines
    tail_lines = 1000    
    cmd = "tail -n" + " " + tail_lines.to_s +  " " + logfile
    log_tail = `#{cmd}`
    log_tail_a = []
    @last_run = []
    
    # save the last run
    log_tail.lines{ |line| @last_run << line.chomp}
    @last_run = @last_run[@last_run.rindex{ |x| x["*** Chef"]}..-1]
  end
    
  def run
    process()
    submit()
  end
  
  def process()
    # extract the date from the last line of the log
    # last_finished = @last_run[-1]
    date_s = @last_run[-1].split(']')[0][1..-1]
    t_lastrun = Time.parse(date_s)
    t_now = Time.new
    
    # search for ERROR or FATAL messages in the log
    @last_run.reverse_each do |line|
      if ((line["ERROR"]) or (line["FATAL"]))
        @status[:state_code] = 2
        @status[:state_info] = "The last run has errors. Last error message: \"#{line}\""
        return
      end
    end
    
    # check the time elapsed since last run ended
    elapsed_time = t_now - t_lastrun
    if (elapsed_time > @max_elapsed_time)
      h = (elapsed_time/3600).to_i
      m = (elapsed_time/60 - h*60).to_i
      s = (elapsed_time - m*60 - h*3600).to_i
      @status[:state_code] = 2
      @status[:state_info] = "Last run finished #{h}:#{m}:#{s} ago."
      return
    end
    
    @status[:state_code] = 0    
  end
  
  def submit()
    data = "#{@hostname}\tchef-client\t#{@status[:state_code]}\t#{@status[:state_info]}\n"
    File.open(@status_file, 'w') {|f| f.write(data) }
    if(@debug)
        puts "The status of the service is #{@status[:state_code].to_s}."
        puts "The state info is: #{@status[:state_info]}"
        puts "Submission data written to #{@status_file}"
    else
        output = `/usr/sbin/send_nsca icinga1a.zinio.com -c /etc/send_nsca.cfg < #{@status_file}`
        output = `/usr/sbin/send_nsca icinga1b.zinio.com -c /etc/send_nsca.cfg < #{@status_file}`
        output = `/usr/sbin/send_nsca icingaweb1.zinio.com -c /etc/send_nsca.cfg < #{@status_file}` 
    end
  end
end

if __FILE__ == $0
  chef_client_status = ChefClientStatus.new()
  chef_client_status.run
end