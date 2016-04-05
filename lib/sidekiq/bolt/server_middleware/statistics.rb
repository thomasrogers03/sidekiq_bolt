module Sidekiq
  module Bolt
    module ServerMiddleware
      class Statistics
        include Scripts

        ROOT = File.dirname(__FILE__)
        SCRIPT_ROOT = ROOT + '/' + File.basename(__FILE__, '.rb')
        COUNT_STATS_SCRIPT_PATH = "#{SCRIPT_ROOT}/stats.lua"
        COUNT_STATS_SCRIPT = File.read(COUNT_STATS_SCRIPT_PATH)
        NAMESPACE_KEY = [''].freeze

        def call(_, job, _)
          ThomasUtils::Future.immediate do
            yield
          end.on_success_ensure do
            run_script(:stats_count, COUNT_STATS_SCRIPT, NAMESPACE_KEY, [job['resource'], job['queue']])
          end.fallback do |error|
            run_script(:stats_count, COUNT_STATS_SCRIPT, NAMESPACE_KEY, [job['resource'], job['queue'], true])
            ThomasUtils::Future.error(error)
          end
        end

      end
    end
  end
end
