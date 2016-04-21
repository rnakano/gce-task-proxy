require 'shellwords'
require 'json'
require 'fileutils'

module GoogleComputeEngine
  class InstanceTerminatedError < StandardError; end

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
          elsif line.chomp =~ /Timeout.+not responding.$/
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
      ret = @cli.gcloud_ssh_command(name, "mkdir -p #{ task.workspace } && cd #{ task.workspace } && /bin/bash -xe #{ remote_path }")
      get_artifacts(task)
      ret
    end

    def get_artifacts(task)
      puts 'gathering artifacts...'
      list = task.artifacts
      artifacts_path = '.artifacts'
      command = "cd #{ task.workspace } && rm -rf #{ artifacts_path } && mkdir -p #{ artifacts_path } && " +
        list.map { |path| "find -wholename '#{ path }' -exec cp --parents {} #{ artifacts_path } \\;" }.join('&&')
      @cli.gcloud_ssh_command(name, command)
      
      FileUtils.rm_rf('artifacts')
      FileUtils.mkdir_p('artifacts')
      @cli.gcloud('compute', 'copy-files', name + ':' + task.workspace + '/' + artifacts_path, 'artifacts')
    end
  end

  class Task
    def initialize(workspace, script_path, artifacts)
      @script_path = script_path
      @artifacts = artifacts
      @workspace = workspace
    end

    attr_reader :script_path, :artifacts, :workspace
  end
end
