# frozen_string_literal: true

module VersionedHelpers
  # Returns all versioned items, optionally filtered by prefix
  # @param prefix [String, nil] Optional prefix to filter items
  # @return [Array<Nanoc::Core::Item>] Array of versioned items
  def versioned_items(prefix = nil)
    items.select do |item|
      item[:base_id] && item[:version_sha] && 
        (prefix.nil? || item[:base_id].start_with?(prefix))
    end
  end

  # Returns the latest version of each base_id, optionally filtered by prefix
  # @param prefix [String, nil] Optional prefix to filter items
  # @return [Array<Nanoc::Core::Item>] Array of latest version items
  def latest_versions(prefix = nil)
    versioned = versioned_items(prefix)
    
    # Group by base_id and get the latest version for each
    versioned.group_by { |item| item[:base_id] }
             .map { |_base_id, versions| versions.max_by { |v| v[:version_date] } }
             .compact
             .sort_by { |item| item[:base_id] }
  end

  # Returns the version history for a given item or base_id
  # @param item_or_base_id [Nanoc::Core::Item, String] Item or base_id string
  # @return [Array<Nanoc::Core::Item>] Array of versions sorted chronologically
  def version_history(item_or_base_id)
    base_id = case item_or_base_id
              when String
                item_or_base_id
              else
                # Check if it's an item object with attributes hash
                if item_or_base_id.respond_to?(:attributes) && item_or_base_id.attributes.respond_to?(:[])
                  item_or_base_id.attributes[:base_id]
                elsif item_or_base_id.respond_to?(:[]) && !item_or_base_id.is_a?(Array) && !item_or_base_id.is_a?(Integer)
                  item_or_base_id[:base_id]
                else
                  nil
                end
              end

    return [] if base_id.nil?

    versioned_items.select { |item| item[:base_id] == base_id }
                   .sort_by { |item| item[:version_date] }
  end

  # Returns the short SHA (7 characters) for a versioned item
  # @param item [Nanoc::Core::Item] The versioned item
  # @return [String, nil] Short SHA or nil if not available
  def short_sha(item)
    return nil unless item[:version_sha]
    item[:version_sha][0..6]
  end

  # Returns a human-readable version date for a versioned item
  # @param item [Nanoc::Core::Item] The versioned item
  # @return [String, nil] Formatted date or nil if not available
  def version_date_formatted(item)
    return nil unless item[:version_date]
    item[:version_date].strftime('%B %d, %Y at %I:%M %p')
  end

  # Checks if an item is the latest version of its base_id
  # @param item [Nanoc::Core::Item] The item to check
  # @return [Boolean] True if this is the latest version
  def latest_version?(item)
    return false unless item[:base_id] && item[:version_date]
    
    latest = latest_versions.find { |v| v[:base_id] == item[:base_id] }
    latest && latest[:version_sha] == item[:version_sha]
  end

  # Returns all base_ids that have versioned items, optionally filtered by prefix
  # @param prefix [String, nil] Optional prefix to filter base_ids
  # @return [Array<String>] Array of unique base_ids
  def versioned_base_ids(prefix = nil)
    versioned_items(prefix).map { |item| item[:base_id] }
                           .uniq
                           .sort
  end

  # Returns the count of versions for each base_id
  # @param prefix [String, nil] Optional prefix to filter items
  # @return [Hash<String, Integer>] Hash mapping base_id to version count
  def version_counts(prefix = nil)
    versioned_items(prefix).group_by { |item| item[:base_id] }
                           .transform_values(&:count)
  end
end
