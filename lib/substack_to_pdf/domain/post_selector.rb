# frozen_string_literal: true

module SubstackPdf
  module Domain
    # Applies the --post and --limit filters to a collection of posts.
    class PostSelector
      Selection = Struct.new(:posts, :unmatched, keyword_init: true)

      def initialize(only: [], limit: nil)
        @only = Array(only)
        @limit = limit
      end

      def call(posts, limit: @limit)
        matching = @only.empty? ? posts : posts.select { |post| matches?(post) }
        unmatched = @only.reject { |value| posts.any? { |post| post.matches?(value) } }
        limited = limit ? matching.first(limit) : matching

        Selection.new(posts: limited, unmatched: unmatched)
      end

      private

      def matches?(post)
        @only.any? { |value| post.matches?(value) }
      end
    end
  end
end
