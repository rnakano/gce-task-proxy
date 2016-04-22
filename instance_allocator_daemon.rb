require 'socket'
require 'thread'
require_relative 'gce'
require_relative 'stack'

include GoogleComputeEngine

class InstanceAllocatorDaemon
  def initialize(port: 5005, cli: CLI.new)
    @port = port
    @cli = cli
  end

  def load_initial_queue
    @idle_instances = Stack.new

    instances = Instance.list(@cli).select { |instance| owned_instance?(instance) }
    instances.each do |instance|
      @idle_instances.push(instance)
    end
  end

  def sweep_instances
    puts "sweep instances..."

    instances = []
    instances = @idle_instances.pop_all

    tids = instances.map do |instance|
      Thread.start(instance) do |instance|
        begin
          instance.stop!
        ensure
          @idle_instances.push(instance)
        end
      end
    end

    tids.each(&:join)
    puts "end sweep instances"
  end

  def start_instance_sweeper
    Thread.start do
      while true
        sweep_instances
        sleep(60 * 2)
      end
    end
  end

  def start
    load_initial_queue
    start_instance_sweeper
    server = TCPServer.open(@port)
    
    while true
      puts "wait command"
      Thread.start(server.accept) do |socket|
        exec(socket)
      end
    end
  end

  def exec(socket)
    line = socket.gets
    line.chomp!
    
    if line =~ /allocate/
      allocate(socket)
    elsif line =~ /free (.+)/
      name = $1
      free(socket, name)
    end

    socket.close
  end

  def allocate(socket)
    instance = @idle_instances.pop
    puts "allocate #{ instance.name }"
    instance.start!
    socket.puts(instance.name)
  end

  def free(socket, name)
    instance = Instance.new({ 'name' => name, 'status' => 'TERMINATED' }, @cli)
    puts "free #{ instance.name }"
    @idle_instances.push(instance)
  end

  def find_owned_instances
    instances = Instance.list(@cli).select { |instance| owned_instance?(instance) }
  end

  def owned_instance?(instance)
    # TODO: put this condition into config file
    instance.name =~ /^gce-task-proxy-node/
  end
end


InstanceAllocatorDaemon.new.start
