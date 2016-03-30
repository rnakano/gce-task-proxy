class GCETaskProxy
  def initialize
    @instance_pool = InstancePool.new
  end

  def run_task(task)
    instance = @instance_pool.pop(task)
    instance.run_task(task)
    @instance_pool.push(instance)
  end

  class Task
  end

  class Instance
    def run_task(task)
    end

    def mark_busy!
    end

    def mark_idle!
    end

    def start!
    end
  end

  class InstancePool
    def find_idle_instances
      # call gcloud command
      
      # filter busy instances
      []
    end

    def find_stopped_instances
      [ Instance.new ]
    end

    def create_instance
      Instance.new
    end

    def with_lock(&block)
      yield
    end

    def pop(task)
      with_lock do
        idle_instances = find_idle_instances
        unless idle_instances.empty?
          instance = idle_instances.first
          instance.mark_busy!
          return instance
        end
      end

      instance = nil
      with_lock do
        instance = pick_stopped_instance
      end

      instance.start!
      instance
    end

    def pick_stopped_instance
      stopped_instances = find_stopped_instances
      unless stopped_instances.empty?
        instance = stopped_instances.first
        instance.mark_busy!
        return instance
      end

      raise RetryError.new
    end

    def push(instance)
      instance.mark_idle!
    end
  end

  class RetryError < StandardError; end
end

GCETaskProxy.new.run_task(GCETaskProxy::Task.new)
