#!/usr/bin/env ruby

# In the double-fork daemon demo, there are a few key problems with PID-based tracking:
# 
# Parent-Child Relationship Loss: When a process double-forks (forks twice in succession), the intermediate parent exits immediately after the second fork. This makes the final daemon process a child of init/PID 1 rather than the original parent. This "orphaning" is actually intentional in daemon design (to prevent terminal hangups), but it means the original parent loses its direct relationship with the daemon.
# PID Tracking Gap: There's a timing window between when the first process forks and when the second (daemon) process writes its PID to the file. During this window, any external system has no reliable way to know the actual PID of the running daemon.
# Initial PID Mismatch: The PID returned from the first fork is not the PID of the final daemon process - it's the PID of the intermediate process that exits immediately. If a program uses that initial PID for tracking, it will be tracking the wrong process.

puts "=== Double-Fork Daemon Tracking Issue ==="
puts "This demo shows how PID-based tracking breaks with daemons that double-fork"

# Create a file to use for PID tracking
pid_file = "/tmp/daemon_demo.pid"

puts "Starting a daemon using the classic double-fork technique..."
puts "This technique is commonly used to fully detach daemons from their parent."

# First fork
daemon_pid = fork do
  # Detach from controlling terminal
  Process.setsid
  
  # Second fork (this is where PID tracking gets complicated)
  daemon_pid = fork do
    # The actual daemon process
    puts "Daemon process running with PID: #{Process.pid}"
    
    # Record PID for tracking
    File.write(pid_file, Process.pid.to_s)
    
    # Set up signal handler
    Signal.trap("TERM") do
      puts "Daemon received TERM signal, shutting down..."
      exit(0)
    end
    
    # Daemon work
    loop do
      sleep 1
    end
  end
  
  # The intermediate process exits immediately
  exit(0)
end

# Wait for the intermediate process to exit
Process.waitpid(daemon_pid)

# By now, the daemon should be running
sleep 2
puts "Daemon should be running now."
puts "PID file shows: #{File.read(pid_file).strip}" if File.exist?(pid_file)

# Try to find the daemon using ps
daemon_output = `ps aux | grep -v grep | grep "Daemon process running"`
puts "\nActual running daemon process:"
puts daemon_output

# Show process tree (might show init/systemd as parent)
puts "\nProcess tree (daemon should now be parented by init/PID 1):"
puts `ps -o pid,ppid,cmd -f | grep -v grep | grep -E "PID|ruby"`

puts "\nWith traditional PID tracking, there are issues:"
puts "1. The PID returned by the first fork isn't the daemon's actual PID"
puts "2. The daemon's parent is now init/PID 1, not the original parent"
puts "3. If you're tracking with a PID file, you miss the transition period"

# Try to terminate the daemon using the PID file
puts "\nAttempting to terminate the daemon using the PID from the file..."
daemon_pid = File.read(pid_file).to_i
Process.kill("TERM", daemon_pid) rescue puts "Failed to send signal to PID #{daemon_pid}"

sleep 1
puts "Checking if the daemon is still running..."
daemon_output = `ps aux | grep -v grep | grep "Daemon process running"`
if daemon_output.empty?
  puts "The daemon has been terminated successfully"
else
  puts "The daemon is still running!"
  puts daemon_output
end

puts "\nWith pidfd, you could maintain a valid reference to the daemon process"
puts "even after double-forking, and reliably signal or wait on it."

# Clean up
Process.kill("TERM", daemon_pid) rescue nil
File.unlink(pid_file) rescue nil