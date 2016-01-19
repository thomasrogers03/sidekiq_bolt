module Sidekiq
  module Bolt
    module FutureWorker

      def self.included(base)
        base.send(:include, Worker)
        base.extend ClassMethods
      end

      module ClassMethods
        def perform_async(*args, &block)
          client_push({'class' => self, 'args' => args, 'resource' => '$async_local'}, &block)
        end

        def perform_async_with_options(options, *args, &block)
          #noinspection RubySuperCallWithoutSuperclassInspection
          super(options.merge(resource: '$async_local'), *args, &block)
        end

        def perform_in(*_)
          raise NotImplementedError, '.peform_in not implemented for FutureWorkers'
        end
      end

      def perform(*args)
        perform_future(*args).on_complete do |_, error|
          acknowledge_work(error)
        end
      end

    end
  end
end
