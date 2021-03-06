module Sidekiq
  module Bolt
    class PersistentResource < Struct.new(:name)
      include Sidekiq::Util

      NAMESPACE_KEY = [''].freeze
      ROOT = File.dirname(__FILE__)
      SCRIPT_ROOT = ROOT + '/' + File.basename(__FILE__, '.rb')
      ALLOCATE_SCRIPT_PATH = "#{SCRIPT_ROOT}/alloc.lua"
      ALLOCATE_SCRIPT = File.read(ALLOCATE_SCRIPT_PATH)
      FREE_SCRIPT_PATH = "#{SCRIPT_ROOT}/free.lua"
      FREE_SCRIPT = File.read(FREE_SCRIPT_PATH)
      DESTROY_SCRIPT_PATH = "#{SCRIPT_ROOT}/destroy.lua"
      DESTROY_SCRIPT = File.read(DESTROY_SCRIPT_PATH)

      def initialize(name, redis_pool = nil)
        @redis_pool = redis_pool
        super(name)
      end

      def create(resource)
        redis do |redis|
          redis.zadd("resources:persistent:#{name}", '-INF', resource)
          resource
        end
      end

      def size
        redis { |redis| redis.zcard("resources:persistent:#{name}") }
      end

      def destroy(resource)
        redis do |redis|
          redis.eval(DESTROY_SCRIPT, keys: NAMESPACE_KEY, argv: [name, resource, identity])
          resource
        end
      end

      def allocate
        result = redis do |redis|
          redis.eval(ALLOCATE_SCRIPT, keys: NAMESPACE_KEY, argv: [name, identity])
        end
        if result.any?
          result[1] = result[1].to_f unless result[1].include?('inf')
          result
        end
      end

      def free(resource, score)
        redis do |redis|
          redis.eval(FREE_SCRIPT, keys: NAMESPACE_KEY, argv: [name, resource, score, identity])
        end
      end

      private

      def redis(&block)
        @redis_pool ? @redis_pool.with(&block) : Bolt.redis(&block)
      end

    end
  end
end
