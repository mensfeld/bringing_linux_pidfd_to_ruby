#!/usr/bin/env ruby

puts "=== PID-based Monitoring Limitations Demo ==="
puts "This demo shows how monitoring systems can get confused with PID-based tracking"

# Create a simple monitoring system class
class PidMonitor
  def initialize
    @processes = {}
    @stats = {}
  end
  
  def register(name, pid)
    @processes[name] = pid
    @stats[name] = { start_time: Time.now, cpu_samples: [] }
    puts "Monitoring: #{name} (PID: #{pid})"
  end
  
  def sample
    @processes.each do |name, pid|
      begin
        # Get CPU usage using ps (simplified)
        cpu = `ps -p #{pid} -o %cpu`.lines.last.to_f rescue nil
        
        if cpu
          @stats[name][:cpu_samples] << cpu
          puts "#{name} (PID: #{pid}): #{cpu}% CPU"
        else
          puts "#{name} (PID: #{pid}): Process not found!"
        end
      rescue => e
        puts "Error monitoring #{name}: #{e.message}"
      end
    end
  end
  
  def report
    puts "\nMonitoring Report:"
    @processes.each do |name, pid|
      samples = @stats[name][:cpu_samples]
      if samples.any?
        avg = samples.sum / samples.size
        puts "#{name} (PID: #{pid}): Avg CPU: #{avg.round(2)}% over #{samples.size} samples"
      else
        puts "#{name} (PID: #{pid}): No samples collected"
      end
    end
  end
end

# Create our monitor
monitor = PidMonitor.new

# Start a CPU-intensive "database" process
db_pid = fork do
  puts "Database process started with PID: #{Process.pid}"
  puts "Running CPU-intensive workload..."
  
  # Simulate CPU-intensive work
  5.times do
    start = Time.now
    while Time.now - start < 0.5
      # Busy loop to consume CPU
      Math.sqrt(rand) * Math.log(rand) * Math.sin(rand) 
    end
    sleep 0.2
  end
  
  puts "Database process finished normally"
  exit(0)
end

puts "Started database process with PID: #{db_pid}"
monitor.register("database", db_pid)

# Sample a few times while the database is running
3.times do
  sleep 0.8
  puts "\nTaking monitoring sample..."
  monitor.sample
end

# Wait for the database to finish
puts "\nWaiting for database process to complete..."
Process.waitpid(db_pid)
puts "Database process has exited"

# Fork a lightweight process that happens to get the same PID
puts "\nForking a new lightweight process..."

new_pid = nil
10.times do
  pid = fork do
    puts "Lightweight process started with PID: #{Process.pid}"
    sleep 10
  end
  
  if pid == db_pid
    new_pid = pid
    puts "SUCCESS: New lightweight process got the same PID (#{pid}) as the database!"
    break
  else
    Process.kill("TERM", pid) rescue nil
    Process.waitpid(pid) rescue nil
  end
end

# If we couldn't get the same PID, simulate it for the demo
unless new_pid
  puts "[DEMO MODE] Simulating PID reuse for demonstration purposes"
  puts "[DEMO MODE] Pretending new process has the database's PID: #{db_pid}"
  
  new_pid = fork do
    puts "Lightweight process with PID: #{Process.pid} (simulating PID: #{db_pid})"
    sleep 10
  end
end

# Take a few more samples
3.times do
  sleep 0.8
  puts "\nTaking monitoring sample..."
  monitor.sample
end

# Show the final report
monitor.report

puts "\nThis demonstrates how PID-based monitoring can be misleading when PIDs are recycled."
puts "The monitor thinks it's still tracking the database, but it's actually seeing data"
puts "from a completely different process."
puts "\nWith pidfd monitoring, the monitoring system would know when the original"
puts "process has exited, and wouldn't confuse it with a new process."

# Clean up
Process.kill("TERM", new_pid) rescue nil
Process.waitpid(new_pid) rescue nil