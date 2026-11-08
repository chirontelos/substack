# frozen_string_literal: true

module SubstackPdf
  module UseCases
    # Downloads the selected posts, stores their HTML and optionally renders PDFs.
    class ExportPosts
      PAUSE_RANGE = 2.0..4.5

      def initialize(
        archive:,
        library:,
        scraper:,
        builder_factory:,
        renderer:,
        selector:,
        error_log:,
        force: false,
        pdf: true
      )
        @archive = archive
        @library = library
        @scraper = scraper
        @builder_factory = builder_factory
        @renderer = renderer
        @selector = selector
        @error_log = error_log
        @force = force
        @pdf = pdf
      end

      def call
        selection = @selector.call(@archive.all_posts)
        warn_unmatched(selection)

        posts = selection.posts
        if posts.empty?
          warn "No posts found."
          return
        end

        puts "Processing #{posts.size} post(s) into #{@library.output_dir}"

        posts.each_with_index do |post, index|
          export_post(post, index, posts.size)
        end
      ensure
        @scraper.close
      end

      private

      def export_post(post, index, total)
        html_path = @library.html_path(post)
        pdf_path = @library.pdf_path(post)

        if already_exported?(post) && !@force
          skip_path = @pdf ? pdf_path : html_path
          puts "[#{index + 1}/#{total}] Skipping existing #{File.basename(skip_path)}"
          return
        end

        puts "[#{index + 1}/#{total}] #{post.display_title}"

        begin
          html = build_html(post)
          @library.write(html_path, html)

          if @pdf
            @renderer.render(
              html,
              pdf_path,
              title: post.display_title,
              subject: post.subtitle
            )
            puts "  saved #{File.basename(pdf_path)} (#{File.size(pdf_path)} bytes)"
          else
            puts "  saved #{File.basename(html_path)} (#{File.size(html_path)} bytes)"
          end
        rescue StandardError => error
          @error_log.record(post, error)
          warn "  failed: #{error.class}: #{error.message}"
          @scraper.reset
        ensure
          sleep(rand(PAUSE_RANGE))
        end
      end

      def build_html(post)
        scraped_html = @scraper.fetch(post.canonical_url)
        @builder_factory.call(post).build(post, scraped_html)
      end

      def already_exported?(post)
        return false unless @library.exist?(@library.html_path(post))
        return true unless @pdf

        @library.exist?(@library.pdf_path(post))
      end

      def warn_unmatched(selection)
        return if selection.unmatched.empty?

        warn "Warning: #{selection.unmatched.size} --only value(s) did not match any archive post."
      end
    end
  end
end
