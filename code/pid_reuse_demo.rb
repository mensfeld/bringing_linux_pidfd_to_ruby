#!/usr/bin/env ruby
# PID Reuse Vulnerability Demonstration
# -------------------------------------
#
# This script demonstrates the security vulnerability related to PID reuse in Linux
# and how it could potentially lead to security issues that pidfd was designed to solve.

# multipass launch -n pid-demo / multipass start pid-demo
# multipass shell pid-demo
# multipass transfer pid_reuse_demo.rb pid-demo:
# sudo sysctl -w kernel.pid_max=1512

require 'fileutils'
require 'optparse'

class PidReuseDemo
  attr_reader :options

  def initialize
    @options = {
      pool_size: 100,
      attempts: 50000,
      debug: false,
      fast: false,
      attack_demo: false
    }
    
    @temp_dir = "/tmp/pid_reuse_demo_#{Process.pid}"
    @pid_file = "#{@temp_dir}/target_pid"
    @token_file = "#{@temp_dir}/secret_token"
    @privileged_process = nil
    @process_pool = []
    
    parse_options
    setup_environment
  end
  
  def parse_options
    OptionParser.new do |opts|
      opts.banner = "Usage: pid_reuse_demo.rb [options]"
      
      opts.on("-p", "--pool-size SIZE", Integer, "Size of process pool (default: #{@options[:pool_size]})") do |size|
        @options[:pool_size] = size
      end
      
      opts.on("-a", "--attempts NUM", Integer, "Number of reuse attempts (default: #{@options[:attempts]})") do |num|
        @options[:attempts] = num
      end
      
      opts.on("-d", "--debug", "Enable debug output") do
        @options[:debug] = true
      end
      
      opts.on("-f", "--fast", "Use fast mode (less reliable but quicker)") do
        @options[:fast] = true
      end
      
      opts.on("-x", "--attack", "Demonstrate privilege escalation attack") do
        @options[:attack_demo] = true
      end
      
      opts.on("-h", "--help", "Show this help message") do
        puts opts
        exit
      end
    end.parse!
  end
  
  def setup_environment
    # Create temporary directory
    FileUtils.mkdir_p(@temp_dir)
    puts "Created temporary directory: #{@temp_dir}"

    # Check PID max value
    @pid_max = File.read("/proc/sys/kernel/pid_max").to_i rescue 32768
    puts "Current system PID max: #{@pid_max}"

    if @pid_max > 10000 && !@options[:fast]
      puts "\n[WARNING] Your pid_max is high (#{@pid_max}), which may make PID reuse difficult to demonstrate"
      puts "Consider temporarily lowering it with: sudo sysctl -w kernel.pid_max=4096"
      puts "Or run with --fast option for a different demonstration approach"
      puts "Continuing with current settings in 3 seconds..."
      sleep 3
    end
  end
  
  def debug(message)
    puts "[DEBUG] #{message}" if @options[:debug]
  end
  
  def create_process_pool
    puts "\nCreating a pool of #{@options[:pool_size]} processes to consume PID space..."
    
    @options[:pool_size].times do |i|
      pid = fork do
        # Child process - just sleep
        trap("TERM") { exit(0) }
        trap("INT") { exit(0) }
        sleep 300 # Sleep for 5 minutes max
      end
      
      if pid
        @process_pool << pid
        if i % 10 == 0
          print "."
          STDOUT.flush
        end
      end
    end
    
    puts "\nCreated #{@process_pool.size} processes"
  end
  
  def create_privileged_process
    return unless @options[:attack_demo]
    
    puts "\nCreating 'privileged' process that will handle secure data..."
    
    # Generate a random token to simulate privileged data
    secret_token = rand(10000..99999).to_s
    
    @privileged_process = fork do
      # This process simulates a privileged process with access to sensitive data
      File.write(@token_file, secret_token)
      puts "Privileged process (PID: #{Process.pid}) created with secret token: #{secret_token}"
      
      # Store my PID for the demo
      File.write(@pid_file, Process.pid.to_s)
      
      # Wait for signals
      trap("USR1") do
        puts "Privileged process received USR1 signal, checking authorization..."
        puts "Privileged action performed! Secret shared."
        
        # Simulate privileged action by revealing secret again
        File.write(@token_file, secret_token)
      end
      
      # Just sleep and wait for signals
      sleep 300
    end
    
    # Wait for privileged process to initialize
    sleep 1
    puts "Privileged process running with PID: #{@privileged_process}"
  end
  
  def demonstrate_pid_reuse_simple
    puts "\n== Basic PID Reuse Demonstration =="
    
    # Create and terminate a target process
    target_pid = fork do
      exit(0)
    end
    
    # Wait for it to terminate
    Process.wait(target_pid)
    puts "Created and terminated process with PID: #{target_pid}"
    
    # Try to get the same PID
    found_reuse = false
    puts "Attempting to catch PID reuse over #{@options[:attempts]} attempts..."
    
    attempt_count = 0
    @options[:attempts].times do |i|
      attempt_count = i + 1
      
      # Every 50 attempts, kill some processes from our pool to free more PIDs
      if i % 50 == 49 && !@process_pool.empty?
        debug("Freeing 20 PIDs from the pool to increase reuse chance...")
        20.times do
          break if @process_pool.empty?
          pid_to_kill = @process_pool.pop
          Process.kill("TERM", pid_to_kill) rescue nil
        end
      end
      
      # Try to create a new process
      new_pid = fork do
        # Store my PID
        File.write("#{@temp_dir}/current_pid", Process.pid.to_s)
        sleep 2
        exit(0)
      end
      
      # Small delay to let child write its PID
      sleep 0.01
      
      # Read the actual PID of the child
      actual_pid = File.read("#{@temp_dir}/current_pid").to_i rescue 0
      
      if actual_pid == target_pid
        found_reuse = true
        puts "\n[SUCCESS] PID REUSED: New process got recycled PID #{actual_pid} after #{attempt_count} attempts!"
        Process.wait(new_pid) rescue nil
        break
      end
      
      # Status update every 50 attempts
      if i % 50 == 0
        print "."
        STDOUT.flush
      end
      
      # Clean up this child
      Process.kill("TERM", new_pid) rescue nil
      Process.wait(new_pid) rescue nil
    end
    
    unless found_reuse
      puts "\nCould not demonstrate PID reuse after #{attempt_count} attempts."
      puts "This is expected behavior in modern Linux which actively tries to prevent immediate PID reuse."
      puts "In real-world scenarios with longer-running systems, PIDs would eventually be reused."
    end
  end
  
  def demonstrate_pid_reuse_attack
    return unless @options[:attack_demo]
    
    puts "\n== PID Reuse Attack Demonstration =="
    puts "This demonstration shows how PID reuse could be exploited in a privilege escalation scenario"
    
    # Get the PID of our privileged process
    target_pid = File.read(@pid_file).to_i
    puts "Target privileged process has PID: #{target_pid}"
    
    # Original secret (simulating a privileged resource)
    original_token = File.read(@token_file) rescue "unknown"
    puts "Original secret token: #{original_token}"
    
    # Now terminate the privileged process (simulating it crashing or ending naturally)
    puts "Terminating privileged process..."
    Process.kill("TERM", @privileged_process) rescue nil
    Process.wait(@privileged_process) rescue nil
    puts "Privileged process terminated"
    
    # Try to get the same PID to impersonate it
    found_reuse = false
    puts "Attempting to impersonate privileged process by catching PID reuse..."
    
    attempt_count = 0
    @options[:attempts].times do |i|
      attempt_count = i + 1
      
      # Every 50 attempts, kill some processes from our pool to free more PIDs
      if i % 50 == 49 && !@process_pool.empty?
        debug("Freeing 20 PIDs from the pool to increase reuse chance...")
        20.times do
          break if @process_pool.empty?
          pid_to_kill = @process_pool.pop
          Process.kill("TERM", pid_to_kill) rescue nil
        end
      end
      
      # Try to create a new process
      new_pid = fork do
        # Check if we got the target PID
        if Process.pid == target_pid
          # We got lucky! We now have the same PID as the privileged process
          puts "ATTACK SUCCESS: Created malicious process with reused PID: #{Process.pid}"
          
          # In a real attack, this would be where the malicious code runs
          # For demo purposes, we'll create a new "secret" token to show we've replaced the process
          File.write(@token_file, "COMPROMISED-#{rand(1000..9999)}")

          # Wait for potential signals that were meant for the original process
          trap("USR1") do
            puts "ATTACK: Malicious process received signal meant for privileged process!"
            puts "ATTACK: Intercepted privileged action request."
            File.write(@token_file, "STOLEN-DATA-#{rand(1000..9999)}")
          end
          
          sleep 30
        else
          # Not the PID we're looking for
          sleep 1
        end
        exit(0)
      end
      
      # Small delay
      sleep 0.01
      
      # Check if we got the target PID
      if new_pid == target_pid
        found_reuse = true
        puts "\n[SUCCESS] PID REUSED: Attack process got target PID #{target_pid} after #{attempt_count} attempts!"
        
        # Try to send a signal to the "privileged" process (which is now our malicious process)
        puts "Simulating another process sending a signal to what it thinks is the privileged process..."
        sleep 1
        Process.kill("USR1", target_pid) rescue nil
        
        # Wait to see the results
        sleep 2
        
        # Check if our attack worked
        new_token = File.read(@token_file) rescue "unknown"
        puts "New token: #{new_token}"
        
        if new_token != original_token && new_token.include?("STOLEN")
          puts "\n[DEMONSTRATION COMPLETE] Successfully demonstrated PID reuse attack!"
          puts "The malicious process was able to intercept actions intended for the privileged process."
          puts "This is why pidfd is important - it would prevent this class of attacks."
        end
        
        break
      end
      
      # Status update every 50 attempts
      if i % 50 == 0
        print "."
        STDOUT.flush
      end
      
      # Clean up this child
      Process.kill("TERM", new_pid) rescue nil
      Process.wait(new_pid) rescue nil
    end
    
    unless found_reuse
      puts "\nCould not demonstrate PID reuse attack after #{attempt_count} attempts."
      puts "This shows how modern Linux protects against immediate PID reuse."
      puts "However, with enough time and in production systems, these vulnerabilities would appear."
    end
  end
  
  def demonstrate_fast_mode
    if @options[:fast]
      puts "\n== Fast Mode Demonstration =="
      puts "In fast mode, we won't try to catch an actual PID reuse"
      puts "Instead, we'll demonstrate the *concept* of the vulnerability"
      
      # Create a "privileged" process with a specific PID
      privileged_pid = fork do
        puts "Privileged process running with PID: #{Process.pid}"
        token = "SECRET_DATA_#{rand(1000..9999)}"
        File.write(@token_file, token)
        puts "Privileged process has confidential data: #{token}"
        sleep 5
        exit(0)
      end
      
      Process.wait(privileged_pid)
      puts "Privileged process terminated"
      
      # Simulate a long time passing (in reality this could be hours or days)
      puts "Time passes... (in a real system, PID would eventually be reused)"
      sleep 1
      
      # Create a "malicious" process and pretend it got the same PID
      malicious_pid = fork do
        puts "Malicious process running (pretending to have PID: #{privileged_pid})"
        puts "In a vulnerable system, after enough time passes, this process"
        puts "could get the same PID as the terminated privileged process"
        
        new_token = "FAKE_DATA_#{rand(1000..9999)}"
        File.write(@token_file, new_token)
        puts "Malicious process wrote fake data: #{new_token}"
        
        sleep 2
      end
      
      Process.wait(malicious_pid)
      
      puts "\nVulnerability explanation:"
      puts "1. A privileged process runs with PID X and has access to sensitive data"
      puts "2. The process terminates (crashes, completes, etc.)"
      puts "3. Later, a malicious process happens to get assigned the same PID X"
      puts "4. Other processes that cached PID X as 'privileged' may trust the new process"
      
      puts "\nThis is why PIDs are insecure for long-term process identification"
      puts "pidfd solves this by using file descriptors that become invalid when"
      puts "the process they refer to terminates, preventing this class of attacks."
    end
  end
  
  def cleanup
    puts "\nCleaning up..."
    
    # Kill all processes in our pool
    @process_pool.each do |pid|
      Process.kill("TERM", pid) rescue nil
    end
    
    # Collect exit statuses to avoid zombies
    @process_pool.each do |pid|
      Process.wait(pid) rescue nil
    end
    
    # Remove temporary files
    FileUtils.rm_rf(@temp_dir)
    
    puts "Done! All temporary processes and files have been cleaned up."
  end
  
  def run
    trap("INT") do
      puts "\nInterrupted! Cleaning up..."
      cleanup
      exit(1)
    end
    
    puts
    puts "PID Reuse Vulnerability Demonstration"
    puts "===================================="
    puts
    
    # Create a pool of processes to consume PID space
    create_process_pool
    
    if @options[:attack_demo]
      # Create a process that simulates a privileged process
      create_privileged_process
      demonstrate_pid_reuse_attack
    elsif @options[:fast]
      demonstrate_fast_mode
    else
      demonstrate_pid_reuse_simple
    end

    cleanup
  end
end

if __FILE__ == $0
  PidReuseDemo.new.run
end
