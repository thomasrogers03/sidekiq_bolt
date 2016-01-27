module Sidekiq
  module Bolt
    class Fetch
      UnitOfWork = Struct.new(:queue, :resource_name, :job) do
        alias :queue_name :queue
        alias :message :job

        def acknowledge
          force_acknowledge unless resource_name == Resource::ASYNC_LOCAL_RESOURCE
        end

        def force_acknowledge
          resource.free(queue, job)
          Fetch.processor_allocator.free(1, resource.type) if Fetch.processor_allocator
        end

        def requeue
          resource.add_work(queue, job)
          acknowledge
        end

        private

        def resource
          @resource ||= Resource.new(resource_name)
        end

      end
    end
  end
end
