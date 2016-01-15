module Sidekiq
  module Bolt
    class Scheduler

      NAMESPACE_KEY = [''].freeze
      ROOT = File.dirname(__FILE__)
      SCRIPT_ROOT = ROOT + '/' + File.basename(__FILE__, '.rb')
      SCHEDULE_SCRIPT_PATH = "#{SCRIPT_ROOT}/schedule.lua"
      SCHEDULE_SCRIPT = File.read(SCHEDULE_SCRIPT_PATH)

      def initialize(prev_job)
        @prev_job_id = prev_job['jid']
        @items = []
      end

      def perform_after(worker_class, *args)
        new_job = {
            'class' => worker_class.to_s,
            'jid' => SecureRandom.base64(16),
            'queue' => 'default',
            'resource' => 'default',
            'args' => args,
            'retry' => true
        }.merge(worker_class.get_sidekiq_options)
        serialized_job = Sidekiq.dump_json(new_job)
        items.concat [new_job['queue'], new_job['resource'], serialized_job]
      end

      def schedule!
        Bolt.redis do |redis|
          redis.eval(SCHEDULE_SCRIPT, keys: NAMESPACE_KEY, argv: [prev_job_id, *items])
        end
      end

      private

      attr_reader :prev_job_id, :items

    end
  end
end