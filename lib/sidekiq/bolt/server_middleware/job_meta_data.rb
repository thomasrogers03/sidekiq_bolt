module Sidekiq
  module Bolt
    module ServerMiddleware
      class JobMetaData

        def call(worker, job, _)
          worker.queue = Queue.new(job['queue'])
          worker.resource = Resource.new(job['resource'])
          worker.jid = job['jid']
          worker.parent_job_id = job['pjid']
          worker.original_message = Sidekiq.dump_json(job)
          worker.child_scheduler = ChildScheduler.new(job)
          result = yield
          worker.child_scheduler.schedule!
          result
        end

      end
    end
  end
end
