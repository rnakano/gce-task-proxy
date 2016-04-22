require 'thread'

class Stack
  def initialize
    @arr = []
    @mutex = Mutex.new
  end

  def push(obj)
    @mutex.synchronize do
      @arr.push(obj)
    end
  end

  def pop
    @mutex.synchronize do
      @arr.pop
    end
  end

  def pop_all
    @mutex.synchronize do
      arr = @arr
      @arr = []
      return arr.reverse
    end
  end
end
