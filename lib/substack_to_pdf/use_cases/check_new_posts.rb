# frozen_string_literal: true

require "json"

module SubstackPdf
  module UseCases
    # Compares the remote archive with the local HTML library and lists unseen posts.
    class CheckNewPosts
      def initialize(archive:, library:, selector:, limit: nil, reporter: Infrastructure::Reporter.new)
        @archive = archive
        @library = library
        @selector = selector
        @limit = limit
        @reporter = reporter
      end

      def call
        selection = @selector.call(@archive.all_posts, limit: nil)
        warn_unmatched(selection)

        new_posts = selection.posts.reject { |post| @library.saved?(post) }
        new_posts = apply_limit(new_posts)
        report(new_posts)
        new_posts
      end

      private

      def apply_limit(posts)
        return posts unless @limit

        @reporter.warn(
          "Warning: --limit #{@limit} counts only posts that are not saved yet."
        )
        posts.first(@limit)
      end

      def report(posts)
        if @reporter.json?
          @reporter.data(JSON.generate(posts.map { |post| serialize(post) }))
          return
        end

        if posts.empty?
          @reporter.data("No new posts.")
          return
        end

        @reporter.data("#{posts.size} new post(s):")
        posts.each do |post|
          @reporter.data("#{post.date_string}  #{post.slug}  #{post.title}")
        end
      end

      def serialize(post)
        {
          date: post.date_string,
          slug: post.slug,
          title: post.title,
          url: post.canonical_url
        }
      end

      def warn_unmatched(selection)
        return if selection.unmatched.empty?

        @reporter.warn "Warning: #{selection.unmatched.size} --post value(s) did not match any archive post."
      end
    end
  end
end
