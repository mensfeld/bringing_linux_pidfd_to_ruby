#!/usr/bin/env ruby
require 'fileutils'
require 'ffi'

# Set up paths for demo
TMPDIR = "/tmp/pidfd_security_demo"
FileUtils.rm_rf(TMPDIR)
FileUtils.mkdir_p(TMPDIR)
pidfile = "#{TMPDIR}/trusted_pid"
dumpfile = "#{TMPDIR}/memdump.log"
marker = "#{TMPDIR}/attacker_ready"

# Implementation of Karafka's Pidfd for the demo
module Karafka
  module Swarm
    module Errors
      class PidfdOpenFailedError < StandardError; end
      class PidfdSignalFailedError < StandardError; end
    end
    
    class Pidfd
      extend FFI::Library
      
      begin
        ffi_lib FFI::Library::LIBC
        
        # Direct usage of this is only available since glibc 2.36, hence we use bindings and call
        # it directly via syscalls
        attach_function :fdpid_open, :syscall, %i[long int uint], :int
        attach_function :fdpid_signal, :syscall, %i[long int int pointer uint], :int
        attach_function :waitid, %i[int int pointer uint], :int
        
        API_SUPPORTED = true
      # LoadError is a parent to FFI::NotFoundError
      rescue LoadError
        API_SUPPORTED = false
      end
      
      # https://github.com/torvalds/linux/blob/7e90b5c295/include/uapi/linux/wait.h#L20
      P_PIDFD = 3
      
      # Wait for child processes that have exited
      WEXITED = 4
      
      # Syscall numbers for x86_64
      PIDFD_OPEN_SYSCALL = 434
      PIDFD_SIGNAL_SYSCALL = 424
      
      class << self
        # @return [Boolean] true if syscall is supported via FFI
        def supported?
          # If we were not even able to load the FFI C lib, it won't be supported
          return false unless API_SUPPORTED
          # Won't work on macOS because it does not support pidfd
          return false if RUBY_DESCRIPTION.include?('darwin')
          # Won't work on Windows for the same reason as on macOS
          return false if RUBY_DESCRIPTION.match?(/mswin|ming|cygwin/)
          
          # There are some OSes like BSD that will have C lib for FFI bindings but will not support
          # the needed syscalls. In such cases, we can just try and fail, which will indicate it
          # won't work. The same applies to using new glibc on an old kernel.
          new(::Process.pid)
          
          true
        rescue Errors::PidfdOpenFailedError
          false
        end
      end
      
      # @param pid [Integer] pid of the node we want to work with
      def initialize(pid)
        @mutex = Mutex.new
        
        @pid = pid
        @pidfd = open(pid)
        @pidfd_io = IO.new(@pidfd)
      end
      
      # @return [Boolean] true if given process is alive, false if no longer
      def alive?
        @pidfd_select ||= [@pidfd_io]

        if @mutex.owned?
          return false if @cleaned

          IO.select(@pidfd_select, nil, nil, 0).nil?
        else
          @mutex.synchronize do
            return false if @cleaned

            IO.select(@pidfd_select, nil, nil, 0).nil?
          end
        end

      end

      # Cleans the zombie process
      # @note This should run **only** on processes that exited, otherwise will wait
      def cleanup
        @mutex.synchronize do
          return if @cleaned
          
          waitid(P_PIDFD, @pidfd, nil, WEXITED)
          
          @pidfd_io.close
          @pidfd_select = nil
          @pidfd_io = nil
          @pidfd = nil
          @cleaned = true
        end
      end
      
      # Sends given signal to the process using its pidfd
      # @param sig_name [String] signal name
      # @return [Boolean] true if signal was sent, otherwise false or error raised. `false`
      #   returned when we attempt to send a signal to a dead process
      # @note It will not send signals to dead processes
      def signal(sig_name)
        @mutex.synchronize do
          return false if @cleaned
          # Never signal processes that are dead
          return false unless alive?
          
          result = fdpid_signal(
            PIDFD_SIGNAL_SYSCALL,
            @pidfd,
            Signal.list.fetch(sig_name),
            nil,
            0
          )
          
          return true if result.zero?
          
          raise Errors::PidfdSignalFailedError, result
        end
      end
      
      private
      
      # Opens a pidfd for the provided pid
      # @param pid [Integer]
      # @return [Integer] pidfd
      def open(pid)
        pidfd = fdpid_open(
          PIDFD_OPEN_SYSCALL,
          pid,
          0
        )
        
        return pidfd if pidfd != -1
        
        raise Errors::PidfdOpenFailedError, pidfd
      end
    end
  end
