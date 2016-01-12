require 'rspec'

module Sidekiq
  module Bolt
    describe Poller do

      let(:now) { Time.now }

      around { |example| Timecop.freeze(now) { example.run } }

      describe '#enqueue_jobs' do
        let(:queue_name) { Faker::Lorem.word }
        let(:resource_name) { Faker::Lorem.word }
        let(:queue) { Queue.new(queue_name) }
        let(:resource) { Resource.new(resource_name) }
        let(:work_time) { now - 120 }
        let(:work_data) { SecureRandom.uuid }
        #noinspection RubyStringKeysInHashInspection
        let(:work) { {'queue' => queue_name, 'resource' => resource_name, 'work' => work_data} }
        let(:serialized_work) { JSON.dump(work) }
        let(:result_allocation) { resource.allocate(1) }
        let(:result_queue) { result_allocation[0] }
        let(:result_work) { result_allocation[1] }

        it 'should run the default Enq for Sidekiq' do
          expect_any_instance_of(Scheduled::Enq).to receive(:enqueue_jobs)
          Poller.new.enqueue_jobs
        end

        shared_examples_for 'enqueuing scheduled jobs' do |set|
          before do
            global_redis.zadd("bolt:#{set}", work_time.to_f, serialized_work)
            Poller.new.enqueue_jobs
          end

          it 'should add the work to the queue that it came from' do
            expect(result_queue).to eq(queue_name)
          end

          it 'should add the work to the resource that it came from' do
            expect(result_work).to eq(work_data)
          end

          it 'should create a reference between the queue and the resource' do
            expect(queue.resources.map(&:name)).to include(resource_name)
          end

          it 'should remove the item from the set' do
            expect(global_redis.zrange("bolt:#{set}", 0, -1)).to be_empty
          end

          context 'when the work is scheduled for later' do
            let(:work_time) { now + 120 }

            it 'should not re-enqueue the work' do
              expect(result_work).to be_nil
            end
          end
        end

        describe 'enqueueing retries' do
          it_behaves_like 'enqueuing scheduled jobs', :retry

          it 'should count the work as retrying' do
            global_redis.zadd('bolt:retry', work_time.to_f, serialized_work)
            Poller.new.enqueue_jobs
            expect(resource.retrying).to eq(1)
          end
        end

        describe 'enqueueing scheduled jobs' do
          it_behaves_like 'enqueuing scheduled jobs', :scheduled

          it 'should not count the work as retrying' do
            global_redis.zadd('bolt:scheduled', work_time.to_f, serialized_work)
            Poller.new.enqueue_jobs
            expect(resource.retrying).to eq(0)
          end
        end

      end

    end
  end
end