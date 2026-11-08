# frozen_string_literal: true

module SubstackPdf
  module UseCases
    # Compares the remote archive with the local HTML library and lists unseen posts.
    class CheckNewPosts
      def initialize(archive:, library:, selector:)
        @archive = archive
        @library = library
        @selector = selector
      end

      def call
        selection = @selector.call(@archive.all_posts)
        warn_unmatched(selection)

        new_posts = selection.posts.reject { |post| @library.saved?(post) }
        report(new_posts)
        new_posts
      end

      private

      def report(posts)
        if posts.empty?
          puts "No new posts."
          return
        end

        puts "#{posts.size} new post(s):"
        posts.each do |post|
          puts "#{post.date_string}  #{post.slug}  #{post.title}"
        end
      end

      def warn_unmatched(selection)
        return if selection.unmatched.empty?

        warn "Warning: #{selection.unmatched.size} --only value(s) did not match any archive post."
      end
    end
  end
end
