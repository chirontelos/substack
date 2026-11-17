# frozen_string_literal: true

require "json"

module SubstackPdf
  module UseCases
    # Runs --check-new against every author folder already present under the
    # output root. Used when no --publication is provided.
    class CheckNewPostsForAllAuthors
      Result = Struct.new(:author, :publication_url, :posts, keyword_init: true)

      def initialize(
        root_dir:,
        selector:,
        limit: nil,
        reporter: Infrastructure::Reporter.new,
        archive_factory: nil,
        library_factory: nil
      )
        @root_dir = File.expand_path(root_dir)
        @selector = selector
        @limit = limit
        @reporter = reporter
        @archive_factory = archive_factory || method(:build_archive)
        @library_factory = library_factory || method(:build_library)
      end

      def call
        authors = author_slugs

        if authors.empty?
          @reporter.warn "No downloaded authors found in #{@root_dir}."
          @reporter.data("[]") if @reporter.json?
          return []
        end

        results = apply_limit(authors.filter_map { |author| check_author(author) })
        report(results)
        results.flat_map(&:posts)
      end

      private

      def author_slugs
        return [] unless Dir.exist?(@root_dir)

        Dir.children(@root_dir).sort.filter_map do |name|
          next if name.start_with?(".")
          next unless File.directory?(File.join(@root_dir, name, "html"))

          name
        end
      end

      def check_author(author)
        publication_url = publication_url_for(author)
        if publication_url.nil?
          @reporter.warn "Skipping #{File.join(@root_dir, author)}: cannot infer its publication URL."
          return nil
        end

        check = CheckNewPosts.new(
          archive: @archive_factory.call(publication_url),
          library: @library_factory.call(author),
          selector: @selector,
          reporter: @reporter
        )

        Result.new(
          author: author,
          publication_url: publication_url,
          posts: check.new_posts(report_unmatched: false)
        )
      end

      def apply_limit(results)
        return results unless @limit

        @reporter.warn(
          "Warning: --limit #{@limit} counts only posts that are not saved yet."
        )

        remaining = @limit
        results.filter_map do |result|
          next unless remaining.positive?

          posts = result.posts.first(remaining)
          remaining -= posts.size
          Result.new(author: result.author, publication_url: result.publication_url, posts: posts)
        end
      end

      def publication_url_for(author)
        return nil if author.casecmp("substack.com").zero?

        host = author.include?(".") ? author : "#{author}.substack.com"
        "https://#{host}"
      end

      def build_archive(publication_url)
        Infrastructure::ArchiveClient.new(
          base_url: publication_url,
          user_agent: Infrastructure::StealthBrowser::REAL_USER_AGENT
        )
      end

      def build_library(author)
        Infrastructure::PostLibrary.new(
          output_dir: @root_dir,
          author_slug: author,
          create_dirs: false
        )
      end

      def report(results)
        if @reporter.json?
          payload = results.flat_map do |result|
            result.posts.map { |post| serialize(post).merge(author: result.author) }
          end
          @reporter.data(JSON.generate(payload))
          return
        end

        if results.all? { |result| result.posts.empty? }
          @reporter.data("No new posts.")
          return
        end

        results.each do |result|
          if result.posts.empty?
            @reporter.data("#{result.author}: no new posts.")
            next
          end

          @reporter.data("#{result.author}: #{result.posts.size} new post(s):")
          result.posts.each do |post|
            @reporter.data("#{post.date_string}  #{post.slug}")
          end
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
    end
  end
end
