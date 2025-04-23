#!/usr/bin/env ruby
require 'fileutils'

TMPDIR = "/tmp/pid_reuse_false_data_demo"
FileUtils.rm_rf(TMPDIR)
FileUtils.mkdir_p(TMPDIR)

pidfile   = "#{TMPDIR}/trusted_pid"
dumpfile  = "#{TMPDIR}/memdump.log"
marker    = "#{TMPDIR}/attacker_ready"

puts "\n[*] Step 1: Starting trusted daemon..."

trusted_pid = fork do
  trap("USR1") do
    puts "[trusted] Dumping real memory to #{dumpfile}"
    File.write(dumpfile, "REAL_DUMP: WARNING! anomalies detected!\n")
  end

  File.write(pidfile, Process.pid.to_s)
  puts "[trusted] Running with PID #{Process.pid}"
  sleep 10
end

sleep 1 # Allow it to start
puts "[*] Trusted process running with PID #{trusted_pid}"
sleep 2

puts "\n[*] Step 2: Killing the trusted process..."
Process.kill("TERM", trusted_pid)
Process.wait(trusted_pid)
puts "[*] Trusted process terminated."

# Reuse attempt
target_pid = File.read(pidfile).to_i
puts "[*] Attempting to reuse PID #{target_pid}..."

max_attempts = 20000
success = false

attacker_pid = nil

max_attempts.times do |i|
  pid = fork do
    if Process.pid == target_pid
      puts "[attacker] Successfully reused PID #{Process.pid}!"
      File.write(marker, Process.pid.to_s)

      trap("USR1") do
        puts "[attacker] Received SIGUSR1 — faking memory dump!"
        File.write(dumpfile, "FAKE_DUMP: No anomalies detected\n")
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
  puts "\n[*] Step 3: Sending SIGUSR1 to PID #{attacker_pid} (expecting a dump)..."
  sleep 1

  begin
    Process.kill("USR1", attacker_pid)
  rescue Errno::ESRCH
    puts "[!] Error: Attacker process already exited"
  end

  sleep 1
  if File.exist?(dumpfile)
    puts "[*] Step 4: Read memory dump:"
    puts "----------------------------------"
    puts File.read(dumpfile)
    puts "----------------------------------"
  else
    puts "[!] No dumpfile found!"
  end
else
  puts "[!] Could not reuse PID after #{max_attempts} attempts."
end

puts "\n[*] Cleanup"
FileUtils.rm_rf(TMPDIR)
