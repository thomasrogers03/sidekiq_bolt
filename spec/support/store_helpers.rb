module RedisHelpers
  extend RSpec::Core::SharedContext

  let(:redis_host) { 'redis.dev' }
  let(:global_namespace) { :bolt }
  let(:global_redis_db) { 13 }
  let(:global_redis_conn) { Redis.new(host: redis_host, db: global_redis_db) }
  let(:global_redis) { Redis::Namespace.new(global_namespace, redis: global_redis_conn) }
  let(:alternate_namespace) { :thunder }
  let(:alternate_redis_conn) { Redis.new(host: redis_host, db: global_redis_db) }
  let(:alternate_redis) { Redis::Namespace.new(alternate_namespace, redis: alternate_redis_conn) }
  let(:sidekiq_redis_options) { {url: 'redis://redis.dev/13', namespace: :bolt} }

  before do
    Sidekiq.redis = sidekiq_redis_options
    global_redis_conn.script(:kill) rescue nil
    keys = global_redis_conn.keys
    global_redis_conn.pipelined do
      keys.each { |key| global_redis_conn.del(key) }
    end
    allow_any_instance_of(Redis).to receive(:subscribe)
  end
end
