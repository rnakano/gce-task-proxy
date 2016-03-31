require 'shellwords'
require 'json'
require 'fileutils'

module GoogleComputeEngine
  class CLI
    def initialize(zone: 'asia-east1-b', gcloud_path: 'gcloud')
      @zone = zone
      @gcloud_path = gcloud_path
    end

    def gcloud(*args)
      command = @gcloud_path +
        ' ' +
        args.map { |arg| Shellwords.escape(arg) }.join(' ') +
        ' --zone ' +
        Shellwords.escape(@zone)
      ret = `#{ command }`
    end

    def gcloud_json(*args)
      command = @gcloud_path +
        ' --format json ' +
        args.map { |arg| Shellwords.escape(arg) }.join(' ') +
        ' --zone ' +
        Shellwords.escape(@zone)
      ret = `#{ command }`
      JSON.parse(ret)
    end

    def gcloud_ssh_command(name, command)
      command = @gcloud_path +
        ' compute ssh -A ' +
        Shellwords.escape(name) +
        ' --command ' +
        "'#{ command }'"
      
      pipe_broken = false
      IO.popen(command, 'r+', STDERR => [:child, STDOUT]) do |io|
        io.close_write
        while line = io.gets
          print line
          if line.chomp =~ /Broken pipe$/
            pipe_broken = true
          end
        end
      end
      result_code = $?.to_i

      if pipe_broken && result_code != 0
        raise InstanceTerminatedError.new
      end

      return result_code
    end
  end

  class Instance
    def initialize(attr, cli)
      @attr = attr
      @cli = cli
    end

    def self.list(cli)
      instance_list = cli.gcloud_json('compute', 'instances', 'list')
      instance_list.map { |attr| Instance.new(attr, cli) }
    end

    def name
      @attr['name']
    end

    def status
      @attr["status"]
    end

    def terminated?
      status == 'TERMINATED'
    end

    def running?
      status == 'RUNNING'
    end

    def start!
      return unless terminated?
      @cli.gcloud('compute', 'instances', 'start', name)
    end

    def stop!
      # work around
      begin
        @cli.gcloud_ssh_command(name, 'sudo shutdown -h now')
      rescue InstanceTerminatedError => e
        # do nothing
      end
    end

    def run_task(task)
      puts 'running task...'
      remote_path = '/tmp/gce-task-proxy-task.sh'
      @cli.gcloud('compute', 'copy-files', task.script_path, name + ':' + remote_path)
      ret = @cli.gcloud_ssh_command(name, "/bin/bash #{ remote_path }")
      get_artifacts(task.artifacts)
      ret
    end

    def get_artifacts(list)
      puts 'gathering artifacts...'
      artifacts_path = '.artifacts'
      command = "rm -rf #{ artifacts_path } && mkdir -p #{ artifacts_path } && " +
        list.map { |path| "cp --parents #{ path } #{ artifacts_path }" }.join('; ')
      @cli.gcloud_ssh_command(name, command)
      
      @cli.gcloud('compute', 'copy-files', name + ':' + artifacts_path, 'artifacts')
    end
  end

  class InstancePool
    def initialize(cli: CLI.new)
      @cli = cli
    end

    def allocate_instance(instance_index)
      instances = find_owned_instances
      instance = instances[instance_index]
      
      raise InstanceAllocationError.new("instance ##{ instance_index } is not found") unless instance

      instance.start!
      instance
    end

    def free_instance(instance)
      instance.stop!
    end

    def find_owned_instances
      Instance.list(@cli).select { |instance| owned_instance?(instance) }
    end

    def owned_instance?(instance)
      # TODO: put this condition into config file
      instance.name =~ /^test-build-/
    end
  end

  class InstanceAllocationError < StandardError; end
  class InstanceTerminatedError < StandardError; end

  class Task
    def initialize(script_path, artifacts)
      @script_path = script_path
      @artifacts = artifacts
    end

    attr_reader :script_path, :artifacts
  end

  class TaskProxy
    def self.run_task(instance_index, task)
      pool = InstancePool.new

      retry_count = 0

      begin
        instance = pool.allocate_instance(instance_index)
        result = instance.run_task(task)
      rescue InstanceTerminatedError => e
        puts "Instance terminated while running task. retrying..."
        retry_count += 1
        if retry_count > 5
          puts "Too many retry. aborting"
          return 1
        end
        retry
      rescue InstanceAllocationError => e
        puts "Cannot allocate instance. aborting"
        return 1
      end

      pool.free_instance(instance)
      result
    end
  end
end

include GoogleComputeEngine

task = Task.new('/tmp/hello_world.sh', [ '**/mapping.txt' ])
result = TaskProxy.run_task(0, task)

exit(result)

