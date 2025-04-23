#!/usr/bin/env ruby

# This demo shows how zombies can accumulate when using PID-based process management

puts "DEMO: Zombie Process Accumulation"
puts "================================="

# Create a bunch of child processes that exit immediately
puts "Creating 10 child processes that will become zombies..."

child_pids = []
10.times do |i|
  pid = fork do
    puts "Child #{i+1} (PID: #{Process.pid}) exiting immediately"
    exit(0)
  end
  
  child_pids << pid
  sleep 0.1
end

# Show zombie processes
puts "\nListing zombie processes (note the 'Z' state):"
system("ps -o pid,ppid,stat,cmd -p #{child_pids.join(',')}")

puts "\nThese processes are in 'zombie' state because the parent hasn't reaped them."
puts "In long-running applications, these can accumulate and potentially waste resources."

# Demonstrate orphan creation
puts "\nNow let's create an orphan process (will be adopted by init/PID 1):"
orphan_pid = fork do
  # Grandchild that outlives its parent
  puts "Grandchild process #{Process.pid} created"
  sleep 10
end

# Fork again, creating a parent that dies before its child
fork do
  puts "Middle process #{Process.pid} created, has child #{orphan_pid}"
  puts "Middle process exiting immediately, orphaning its child"
  exit(0)
end

sleep 2

puts "\nThe process hierarchy now looks like:"
system("ps f -o pid,ppid,stat,cmd | grep -v grep | grep -E '(#{orphan_pid}|ruby)'")

puts "\nWhen using PIDs for tracking, orphaned processes can be difficult to manage"
puts "because the original parent-child relationship is lost."

# Finally, clean up by waiting for all the zombies
puts "\nCleaning up zombie processes..."
child_pids.each do |pid|
  Process.waitpid(pid, Process::WNOHANG)
end

puts "Demo complete. In a real application, these issues would need to be carefully handled."