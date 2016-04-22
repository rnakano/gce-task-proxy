require 'socket'
require 'optparse'
require_relative 'gce'

include GoogleComputeEngine

class TaskRunner
  
  def initialize
    params = ARGV.getopts('w:t:a:')
    p params
    @task = Task.new(params['w'], params['t'], File.read(params['a']).chomp.split('\n'))
  end

  def run
    run_task(@task)
  end

  def allocate_instance
    sock = TCPSocket.open('localhost', 5005)
    sock.puts('allocate')
    instance_name = sock.gets.chomp
    sock.close
    cli = CLI.new
    Instance.new({ 'name' => instance_name, 'status' => 'TERMINATED' }, cli)
  end

  def free_instance(instance)
    sock = TCPSocket.open('localhost', 5005)
    sock.puts("free #{ instance.name }")
    sock.close
  end

  def run_task(task)
    retry_count = 0

    begin
      instance = allocate_instance
      puts "Allocate #{ instance.name }"
      result = instance.run_task(task)
    rescue InstanceTerminatedError => e
      puts "Instance terminated while running task. retrying..."
      free_instance(instance)
      retry_count += 1
      if retry_count > 5
        puts "Too many retry. aborting"
        return 1
      end
      retry
    ensure
      free_instance(instance)
    end

    result
  end
end

