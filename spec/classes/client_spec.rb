require 'rspec'

module Sidekiq
  module Bolt
    describe Client do

      it { is_expected.to be_a_kind_of(Sidekiq::Client) }

      describe 'push items into the queue' do
        let(:queue_name) { Faker::Lorem.word }
        let(:resource_name) { Faker::Lorem.word }
        let(:klass) { Faker::Lorem.word }
        let(:args) { Faker::Lorem.paragraphs }
        #noinspection RubyStringKeysInHashInspection
        let(:item) { {'queue' => queue_name, 'resource' => resource_name, 'class' => klass, 'args' => args} }
        let!(:original_item) { item.dup }
        let(:resource) { Resource.new(resource_name) }
        let(:result_work) { resource.allocate(1) }
        let(:result_queue) { result_work[0] }
        let(:result_item) { Sidekiq::load_json(result_work[1]) }
        let(:now) { Time.now }

        around { |example| Timecop.freeze(now) { example.run } }

        it 'should push the item on to the queue for the specified resource' do
          subject.push(item)
          expect(result_item).to include(original_item)
        end

        it 'should include the time the item was enqueued at' do
          subject.push(item)
          expect(result_item).to include('enqueued_at' => now.to_s)
        end

        it 'should use the right queue' do
          subject.push(item)
          expect(result_queue).to eq(queue_name)
        end

        describe 'pushing multiple items' do
          let(:args_two) { Faker::Lorem.paragraphs }
          let!(:original_item_two) { item.dup }
          let(:result_work) { resource.allocate(2) }
          let(:result_queue_two) { result_work[2] }
          let(:result_item_two) { Sidekiq::load_json(result_work[3]) }
          let(:items) { {'queue' => queue_name, 'resource' => resource_name, 'class' => klass, 'args' => [args, args_two]} }
          let(:result_args) { [result_item['args'], result_item_two['args']] }

          it 'should push each item on to the queue' do
            subject.push_bulk(items)
            expect(result_args).to match_array([args, args_two])
          end
        end

        context 'with no resource specified' do
          let(:resource_name) { nil }
          let(:resource) { Resource.new('default') }

          it 'should push the item on to the queue for the default resource' do
            subject.push(item)
            expect(result_item).to include(original_item)
          end
        end
      end

    end
  end
end