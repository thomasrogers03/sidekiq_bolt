require 'rspec'

module Sidekiq
  module Bolt
    describe ProcessorAllocator do

      let(:options) { {} }
      let(:allocator) { ProcessorAllocator.new(options) }

      describe '#allocate' do
        let(:allocation) { 1 }
        let(:concurrency) { 12 }
        let(:options) { {concurrency: concurrency} }

        subject { allocator.allocate(allocation) }

        it { is_expected.to eq(1) }

        context 'when called multiple times' do
          before { allocator.allocate(allocation) }
          it { is_expected.to eq(1) }
        end

        context 'when called with a different allocation' do
          let(:allocation) { 5 }
          it { is_expected.to eq(5) }
        end

        context 'when there are not enough workers' do
          let(:concurrency) { 0 }
          it { is_expected.to eq(0) }

          context 'when we can allocate some workers' do
            let(:concurrency) { 1 }
            let(:allocation) { 2 }

            it { is_expected.to eq(1) }
          end
        end
      end

    end
  end
end