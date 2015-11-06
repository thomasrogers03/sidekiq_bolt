module Sidekiq
  module Bolt
    class Resource < Struct.new(:name)
      extend PropertyList

      ROOT = File.dirname(__FILE__)
      SCRIPT_ROOT = ROOT + '/' + File.basename(__FILE__, '.rb')
      ALLOCATE_SCRIPT_PATH = "#{SCRIPT_ROOT}/alloc.lua"
      ALLOCATE_SCRIPT = File.read(ALLOCATE_SCRIPT_PATH)
      ADD_WORK_SCRIPT_PATH = "#{SCRIPT_ROOT}/add_work.lua"
      ADD_WORK_SCRIPT = File.read(ADD_WORK_SCRIPT_PATH)
      SIZE_SCRIPT_PATH = "#{SCRIPT_ROOT}/size.lua"
      SIZE_SCRIPT = File.read(SIZE_SCRIPT_PATH)
      FREE_SCRIPT_PATH = "#{SCRIPT_ROOT}/free.lua"
      FREE_SCRIPT = File.read(FREE_SCRIPT_PATH)

      define_property 'resource:type', :type
      define_property 'resource:limit', :limit, :int

      def self.all
        Bolt.redis { |redis| redis.smembers('resources') }.map { |name| new(name) }
      end

      def frozen=(value)
        Bolt.redis do |redis|
          if value
            redis.set("resource:frozen:#{name}", 1)
          else
            redis.del("resource:frozen:#{name}")
          end
        end
      end

      def frozen
        Bolt.redis { |redis| !!redis.get("resource:frozen:#{name}") }
      end

      def allocated
        Bolt.redis { |redis| redis.get(allocated_key).to_i }
      end

      def queues
        Bolt.redis { |redis| redis.smembers("resource:queues:#{name}") }
      end

      def size
        Bolt.redis do |redis|
          redis.eval(SIZE_SCRIPT, keys: [''], argv: [name])
        end
      end

      def add_work(queue, work)
        Bolt.redis do |redis|
          redis.eval(ADD_WORK_SCRIPT, keys: [''], argv: [queue, name, work])
        end
      end

      def allocate(amount)
        Bolt.redis do |redis|
          redis.eval(ALLOCATE_SCRIPT, keys: [''], argv: [name, amount, *queues.shuffle])
        end
      end

      def free(queue)
        Bolt.redis do |redis|
          redis.eval(FREE_SCRIPT, keys: [''], argv: [queue, name])
        end
      end

      private

      def allocated_key
        "resource:allocated:#{name}"
      end

    end
  end
end
