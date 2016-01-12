module Sidekiq
  module Bolt
    class Poller
      ROOT = File.dirname(__FILE__)
      SCRIPT_ROOT = ROOT + '/' + File.basename(__FILE__, '.rb')
      POLL_SCRIPT_PATH = "#{SCRIPT_ROOT}/poll.lua"
      POLL_SCRIPT = File.read(POLL_SCRIPT_PATH)
      NAMESPACE_KEY = [''].freeze

      def initialize
        @enq = Scheduled::Enq.new
      end

      def enqueue_jobs
        @enq.enqueue_jobs
        {retry: 'retrying:', scheduled: ''}.each do |set, prefix|
          Bolt.redis do |redis|
            redis.eval(POLL_SCRIPT, keys: NAMESPACE_KEY, argv: ["bolt:#{set}", prefix, Time.now.to_f])
          end
        end
      end
    end
  end
end