# frozen_string_literal: true

require "json"

module SubstackPdf
  module UseCases
    # Prints the archive posts that match the current filters.
    class ListPosts
      def initialize(archive:, selector:, reporter: Infrastructure::Reporter.new)
        @archive = archive
        @selector = selector
        @reporter = reporter
      end

      def call
        selection = @selector.call(@archive.all_posts)
        warn_unmatched(selection)

        rendered = render(selection.posts)
        @reporter.data(rendered) unless rendered.empty?
        selection.posts
      end

      private

      def render(posts)
        return JSON.generate(posts.map { |post| serialize(post) }) if @reporter.json?

        posts.map { |post| "#{post.date_string}  #{post.slug}  #{post.title}" }.join("\n")
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
