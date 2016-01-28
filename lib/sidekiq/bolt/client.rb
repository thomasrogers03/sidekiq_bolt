module Sidekiq
  module Bolt
    class Client < Sidekiq::Client

      NAMESPACE_KEY = [''].freeze
      ROOT = File.dirname(__FILE__)
      SCRIPT_ROOT = ROOT + '/' + File.basename(__FILE__, '.rb')
      BACKUP_WORK_SCRIPT_PATH = "#{SCRIPT_ROOT}/backup.lua"
      BACKUP_WORK_DEPENDENCY_SCRIPT = File.read(BACKUP_WORK_SCRIPT_PATH)

      def skeleton_push(item)
        queue_name = item['queue']
        resource_name = item['resource']
        work = Sidekiq.dump_json(item)
        if item['resource'] == Resource::ASYNC_LOCAL_RESOURCE
          backup_work(item, work)
          run_work_now(item, queue_name)
        else
          queue = Queue.new(queue_name)
          queue.enqueue(resource_name, work, !!item['error'])
        end
      end

      private

      def raw_push(payloads)
        @redis_pool.with do |conn|
          atomic_push(conn, payloads)
        end
        true
      end

      def atomic_push(_, payloads)
        if payloads.first['at']
          payloads.each { |item| item['sk'] = 'bolt' }
          return super
        end

        now = Time.now.to_f
        payloads.each do |entry|
          entry['resource'] ||= 'default'
          entry['enqueued_at'.freeze] = now
          skeleton_push(entry)
        end
      end

      def backup_work(item, work)
        argv = [item['queue'], Resource::ASYNC_LOCAL_RESOURCE, work, Socket.gethostname]
        Bolt.redis do |redis|
          redis.eval(BACKUP_WORK_DEPENDENCY_SCRIPT, keys: NAMESPACE_KEY, argv: argv)
        end
      end

      def run_work_now(item, queue_name)
        worker = item['class'].constantize.new
        Sidekiq.server_middleware.invoke(worker, item, queue_name) do
          worker.perform(*item['args'])
        end
      end

    end
  end

  class Client
    def self.push(item)
      (item['sk'] == 'bolt' ? Bolt::Client : self).new.push(item)
    end
  end

end
