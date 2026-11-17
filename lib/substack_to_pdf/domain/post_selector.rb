# frozen_string_literal: true

module SubstackPdf
  module Domain
    # Applies the --post, saved-file and --limit filters to a collection of
    # posts. Accepts arrays and lazy enumerators so callers can stop fetching
    # archive pages as soon as the limit is reached.
    class PostSelector
      Selection = Struct.new(:posts, :unmatched, :matched_count, keyword_init: true)

      def initialize(only: [], limit: nil)
        @only = Array(only)
        @limit = limit
      end

      def call(posts, limit: @limit, filter: nil)
        return Selection.new(posts: [], unmatched: [], matched_count: 0) if limit && limit <= 0

        selected = []
        matched_refs = {}
        matched_count = 0
        completed = true

        posts.each do |post|
          matched = @only.empty? ? [] : @only.select { |value| post.matches?(value) }
          next if !@only.empty? && matched.empty?

          matched.each { |value| matched_refs[value] = true }
          matched_count += 1

          next if filter && !filter.call(post)

          selected << post

          if limit && selected.size >= limit
            completed = false
            break
          end
        end

        unmatched = @only.empty? || !completed ? [] : @only.reject { |value| matched_refs[value] }
        Selection.new(posts: selected, unmatched: unmatched, matched_count: matched_count)
      end
    end
  end
end
