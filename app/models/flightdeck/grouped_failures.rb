# frozen_string_literal: true

module Flightdeck
  # Groups the failed rows of the *current page* by exception class.
  #
  # Grouping happens in Ruby on purpose. Extracting the exception class in SQL
  # would mean a JSON function per adapter (and an unindexed scan of a large
  # text column either way), which is a bad trade for a header row.
  class GroupedFailures
    Group = Struct.new(:key, :rows, keyword_init: true) do
      def count = rows.size
      def job_ids = rows.map(&:id)
      def first_failed_at = rows.filter_map(&:failed_at).min
      def last_failed_at = rows.filter_map(&:failed_at).max
    end

    def self.build(rows)
      rows
        .group_by { |row| row.error_summary.group_key }
        .map { |key, grouped| Group.new(key: key, rows: grouped) }
        .sort_by { |group| [ -group.count, group.key ] }
    end
  end
end
