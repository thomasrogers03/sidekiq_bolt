require 'rspec'

module Sidekiq
  module Bolt
    module Exceptions
      describe InvalidResource do

        let(:resource_type) { Faker::Lorem.word }
        let(:allocator) { PersistentResource.new(resource_type) }
        let(:resource) { Faker::Lorem.sentence }

        subject { InvalidResource.new(allocator, resource) }

        it { is_expected.to be_a_kind_of(StandardError) }

        its(:message) { is_expected.to eq(%Q{Resource "#{resource}" of type "#{resource_type}" has been invalidated!}) }
        its(:allocator) { is_expected.to eq(allocator) }
        its(:resource) { is_expected.to eq(resource) }

      end
    end
  end
end
