require 'rspec'

module Sidekiq
  module Bolt
    describe Worker do

      class MockWorker
        include Worker
      end

      class MockWorkerTwo
        include Worker
        RESOURCE_NAME = Faker::Lorem.word
        sidekiq_options resource: RESOURCE_NAME
      end

      class MockWorkerThree
        include Worker
        QUEUE_NAME = Faker::Lorem.word
        sidekiq_options queue: QUEUE_NAME
      end

      class MockWorkerFour
        include Worker
        JOB_NAME = Faker::Lorem.word
        sidekiq_options job: JOB_NAME
      end

      let(:args) { Faker::Lorem.paragraphs }
      let(:queue_name) { 'default' }
      let(:resource_name) { 'default' }
      let(:resource) { Resource.new(resource_name) }
      let(:result_work) { work_klass.from_allocation(resource_name, resource.allocate(1)) }
      let(:result_item) { Sidekiq.load_json(result_work.work) }
      let(:klass) { MockWorker }
      let(:scheduler_class) do
        Struct.new(:job) do
          def schedule!

          end
        end
      end
      let(:sidekiq_options) { {concurrency: 0} }

      subject { klass.new }

      before do
        allow(Scheduler).to receive(:new) do |job|
          scheduler_class.new(job)
        end
      end

      it { is_expected.to be_a_kind_of(Sidekiq::Worker) }

      describe '#queue' do
        let(:queue_name) { Faker::Lorem }
        let(:queue) { Queue.new(queue_name) }
        before { subject.queue = queue }
        its(:queue) { is_expected.to eq(queue) }
      end

      describe '#resource' do
        let(:resource_name) { Faker::Lorem }
        before { subject.resource = resource }
        its(:resource) { is_expected.to eq(resource) }
      end

      describe '#original_message' do
        let(:original_message) { SecureRandom.uuid }
        before { subject.original_message = original_message }
        its(:original_message) { is_expected.to eq(original_message) }
      end

      describe '#parent_job_id' do
        let(:jid) { SecureRandom.uuid }
        before { subject.parent_job_id = jid }
        its(:parent_job_id) { is_expected.to eq(jid) }
      end

      describe '#resource_allocation' do
        let(:resource_allocation) { rand(1..100) }
        before { subject.resource_allocation = resource_allocation }
        its(:resource_allocation) { is_expected.to eq(resource_allocation) }
      end

      describe '#child_scheduler' do
        let(:child_scheduler) { ChildScheduler.new('jid' => SecureRandom.uuid) }
        before { subject.child_scheduler = child_scheduler }
        its(:child_scheduler) { is_expected.to eq(child_scheduler) }
      end

      describe '.sidekiq_should_retry?' do
        let(:some_value) { Faker::Lorem.word }
        let(:retry_block) { ->() { some_value } }
        let(:klass) do
          block = retry_block
          Class.new do
            include Worker
            sidekiq_should_retry?(&block)
          end
        end

        it 'should set the sidekiq_should_retry_block for this worker' do
          expect(subject.sidekiq_should_retry_block.call).to eq(some_value)
        end
      end

      describe '.sidekiq_freeze_resource_after_retry_for' do
        let(:some_value) { Faker::Lorem.word }
        let(:retry_block) { ->() { some_value } }
        let(:klass) do
          block = retry_block
          Class.new do
            include Worker
            sidekiq_freeze_resource_after_retry_for(&block)
          end
        end

        it 'should set the sidekiq_freeze_resource_after_retry_for_block for this worker' do
          expect(subject.sidekiq_freeze_resource_after_retry_for_block.call).to eq(some_value)
        end
      end

      describe '.perform_async' do
        let(:queue) { Queue.new(queue_name) }
        let(:result_jid) { result_item['jid'] }
        let(:result_parent_job_id) { result_item['pjid'] }
        let(:result_queue_job) { queue.job }
        let(:expected_jid) { SecureRandom.base64(16) }
        let(:expected_parent_job_id) { result_item['queue'] }
        let(:block) { nil }

        before do
          allow(SecureRandom).to receive(:base64).with(16).and_return(expected_jid)
        end

        it 'should return the new job id' do
          expect(klass.perform_async(*args)).to eq(result_jid)
        end

        describe 'enqueuing the job' do
          before { klass.perform_async(*args, &block) }

          it 'should enqueue the work to the default queue/resource' do
            expect(result_item).to include('queue' => queue_name, 'resource' => resource_name, 'class' => 'Sidekiq::Bolt::MockWorker', 'args' => args)
          end

          it 'should serialize a Message' do
            expect(result_item).to be_a_kind_of(Message)
          end

          it 'should generate a job id for this work' do
            expect(result_jid).to eq(expected_jid)
          end

          context 'with an overridden queue name' do
            let(:klass) { MockWorkerThree }
            let(:queue_name) { MockWorkerThree::QUEUE_NAME }

            it 'should set parent job id to the queue' do
              expect(result_parent_job_id).to eq(expected_parent_job_id)
            end
          end

          it 'does not associate the job with the queue' do
            expect(result_queue_job).to be_nil
          end

          context 'with a job name provided' do
            let(:klass) { MockWorkerFour }
            let(:job_name) { MockWorkerFour::JOB_NAME }

            it 'associates the job with the queue' do
              expect(result_queue_job).to eq(Job.new(job_name))
            end
          end

          context 'with an overridden resource name' do
            let(:klass) { MockWorkerTwo }
            let(:resource_name) { MockWorkerTwo::RESOURCE_NAME }

            it 'should enqueue the work to the specified resource' do
              expect(result_item).to include('queue' => queue_name, 'resource' => resource_name, 'class' => 'Sidekiq::Bolt::MockWorkerTwo', 'args' => args)
            end
          end
        end

        context 'when a block is provided' do
          let(:result_scheduler) { scheduler_class.new }
          let(:block) { ->(scheduler) { result_scheduler.job = scheduler.job } }

          it 'should yield a scheduler with the job' do
            klass.perform_async(*args, &block)
            expect(result_scheduler.job).to include(result_item)
          end

          it 'should call #schedule! on the Scheduler' do
            expect_any_instance_of(scheduler_class).to receive(:schedule!)
            klass.perform_async(*args, &block)
          end
        end

      end

      describe '#perform_in' do
        let(:now) { Time.now }
        let(:interval) { rand(1..999) }
        let(:scheduled_job) { global_redis.zrange('bolt:scheduled', 0, -1).first }
        let(:result_work) { JSON.load(scheduled_job) }
        let(:result_item) { Sidekiq.load_json(result_work['work']) }
        let(:result_queue) { result_work['queue'] }
        let(:result_resource) { result_work['resource'] }

        before { klass.perform_in(interval, *args) }

        around { |example| Timecop.freeze(now) { example.run } }

        it 'should enqueue the work to the default queue/resource' do
          expect(result_item).to include('queue' => queue_name, 'resource' => resource_name, 'class' => 'Sidekiq::Bolt::MockWorker', 'args' => args)
        end

        it 'should schedule to run in the specified interval' do
          expect(global_redis.zscore('bolt:scheduled', scheduled_job)).to eq(now.to_f + interval)
        end

        it 'should save the queue for later scheduling' do
          expect(result_queue).to eq(queue_name)
        end

        it 'should save the resource for later scheduling' do
          expect(result_resource).to eq(resource_name)
        end

        context 'with an overridden resource name' do
          let(:klass) { MockWorkerTwo }
          let(:resource_name) { MockWorkerTwo::RESOURCE_NAME }

          it 'should enqueue the work to the specified resource' do
            expect(result_item).to include('queue' => queue_name, 'resource' => resource_name, 'class' => 'Sidekiq::Bolt::MockWorkerTwo', 'args' => args)
          end

          it 'should save the resource for later scheduling' do
            expect(result_resource).to eq(resource_name)
          end
        end

        context 'with an overridden queue name' do
          let(:klass) { MockWorkerThree }
          let(:queue_name) { MockWorkerThree::QUEUE_NAME }

          it 'should enqueue the work to the specified queue' do
            expect(result_item).to include('queue' => queue_name, 'resource' => resource_name, 'class' => 'Sidekiq::Bolt::MockWorkerThree', 'args' => args)
          end

          it 'should save the queue for later scheduling' do
            expect(result_queue).to eq(queue_name)
          end
        end
      end

      describe '.perform_async_with_options' do
        let(:options) { {} }
        let(:block) { nil }

        it 'should return the new job id' do
          expect(klass.perform_async_with_options({}, *args)).to eq(result_item['jid'])
        end

        describe 'enqueuing the job' do
          before { klass.perform_async_with_options(options, *args, &block) }

          it 'should enqueue the work to the default queue/resource' do
            expect(result_item).to include('queue' => queue_name, 'resource' => resource_name, 'class' => 'Sidekiq::Bolt::MockWorker', 'args' => args)
          end

          describe 'persisting results to redis' do
            let(:options) { {persist_result: true} }

            it 'should indicate that this result will be persisted so that it may be picked up later' do
              expect(result_item['persist']).to eq(true)
            end

            context 'when not to be persisted' do
              let(:options) { {} }

              it 'should not include that key' do
                expect(result_item).not_to include('persist')
              end
            end
          end

          context 'when a block is provided' do
            let(:result_scheduler) { scheduler_class.new }
            let(:block) { ->(scheduler) { result_scheduler.job = scheduler.job } }

            it 'should yield a scheduler with the job' do
              expect(result_scheduler.job).to include(result_item)
            end
          end

          context 'when the class sets the resource name' do
            let(:resource_name) { MockWorkerTwo::RESOURCE_NAME }
            let(:klass) { MockWorkerTwo }

            it 'should enqueue the work to the proper resource' do
              expect(result_item['resource']).to eq(resource_name)
            end
          end

          context 'when the class sets the queue name' do
            let(:klass) { MockWorkerThree }

            it 'should enqueue the work to the proper resource' do
              expect(result_item['queue']).to eq(MockWorkerThree::QUEUE_NAME)
            end
          end

          context 'with an overridden queue' do
            let(:new_queue) { Faker::Lorem.word }
            let(:options) { {queue: new_queue} }

            it 'should use the new queue' do
              expect(result_item['queue']).to eq(new_queue)
            end

            it 'should use the new queue as the parent job id' do
              expect(result_item['pjid']).to eq(new_queue)
            end

            context 'with an overridden job' do
              let(:new_job) { Faker::Lorem.word }
              let(:options) { {job: new_job, queue: new_queue} }
              let(:queue) { Queue.new(new_queue) }

              it 'should use the new queue' do
                expect(queue.job).to eq(Job.new(new_job))
              end
            end
          end

          context 'with an overridden job' do
            let(:new_job) { Faker::Lorem.word }
            let(:options) { {job: new_job} }
            let(:queue) { Queue.new(queue_name) }

            it 'should use the new job' do
              expect(queue.job).to eq(Job.new(new_job))
            end
          end

          context 'with an overridden resource' do
            let(:new_resource) { Faker::Lorem.word }
            let(:resource_name) { new_resource }
            let(:options) { {resource: new_resource} }

            it 'should use the new queue' do
              expect(result_item['resource']).to eq(new_resource)
            end
          end

          context 'with an overridden jid' do
            let(:new_jid) { Digest::MD5.base64digest(Faker::Lorem.word) }
            let(:options) { {job_id: new_jid} }

            it 'should use the new queue' do
              expect(result_item['jid']).to eq(new_jid)
            end
          end

          context 'with a parent jid' do
            let(:new_jid) { Digest::MD5.base64digest(Faker::Lorem.word) }
            let(:options) { {parent_job_id: new_jid} }

            it 'should use the set parent job id' do
              expect(result_item['pjid']).to eq(new_jid)
            end
          end
        end
      end

      describe '#acknowledge_work' do
        let(:retryable) { true }
        let(:original_job) { Message['queue' => queue_name, 'resource' => resource_name, 'jid' => job_id, 'pjid' => parent_job_id, 'retry' => retryable] }
        let(:original_message) { Sidekiq.dump_json(original_job) }
        let(:job_id) { SecureRandom.uuid }
        let(:parent_job_id) { SecureRandom.uuid }

        before do
          resource.add_work(queue_name, original_message)
          subject.queue = Queue.new(queue_name)
          subject.resource = resource
          subject.original_message = original_message
          subject.jid = job_id
          subject.parent_job_id = parent_job_id
          allocation = work_klass.from_allocation(resource_name, resource.allocate(1))
          subject.resource_allocation = allocation.allocation
        end

        it 'should acknowledge that the work is done' do
          subject.acknowledge_work
          expect(resource.allocated).to eq(0)
        end

        describe 'job succession' do
          let(:resource_name) { Resource::ASYNC_LOCAL_RESOURCE }

          before { global_redis.sadd("dependencies:#{parent_job_id}", job_id) }

          it 'should call the JobSuccession server middleware' do
            subject.acknowledge_work
            expect(global_redis.smembers("dependencies:#{parent_job_id}")).not_to include(job_id)
          end

          context 'when an error is provided' do
            let(:error) { StandardError.new(Faker::Lorem.word).tap { |error| error.set_backtrace(Faker::Lorem.paragraphs) } }

            it 'should call the RetryJobs server middleware' do
              subject.acknowledge_work(error)
              expect(resource.retrying).to eq(1)
            end

            context 'when this job cannot retry' do
              let(:retryable) { false }

              it 'should still acknowledge that the work is done' do
                subject.acknowledge_work(error)
                expect(resource.allocated).to eq(0)
              end

              it 'should indicate that the job failed completely in the logs' do
                expect(Sidekiq.logger).to receive(:error).with("Local async job failed: #{error}\n#{error.backtrace * "\n"}")
                subject.acknowledge_work(error)
              end

            end
          end

          context 'when the original resource was not $async_local' do
            let(:resource_name) { Faker::Lorem.word }

            it 'should not call the JobSuccession server middleware' do
              subject.acknowledge_work
              expect(global_redis.smembers("dependencies:#{parent_job_id}")).to include(job_id)
            end
          end
        end
      end

    end
  end
end
