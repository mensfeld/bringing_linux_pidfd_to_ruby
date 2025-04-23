#!/usr/bin/env ruby
# demo_orphan_detection.rb

require 'karafka'

puts "Starting orphan detection demo"
puts "Parent PID: #{Process.pid}"

# Fork a child process that will monitor its parent
child_pid = fork do
  begin
    child_pid = Process.pid
    parent_pid = Process.ppid

    puts "[Child #{child_pid}] I'm monitoring parent (#{parent_pid})"

    # Create a pidfd for the parent process
    parent_pidfd = Karafka::Swarm::Pidfd.new(parent_pid)

    # Monitor loop
    loop do
      if parent_pidfd.alive?
        puts "[Child #{child_pid}] Parent is alive, sleeping for 5 seconds..."
        sleep 5
      else
        puts "[Child #{child_pid}] DETECTED: Parent is dead!"
        puts "[Child #{child_pid}] Cleaning up resources and exiting..."
        parent_pidfd.cleanup

        exit(0)
      end
    end
  rescue => e
    puts "[Child #{child_pid}] Error: #{e.message}"
    puts e.backtrace
    exit(1)
  end
end

puts "Child process started with PID: #{child_pid}"

sleep
