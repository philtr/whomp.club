# frozen_string_literal: true

RSpec.describe Nanoc::DataSources::Versioned do
  let(:site_config) do
    {
      data_sources: [
        { type: 'filesystem', content_dir: 'content' }
      ]
    }
  end
  let(:items_root) { '/games/' }
  let(:layouts_root) { '/' }
  let(:config) { { prefix: 'games', extensions: %w[.md .html], content_dir: 'content' } }
  let(:data_source) { described_class.new(site_config, items_root, layouts_root, config) }

  around(:each) do |example|
    Dir.mktmpdir do |tmpdir|
      @tmpdir = tmpdir
      Dir.chdir(tmpdir) do
        example.run
      end
    end
  end

  def setup_git_repo_with_files
    # Initialize git repo
    repo = Rugged::Repository.init_at('.')
    
    # Set up git config
    config = repo.config
    config['user.name'] = 'Test User'
    config['user.email'] = 'test@example.com'

    # Create content directory structure
    FileUtils.mkdir_p('content/games')
    
    # Create initial files and commits
    create_file_and_commit(repo, 'content/games/duck-duck-goose.md', 
      "---\ntitle: Duck Duck Goose\n---\n\n# Duck Duck Goose\n\nA classic game.",
      'Add duck-duck-goose game', 
      Time.new(2024, 1, 1, 12, 0, 0))
    
    create_file_and_commit(repo, 'content/games/tag.html',
      "<h1>Tag Game</h1>\n<p>Run and tag others!</p>",
      'Add tag game',
      Time.new(2024, 1, 15, 14, 0, 0))
    
    # Update duck-duck-goose
    create_file_and_commit(repo, 'content/games/duck-duck-goose.md',
      "---\ntitle: Duck Duck Goose\n---\n\n# Duck Duck Goose\n\nA classic game for all ages.\n\n## Rules\n\n1. Sit in circle\n2. One person walks around",
      'Update duck-duck-goose with rules',
      Time.new(2024, 2, 1, 10, 0, 0))
    
    repo
  end

  def create_file_and_commit(repo, filepath, content, message, time)
    # Ensure directory exists
    FileUtils.mkdir_p(File.dirname(filepath))
    
    # Write file
    File.write(filepath, content)
    
    # Add to index
    index = repo.index
    index.add(filepath)
    index.write
    
    # Create commit
    signature = {
      name: 'Test User',
      email: 'test@example.com',
      time: time
    }
    
    tree_id = index.write_tree(repo)
    parents = repo.empty? ? [] : [repo.head.target]
    
    Rugged::Commit.create(repo,
      tree: tree_id,
      author: signature,
      committer: signature,
      message: message,
      parents: parents,
      update_ref: 'HEAD'
    )
  end

  describe '#initialize' do
    it 'sets default configuration values' do
      ds = described_class.new(site_config, items_root, layouts_root, {})
      expect(ds.instance_variable_get(:@prefix)).to eq('games')
      expect(ds.instance_variable_get(:@extensions)).to eq(%w[.md .html .txt])
      expect(ds.instance_variable_get(:@content_dir)).to eq('content')
    end

    it 'uses provided configuration values' do
      custom_config = { prefix: 'blog', extensions: %w[.markdown], content_dir: 'src' }
      ds = described_class.new(site_config, items_root, layouts_root, custom_config)
      expect(ds.instance_variable_get(:@prefix)).to eq('blog')
      expect(ds.instance_variable_get(:@extensions)).to eq(%w[.markdown])
      expect(ds.instance_variable_get(:@content_dir)).to eq('src')
    end
  end

  describe '#items' do
    context 'with no git repository' do
      it 'returns empty array when no git repo exists' do
        items = data_source.items.to_a
        expect(items).to be_empty
      end
    end

    context 'with no content directory' do
      before do
        setup_git_repo_with_files
        FileUtils.rm_rf('content')
      end

      it 'returns empty array when content directory does not exist' do
        items = data_source.items.to_a
        expect(items).to be_empty
      end
    end

    context 'with git repository and content' do
      before do
        setup_git_repo_with_files
      end

      it 'returns versioned items for all commits' do
        items = data_source.items.to_a
        expect(items.length).to eq(3) # 2 commits for duck-duck-goose + 1 for tag
      end

      it 'creates items with correct attributes' do
        items = data_source.items.to_a
        
        # Check first item (earliest duck-duck-goose)
        first_item = items.find { |i| i.attributes[:base_id] == 'duck-duck-goose' && i.content.string.include?('A classic game.') }
        expect(first_item).not_to be_nil
        expect(first_item.attributes[:base_id]).to eq('duck-duck-goose')
        expect(first_item.attributes[:version_sha]).to be_a(String)
        expect(first_item.attributes[:version_sha].length).to eq(40) # Full SHA
        expect(first_item.attributes[:version_date]).to be_a(Time)
        expect(first_item.attributes[:title]).to eq('Duck Duck Goose')
        expect(first_item.attributes[:extension]).to eq('.md')
      end

      it 'creates items with correct identifiers' do
        items = data_source.items.to_a
        
        items.each do |item|
          expect(item.identifier.to_s).to match(%r{^/[\w-]+/[a-f0-9]{7}$})
          expect(item.identifier.to_s).to start_with("/#{item.attributes[:base_id]}/")
        end
      end

      it 'sorts items by base_id and version_date' do
        items = data_source.items.to_a
        
        # Should be sorted by base_id first, then by date
        base_ids = items.map { |i| i.attributes[:base_id] }
        expect(base_ids).to eq(['duck-duck-goose', 'duck-duck-goose', 'tag'])
        
        # Duck-duck-goose items should be sorted by date
        ddg_items = items.select { |i| i.attributes[:base_id] == 'duck-duck-goose' }
        dates = ddg_items.map { |i| i.attributes[:version_date] }
        expect(dates).to eq(dates.sort)
      end

      it 'handles items with different extensions' do
        items = data_source.items.to_a
        
        md_items = items.select { |i| i.attributes[:extension] == '.md' }
        html_items = items.select { |i| i.attributes[:extension] == '.html' }
        
        expect(md_items.count).to eq(2) # Two versions of duck-duck-goose
        expect(html_items.count).to eq(1) # One version of tag
      end

      it 'extracts titles correctly from front matter and content' do
        items = data_source.items.to_a
        
        # Markdown file with front matter
        md_item = items.find { |i| i.attributes[:extension] == '.md' }
        expect(md_item.attributes[:title]).to eq('Duck Duck Goose')
        
        # HTML file with h1
        html_item = items.find { |i| i.attributes[:extension] == '.html' }
        expect(html_item.attributes[:title]).to eq('Tag Game')
      end
    end

    context 'with filtered extensions' do
      let(:config) { { prefix: 'games', extensions: %w[.md], content_dir: 'content' } }

      before do
        setup_git_repo_with_files
      end

      it 'only includes files with specified extensions' do
        items = data_source.items.to_a
        expect(items.length).to eq(2) # Only .md files (duck-duck-goose versions)
        expect(items.all? { |i| i.attributes[:extension] == '.md' }).to be true
      end
    end

    context 'with different prefix' do
      let(:config) { { prefix: 'blog', extensions: %w[.md .html], content_dir: 'content' } }

      before do
        setup_git_repo_with_files
        # Create blog content
        repo = Rugged::Repository.new('.')
        FileUtils.mkdir_p('content/blog')
        create_file_and_commit(repo, 'content/blog/hello-world.md',
          "# Hello World\n\nFirst post!",
          'Add hello world blog post',
          Time.new(2024, 3, 1, 9, 0, 0))
      end

      it 'only includes files from specified prefix' do
        items = data_source.items.to_a
        expect(items.length).to eq(1)
        expect(items.first.attributes[:base_id]).to eq('hello-world')
      end
    end
  end

  describe 'edge cases' do
    before do
      setup_git_repo_with_files
    end

    context 'with nested directories' do
      before do
        repo = Rugged::Repository.new('.')
        FileUtils.mkdir_p('content/games/card-games')
        create_file_and_commit(repo, 'content/games/card-games/poker.md',
          "# Poker\n\nA gambling card game.",
          'Add poker card game',
          Time.new(2024, 3, 15, 16, 0, 0))
      end

      it 'handles nested directory structures' do
        items = data_source.items.to_a
        poker_item = items.find { |i| i.attributes[:base_id] == 'card-games/poker' }
        expect(poker_item).not_to be_nil
        expect(poker_item.attributes[:base_id]).to eq('card-games/poker')
        expect(poker_item.identifier.to_s).to match(%r{^/card-games/poker/[a-f0-9]{7}$})
      end
    end

    context 'with file without front matter or heading' do
      before do
        repo = Rugged::Repository.new('.')
        create_file_and_commit(repo, 'content/games/simple-game.md',
          "This is just plain text without any title markers.",
          'Add simple game',
          Time.new(2024, 4, 1, 11, 0, 0))
      end

      it 'infers title from filename' do
        items = data_source.items.to_a
        simple_item = items.find { |i| i.attributes[:base_id] == 'simple-game' }
        expect(simple_item.attributes[:title]).to eq('Simple Game')
      end
    end

    context 'with file that was deleted' do
      before do
        repo = Rugged::Repository.new('.')
        
        # Add a file
        create_file_and_commit(repo, 'content/games/temporary.md',
          "# Temporary\n\nThis will be deleted.",
          'Add temporary file',
          Time.new(2024, 5, 1, 12, 0, 0))
        
        # Delete the file
        FileUtils.rm('content/games/temporary.md')
        index = repo.index
        index.remove('content/games/temporary.md')
        index.write
        
        signature = {
          name: 'Test User',
          email: 'test@example.com',
          time: Time.new(2024, 5, 2, 12, 0, 0)
        }
        
        tree_id = index.write_tree(repo)
        Rugged::Commit.create(repo,
          tree: tree_id,
          author: signature,
          committer: signature,
          message: 'Delete temporary file',
          parents: [repo.head.target],
          update_ref: 'HEAD'
        )
      end

      it 'still includes historical versions of deleted files' do
        items = data_source.items.to_a
        temp_item = items.find { |i| i.attributes[:base_id] == 'temporary' }
        expect(temp_item).not_to be_nil
        expect(temp_item.attributes[:title]).to eq('Temporary')
      end
    end

    context 'with missing git objects' do
      before do
        repo = Rugged::Repository.new('.')
        oid = repo.head.target.tree.first[:oid]
        object_path = File.join(repo.path, 'objects', oid[0, 2], oid[2..])
        FileUtils.rm_f(object_path)
      end

      it 'handles Rugged::OdbError gracefully' do
        expect { data_source.items.to_a }.not_to raise_error
      end
    end
  end
end
