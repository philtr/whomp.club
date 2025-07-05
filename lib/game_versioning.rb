require 'yaml'

module GameVersioning
  TIMESTAMP_RE = /\d{12}/.freeze

  def self.create_index_items(items)
    Dir.glob('content/games/*').select { |d| File.directory?(d) }.each do |dir|
      versions = Dir.glob(File.join(dir, '*.md')).select { |f| File.basename(f) =~ TIMESTAMP_RE }
      next if versions.empty?
      latest = versions.max
      content = File.read(latest)
      attrs = extract_attrs(content)
      base = File.basename(dir)
      identifier = "/games/#{base}/index.md"
      items.create(content, attrs.merge(index: true), identifier)
    end
  end

  def self.extract_attrs(content)
    if content =~ /^---\s*\n(.*?)\n---/m
      YAML.safe_load($1) || {}
    else
      {}
    end
  end
end
