# frozen_string_literal: true

RSpec.describe VersionedHelpers do
  # Create a test class that includes our helper module
  let(:helper_class) do
    Class.new do
      include VersionedHelpers
      
      attr_reader :items
      
      def initialize(items)
        @items = items
      end
    end
  end

  let(:mock_items) do
    [
      # Duck Duck Goose - 2 versions
      create_mock_item('duck-duck-goose', 'abc1234567890123456789012345678901234567', Time.new(2024, 1, 1), 'Duck Duck Goose'),
      create_mock_item('duck-duck-goose', 'def4567890123456789012345678901234567890', Time.new(2024, 2, 1), 'Duck Duck Goose Updated'),
      
      # Tag - 1 version  
      create_mock_item('tag', 'ghi7890123456789012345678901234567890123', Time.new(2024, 1, 15), 'Tag Game'),
      
      # Blog post - 1 version (different prefix)
      create_mock_item('blog/hello-world', 'jkl0123456789012345678901234567890123456', Time.new(2024, 3, 1), 'Hello World'),
      
      # Card game - 1 version (nested)
      create_mock_item('games/card-games/poker', 'mno3456789012345678901234567890123456789', Time.new(2024, 3, 15), 'Poker'),
      
      # Regular item without versioning attributes
      double('regular_item', :[] => nil, identifier: '/regular/')
    ]
  end

  let(:helper) { helper_class.new(mock_items) }

  def create_mock_item(base_id, sha, date, title)
    double('versioned_item',
      :[] => proc { |key|
        case key
        when :base_id then base_id
        when :version_sha then sha
        when :version_date then date
        when :title then title
        end
      }.call(nil), # This will return nil for any unmocked key
      identifier: "/#{base_id}/#{sha[0..6]}/"
    ).tap do |item|
      # Mock the [] method properly
      allow(item).to receive(:[]) do |key|
        case key
        when :base_id then base_id
        when :version_sha then sha
        when :version_date then date
        when :title then title
        else nil
        end
      end
    end
  end

  describe '#versioned_items' do
    context 'without prefix filter' do
      it 'returns all items with versioning attributes' do
        result = helper.versioned_items
        expect(result.length).to eq(5) # Excludes the regular item
        expect(result.all? { |item| item[:base_id] && item[:version_sha] }).to be true
      end

      it 'excludes items without versioning attributes' do
        result = helper.versioned_items
        regular_item = mock_items.last
        expect(result).not_to include(regular_item)
      end
    end

    context 'with prefix filter' do
      it 'returns only items matching the prefix' do
        result = helper.versioned_items('duck')
        expect(result.length).to eq(2)
        expect(result.all? { |item| item[:base_id].start_with?('duck') }).to be true
      end

      it 'returns items matching partial prefix' do
        result = helper.versioned_items('games')
        expect(result.length).to eq(1)
        expect(result.first[:base_id]).to eq('games/card-games/poker')
      end

      it 'returns empty array for non-matching prefix' do
        result = helper.versioned_items('nonexistent')
        expect(result).to be_empty
      end

      it 'handles exact base_id matches' do
        result = helper.versioned_items('tag')
        expect(result.length).to eq(1)
        expect(result.first[:base_id]).to eq('tag')
      end
    end
  end

  describe '#latest_versions' do
    context 'without prefix filter' do
      it 'returns one item per base_id' do
        result = helper.latest_versions
        base_ids = result.map { |item| item[:base_id] }
        expect(base_ids.uniq.length).to eq(base_ids.length)
      end

      it 'returns the latest version for each base_id' do
        result = helper.latest_versions
        
        # Find duck-duck-goose item (should be the newer version)
        ddg_item = result.find { |item| item[:base_id] == 'duck-duck-goose' }
        expect(ddg_item[:version_date]).to eq(Time.new(2024, 2, 1))
        expect(ddg_item[:title]).to eq('Duck Duck Goose Updated')
      end

      it 'sorts results by base_id' do
        result = helper.latest_versions
        base_ids = result.map { |item| item[:base_id] }
        expect(base_ids).to eq(base_ids.sort)
      end

      it 'returns correct number of unique items' do
        result = helper.latest_versions
        expect(result.length).to eq(4) # 4 unique base_ids
      end
    end

    context 'with prefix filter' do
      it 'returns latest versions only for matching prefix' do
        result = helper.latest_versions('duck')
        expect(result.length).to eq(1)
        expect(result.first[:base_id]).to eq('duck-duck-goose')
        expect(result.first[:version_date]).to eq(Time.new(2024, 2, 1))
      end

      it 'handles nested path prefixes' do
        result = helper.latest_versions('games')
        expect(result.length).to eq(1)
        expect(result.first[:base_id]).to eq('games/card-games/poker')
      end
    end
  end

  describe '#version_history' do
    context 'with string base_id' do
      it 'returns all versions for a base_id sorted chronologically' do
        result = helper.version_history('duck-duck-goose')
        expect(result.length).to eq(2)
        
        dates = result.map { |item| item[:version_date] }
        expect(dates).to eq(dates.sort)
        
        expect(result.first[:version_date]).to eq(Time.new(2024, 1, 1))
        expect(result.last[:version_date]).to eq(Time.new(2024, 2, 1))
      end

      it 'returns single item for base_id with one version' do
        result = helper.version_history('tag')
        expect(result.length).to eq(1)
        expect(result.first[:base_id]).to eq('tag')
      end

      it 'returns empty array for non-existent base_id' do
        result = helper.version_history('non-existent')
        expect(result).to be_empty
      end
    end

    context 'with item object' do
      it 'returns version history for item base_id' do
        duck_item = mock_items.find { |item| item[:base_id] == 'duck-duck-goose' }
        result = helper.version_history(duck_item)
        expect(result.length).to eq(2)
        expect(result.all? { |item| item[:base_id] == 'duck-duck-goose' }).to be true
      end

      it 'handles item without base_id' do
        item_without_base_id = double('item', :[] => nil)
        result = helper.version_history(item_without_base_id)
        expect(result).to be_empty
      end
    end

    context 'with invalid input' do
      it 'returns empty array for nil input' do
        result = helper.version_history(nil)
        expect(result).to be_empty
      end

      it 'returns empty array for invalid input type' do
        result = helper.version_history(123)
        expect(result).to be_empty
      end
    end
  end

  describe '#short_sha' do
    it 'returns first 7 characters of SHA' do
      item = mock_items.first
      result = helper.short_sha(item)
      expect(result).to eq('abc1234')
    end

    it 'returns nil for item without version_sha' do
      item = double('item', :[] => nil)
      result = helper.short_sha(item)
      expect(result).to be_nil
    end
  end

  describe '#version_date_formatted' do
    it 'returns formatted date string' do
      item = mock_items.first
      result = helper.version_date_formatted(item)
      expect(result).to eq('January 01, 2024 at 12:00 AM')
    end

    it 'returns nil for item without version_date' do
      item = double('item', :[] => nil)
      result = helper.version_date_formatted(item)
      expect(result).to be_nil
    end
  end

  describe '#latest_version?' do
    it 'returns true for latest version of an item' do
      # Get the newer duck-duck-goose item
      newer_duck_item = mock_items.find { |item| 
        item[:base_id] == 'duck-duck-goose' && item[:version_date] == Time.new(2024, 2, 1) 
      }
      result = helper.latest_version?(newer_duck_item)
      expect(result).to be true
    end

    it 'returns false for older version of an item' do
      # Get the older duck-duck-goose item
      older_duck_item = mock_items.find { |item| 
        item[:base_id] == 'duck-duck-goose' && item[:version_date] == Time.new(2024, 1, 1) 
      }
      result = helper.latest_version?(older_duck_item)
      expect(result).to be false
    end

    it 'returns true for items with only one version' do
      tag_item = mock_items.find { |item| item[:base_id] == 'tag' }
      result = helper.latest_version?(tag_item)
      expect(result).to be true
    end

    it 'returns false for item without base_id' do
      item = double('item', :[] => nil)
      result = helper.latest_version?(item)
      expect(result).to be false
    end

    it 'returns false for item without version_date' do
      item = double('item', :[] => proc { |key| key == :base_id ? 'test' : nil }.call(nil))
      allow(item).to receive(:[]) { |key| key == :base_id ? 'test' : nil }
      result = helper.latest_version?(item)
      expect(result).to be false
    end
  end

  describe '#versioned_base_ids' do
    context 'without prefix filter' do
      it 'returns all unique base_ids sorted' do
        result = helper.versioned_base_ids
        expected = ['blog/hello-world', 'duck-duck-goose', 'games/card-games/poker', 'tag']
        expect(result).to eq(expected)
      end
    end

    context 'with prefix filter' do
      it 'returns base_ids matching prefix' do
        result = helper.versioned_base_ids('duck')
        expect(result).to eq(['duck-duck-goose'])
      end

      it 'returns empty array for non-matching prefix' do
        result = helper.versioned_base_ids('xyz')
        expect(result).to be_empty
      end
    end
  end

  describe '#version_counts' do
    context 'without prefix filter' do
      it 'returns count of versions for each base_id' do
        result = helper.version_counts
        expected = {
          'duck-duck-goose' => 2,
          'tag' => 1,
          'blog/hello-world' => 1,
          'games/card-games/poker' => 1
        }
        expect(result).to eq(expected)
      end
    end

    context 'with prefix filter' do
      it 'returns counts only for matching prefix' do
        result = helper.version_counts('duck')
        expect(result).to eq({ 'duck-duck-goose' => 2 })
      end

      it 'returns empty hash for non-matching prefix' do
        result = helper.version_counts('xyz')
        expect(result).to eq({})
      end
    end
  end

  describe 'integration with empty items' do
    let(:empty_helper) { helper_class.new([]) }

    it 'handles empty items gracefully' do
      expect(empty_helper.versioned_items).to be_empty
      expect(empty_helper.latest_versions).to be_empty
      expect(empty_helper.version_history('anything')).to be_empty
      expect(empty_helper.versioned_base_ids).to be_empty
      expect(empty_helper.version_counts).to eq({})
    end
  end

  describe 'edge cases with malformed data' do
    let(:malformed_items) do
      [
        # Item with base_id but no version_sha
        double('item1', :[] => proc { |key| key == :base_id ? 'test1' : nil }.call(nil)),
        # Item with version_sha but no base_id  
        double('item2', :[] => proc { |key| key == :version_sha ? 'abc123' : nil }.call(nil)),
        # Item with all attributes
        create_mock_item('valid', 'def456', Time.new(2024, 1, 1), 'Valid Item')
      ]
    end

    let(:malformed_helper) { helper_class.new(malformed_items) }

    before do
      malformed_items.each_with_index do |item, index|
        allow(item).to receive(:[]) do |key|
          case index
          when 0 # Item with only base_id
            key == :base_id ? 'test1' : nil
          when 1 # Item with only version_sha
            key == :version_sha ? 'abc123' : nil
          when 2 # Valid item (already handled by create_mock_item)
            case key
            when :base_id then 'valid'
            when :version_sha then 'def456'
            when :version_date then Time.new(2024, 1, 1)
            when :title then 'Valid Item'
            else nil
            end
          end
        end
      end
    end

    it 'filters out items without both base_id and version_sha' do
      result = malformed_helper.versioned_items
      expect(result.length).to eq(1)
      expect(result.first[:base_id]).to eq('valid')
    end

    it 'handles malformed items in latest_versions' do
      result = malformed_helper.latest_versions
      expect(result.length).to eq(1)
      expect(result.first[:base_id]).to eq('valid')
    end
  end
end
