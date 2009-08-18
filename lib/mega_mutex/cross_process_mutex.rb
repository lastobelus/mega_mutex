require 'logging'
require 'memcache'

module MegaMutex
  class TimeoutError < Exception; end

  class CrossProcessMutex

    class Configuration
      attr_accessor :memcache_servers

      def initialize
        @memcache_servers = 'localhost'
      end
    end

    class << self
      def configure
        yield configuration
      end

      def configuration
        @configuration ||= Configuration.new
      end
    end
    
    def initialize(key, timeout = nil)
      @key = key
      @timeout = timeout
    end

    def logger
      Logging::Logger[self]
    end

    def run(&block)
      @start_time = Time.now
      log "Attempting to lock cross-process mutex..."
      lock!
      log "Locked. Running critical section..."
      yield
      log "Critical section complete. Unlocking..."
    ensure
      unlock!
      log "Unlocking Mutex."
    end
    
  private
  
    def timeout?
      return false unless @timeout
      Time.now > @start_time + @timeout
    end
  
    def log(message)
      logger.debug do
        "(key:#{@key}) (lock_id:#{my_lock_id}) #{message}"
      end
    end

    def lock!
      until timeout?
        return if attempt_to_lock == my_lock_id
        sleep 0.1
      end
      raise TimeoutError.new("Failed to obtain a lock within #{@timeout} seconds.")
    end
    
    def attempt_to_lock
      if current_lock.nil?
        set_current_lock my_lock_id
      end
      current_lock
    end
    
    def unlock!
      cache.delete(@key) if locked_by_me?
    end
    
    def locked_by_me?
      current_lock == my_lock_id
    end
    
    def current_lock
      cache.get(@key)
    end
    
    def set_current_lock(new_lock)
      cache.add(@key, my_lock_id)      
    end
    
    def my_lock_id
      @my_lock_id ||= "#{Process.pid.to_s}.#{self.object_id.to_s}.#{Time.now.to_i.to_s}"
    end

    def cache
      @cache ||= MemCache.new self.class.configuration.memcache_servers, :namespace => 'mega_mutex'
    end
  end
end