end

puts "\n=== pidfd Security Demo ==="
puts "This demo shows how Karafka's pidfd implementation prevents PID reuse attacks"

# First check if pidfd is supported
unless Karafka::Swarm::Pidfd.supported?
  puts "\n[!] ERROR: pidfd is not supported on this system"
  puts "[!] You need Linux 5.3 or newer to run this demo"
  exit 1
end

puts "\n[*] Step 1: Starting trusted daemon process..."
trusted_pid = fork do
  trap("USR1") do
    puts "[trusted] Dumping real memory to #{dumpfile}"
    File.write(dumpfile, "REAL_DUMP: WARNING! Critical security anomalies detected!\n")
  end
  File.write(pidfile, Process.pid.to_s)
  puts "[trusted] Running with PID #{Process.pid}"
  sleep 5
end
sleep 1 # Allow process to start

puts "[*] Trusted process running with PID #{trusted_pid}"
puts "[*] Creating stable pidfd reference to trusted process..."

# Create a pidfd for the trusted process
process_ref = Karafka::Swarm::Pidfd.new(trusted_pid)
puts "[*] Successfully created pidfd for trusted process"

puts "\n[*] Step 2: Killing the trusted process..."
Process.kill("TERM", trusted_pid)
Process.wait(trusted_pid)
puts "[*] Trusted process terminated."

# Attempt PID reuse
target_pid = File.read(pidfile).to_i
puts "[*] Attacker attempting to reuse PID #{target_pid}..."

max_attempts = 1000
success = false
attacker_pid = nil

max_attempts.times do |i|
  pid = fork do
    if Process.pid == target_pid
      puts "[attacker] Successfully reused PID #{Process.pid}!"
      File.write(marker, Process.pid.to_s)
      trap("USR1") do
        puts "[attacker] Received SIGUSR1 — faking memory dump!"
        File.write(dumpfile, "FAKE_DUMP: No anomalies detected. System is secure.\n")
      end
      sleep 10
      exit 0
    else
      exit 0
    end
  end
  
  if pid == target_pid
    attacker_pid = pid
    success = true
    break
  else
    Process.wait(pid) rescue nil
  end
  
  if File.exist?(marker)
    attacker_pid = File.read(marker).to_i
    success = true
    break
  end
end

if success
  puts "[*] PID #{target_pid} successfully reused by attacker"
else
  puts "[*] Could not reuse PID after #{max_attempts} attempts, simulating success"
  puts "[*] Assume PID #{target_pid} is now controlled by an attacker"
  attacker_pid = fork do
    trap("USR1") do
      puts "[attacker] Received SIGUSR1 — faking memory dump!"
      File.write(dumpfile, "FAKE_DUMP: No anomalies detected. System is secure.\n")
    end
    sleep 10
  end
end

puts "\n[*] Step 3: Security system checking process via pidfd..."

if process_ref.alive?
  puts "[!] pidfd incorrectly reports process is still alive (this should not happen)"
else
  puts "[*] pidfd correctly reports process is no longer alive"
  puts "[*] Security system will not send signal to PID #{target_pid}"
  puts "[✓] ATTACK PREVENTED: pidfd detected that the original process is gone"
  puts "    Even though PID #{target_pid} exists, we know it's not our trusted process"
end

# Just for demonstration - try to signal through pidfd
puts "\n[*] Attempting to signal through pidfd..."
if process_ref.signal("USR1")
  puts "[!] Signal sent successfully (this should not happen)"
else
  puts "[✓] Signal not sent - pidfd knows this isn't our trusted process"
end

# If we had used PID-based approach instead
puts "\n[*] If we had used traditional PID-based approach:"
puts "    Process.kill(\"USR1\", #{target_pid}) would have signaled the attacker process"
puts "    Leading to false data and a potential security breach"

# Clean up the pidfd
process_ref.cleanup

# Clean up attacker process if it exists
begin
  Process.kill("TERM", attacker_pid) if attacker_pid
  Process.wait(attacker_pid) if attacker_pid
rescue
  # Ignore errors
end

FileUtils.rm_rf(TMPDIR)