require 'spec_helper'

RSpec.describe GameVersioning do
  it 'creates index items using latest version' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('content/games/test')
        File.write('content/games/test/202401010000.md', "old\n")
        File.write('content/games/test/202402010000.md', "new\n")
        collection = []
        wrapper = Class.new do
          attr_reader :items
          def initialize(arr); @items = arr; end
          def create(content, attrs, id)
            @items << Nanoc::Core::Item.new(content, attrs, id)
          end
        end.new(collection)
        GameVersioning.create_index_items(wrapper)
        index = collection.find { |i| i.identifier.to_s == '/games/test/index.md' }
        expect(index).not_to be_nil
        expect(index.content.string).to eq("new\n")
      end
    end
  end
end
