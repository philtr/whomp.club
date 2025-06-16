# frozen_string_literal: true

require 'rugged'

module Nanoc
  module DataSources
    class Versioned < Nanoc::DataSource
      identifier :versioned

      def initialize(site_config, items_root, layouts_root, config = {})
        super
        @site_config = site_config
        @prefix = config.fetch(:prefix, 'games')
        @extensions = config.fetch(:extensions, %w[.md .html .txt])
        @content_dir = config.fetch(:content_dir, 'content')
      end

      def items
        return enum_for(:items) unless block_given?

        versioned_items_data.each do |item_data|
          yield item_data
        end
      end

      private

      def versioned_items_data
        items_data = []
        
        begin
          repo = Rugged::Repository.discover('.')
        rescue Rugged::RepositoryError
          return items_data
        end

        tracked_files.each do |file_path|
          base_id = extract_base_id(file_path)
          
          commits_for_file(repo, file_path).each do |commit|
            content = file_content_at_commit(repo, commit, file_path)
            next if content.nil?

            attributes = {
              base_id: base_id,
              version_sha: commit.oid,
              version_date: commit.time,
              title: infer_title(file_path, content),
              extension: File.extname(file_path)
            }

            identifier = "/#{base_id}/#{commit.oid[0..6]}"
            
            items_data << Nanoc::Core::Item.new(
              content,
              attributes,
              identifier
            )
          end
        end

        items_data.sort_by { |item| [item.attributes[:base_id], item.attributes[:version_date]] }
      end

      def tracked_files
        content_path = File.join(site_root, @content_dir, @prefix)
        
        # If the content directory for this prefix doesn't exist, return empty
        # This covers the case where the entire content structure is removed
        return [] unless Dir.exist?(content_path)
        
        current_files = Dir.glob(File.join(content_path, '**', '*'))
           .select { |f| File.file?(f) && @extensions.include?(File.extname(f)) }
           .map { |f| f.sub("#{site_root}/", '') }

        # Also scan git history for files that may have been deleted
        historical_files = []
        begin
          repo = Rugged::Repository.discover('.')
          walker = Rugged::Walker.new(repo)
          walker.sorting(Rugged::SORT_NONE)
          walker.push(repo.head.target_id)

          prefix_pattern = "#{@content_dir}/#{@prefix}/"
          walker.each do |commit|
            begin
              commit.tree.walk_blobs do |root, entry|
                full_path = root.empty? ? entry[:name] : File.join(root, entry[:name])
                if full_path.start_with?(prefix_pattern) && @extensions.include?(File.extname(full_path))
                  historical_files << full_path unless historical_files.include?(full_path)
                end
              end
            rescue
              # Skip any problematic commits
            end
          end
        rescue Rugged::RepositoryError
          # No git repo
        end

        (current_files + historical_files).uniq
      end

      def extract_base_id(file_path)
        relative_path = file_path.sub(/^#{@content_dir}\/#{@prefix}\//, '')
        relative_path.sub(/#{Regexp.escape(File.extname(relative_path))}$/, '')
      end

      def commits_for_file(repo, file_path)
        commits = []
        walker = Rugged::Walker.new(repo)
        walker.sorting(Rugged::SORT_DATE | Rugged::SORT_REVERSE)
        walker.push(repo.head.target_id)

        previous_content = nil
        walker.each do |commit|
          current_content = get_file_content_at_commit(repo, commit, file_path)
          
          # Only include this commit if the file was added or changed
          if current_content && current_content != previous_content
            commits << commit
            previous_content = current_content
          end
        end

        commits
      rescue Rugged::ReferenceError
        []
      end

      def get_file_content_at_commit(repo, commit, file_path)
        begin
          blob_entry = commit.tree.path(file_path)
          blob = repo.lookup(blob_entry[:oid])
          blob.content
        rescue Rugged::TreeError
          nil
        end
      end

      def file_content_at_commit(repo, commit, file_path)
        get_file_content_at_commit(repo, commit, file_path)
      end

      def infer_title(file_path, content)
        # Try to extract title from front matter or first heading
        if content =~ /^---\s*\n.*?^title:\s*([^\n]+)/m
          $1.strip.gsub(/^["']|["']$/, '')
        elsif content =~ /<h1[^>]*>([^<]+)<\/h1>/i
          $1.strip
        elsif content =~ /^#\s*(.+)$/
          $1.strip
        else
          File.basename(file_path, File.extname(file_path)).tr('-_', ' ').split.map(&:capitalize).join(' ')
        end
      end

      def site_root
        @site_root ||= @site_config.fetch(:data_sources, [])
                          .find { |ds| ds[:type] == 'filesystem' }
                          &.fetch(:content_dir, 'content')
                          &.then { |dir| File.expand_path('..', dir) } || Dir.pwd
      end
    end
  end
end
