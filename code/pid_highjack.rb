#!/usr/bin/env ruby

# This program demonstrates the race condition between a "library" and the main program
# when it comes to reaping child processes.

# Simulated "library" that spawns and tracks child processes
module DemoLibrary
  def self.do_work
    pid = fork do
      sleep 1
      exit 42
    end
    pid
  end

  def self.check_result(pid)
    puts "\nLIBRARY: Checking status of child PID #{pid}..."

    begin
      waited_pid, status = Process.waitpid2(pid)
      puts "LIBRARY: Successfully reaped PID #{waited_pid} with exit code #{status.exitstatus}"
      return status
    rescue Errno::ECHILD
      puts "LIBRARY: ERROR - Child PID #{pid} was already reaped by someone else!"
      return nil
    end
  end
end

# Setup: main program installs a SIGCHLD handler to reap any exiting children
puts "\n=== SETUP: Installing SIGCHLD handler in main program ==="
Signal.trap(:CHLD) do
  begin
    pid, status = Process.waitpid2(-1, Process::WNOHANG)
    if pid
      puts "MAIN: Signal handler reaped child PID #{pid} (exit code: #{status.exitstatus})"
    end
  rescue Errno::ECHILD
    # No children left to reap
  end
end

# Run the race condition demonstration
def demonstrate_race_condition
  puts "\n=== DEMO: With signal handler installed ==="
  puts "Spawning a child process via the library..."

  pid = DemoLibrary.do_work
  puts "MAIN: Library spawned child PID #{pid}"
  puts "MAIN: Waiting for child to exit (approximately 1 second)..."

  sleep 2

  result = DemoLibrary.check_result(pid)

  if result.nil?
    puts "\nRACE CONDITION DEMONSTRATED:"
    puts "The main program reaped the child before the library could."
    puts "This makes libraries unreliable when managing their own child processes."
  else
    puts "\nNo race occurred this time — the library successfully retrieved the exit status."
  end
end

demonstrate_race_condition

exit

# Show correct behavior without the SIGCHLD handler
puts "\n\n=== DEMO 2: Without main program interference ==="
puts "Resetting SIGCHLD handler to default..."

Signal.trap(:CHLD, "DEFAULT")

pid = DemoLibrary.do_work
puts "MAIN: Library spawned child PID #{pid}"
puts "MAIN: Waiting for child to exit..."

sleep 2

result = DemoLibrary.check_result(pid)

if result
  puts "\nSUCCESS: Without interference, the library retrieved the exit code as expected."
else
  puts "\nUNEXPECTED: The library failed to retrieve the exit code (this should not happen here)."
end

puts "\n=== END OF DEMO ==="
