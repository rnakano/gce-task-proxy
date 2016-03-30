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
  end

  class InstancePool
    def pop(task)
      Instance.new
    end

    def push(instance)
    end
  end
end

GCETaskProxy.new.run_task(GCETaskProxy::Task.new)
