module Sidekiq
  module Bolt
    class PersistentResource < Struct.new(:name)

      NAMESPACE_KEY = [''].freeze
      ROOT = File.dirname(__FILE__)
      SCRIPT_ROOT = ROOT + '/' + File.basename(__FILE__, '.rb')
      ALLOCATE_SCRIPT_PATH = "#{SCRIPT_ROOT}/alloc.lua"
      ALLOCATE_SCRIPT = File.read(ALLOCATE_SCRIPT_PATH)

      def create(resource)
        Bolt.redis do |redis|
          redis.zadd("resources:persistent:#{name}", '-INF', resource)
          resource
        end
      end

      def allocate
        Bolt.redis do |redis|
          redis.eval(ALLOCATE_SCRIPT, keys: NAMESPACE_KEY, argv: [name])
        end
      end

    end
  end
end
