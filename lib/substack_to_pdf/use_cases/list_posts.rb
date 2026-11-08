# frozen_string_literal: true

module SubstackPdf
  module UseCases
    # Prints the archive posts that match the current filters.
    class ListPosts
      def initialize(archive:, selector:)
        @archive = archive
        @selector = selector
      end

      def call
        selection = @selector.call(@archive.all_posts)
        warn_unmatched(selection)

        selection.posts.each do |post|
          puts "#{post.date_string}  #{post.slug}  #{post.title}"
        end
      end

      private

      def warn_unmatched(selection)
        return if selection.unmatched.empty?

        warn "Warning: #{selection.unmatched.size} --only value(s) did not match any archive post."
      end
    end
  end
end
