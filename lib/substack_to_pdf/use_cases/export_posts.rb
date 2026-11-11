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
        pdf: true,
        limit: nil,
        dry_run: false,
        reporter: Infrastructure::Reporter.new
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
        @limit = limit
        @dry_run = dry_run
        @reporter = reporter
      end

      def call
        selection = @selector.call(@archive.all_posts, limit: nil)
        warn_unmatched(selection)

        posts = select_candidates(selection.posts)
        if posts.empty?
          @reporter.warn "No posts found."
          return []
        end

        @reporter.info "Processing #{posts.size} post(s) into #{@library.output_dir}"

        posts.each_with_index do |post, index|
          export_post(post, index, posts.size)
        end

        posts
      ensure
        @scraper&.close
      end

      private

      def select_candidates(posts)
        candidates = @force ? posts : posts.reject { |post| already_exported?(post) }
        candidates = apply_limit(candidates)
        candidates
      end

      def apply_limit(posts)
        return posts unless @limit

        if @force
          @reporter.warn "Warning: --limit #{@limit} counts all selected posts because --force is enabled."
        else
          @reporter.warn "Warning: --limit #{@limit} counts only posts that are not saved yet."
        end
        posts.first(@limit)
      end

      def export_post(post, index, total)
        html_path = @library.html_path(post)
        pdf_path = @library.pdf_path(post)

        if @dry_run
          report_dry_run(post, index, total, html_path, pdf_path)
          return
        end

        if already_exported?(post) && !@force
          skip_path = @pdf ? pdf_path : html_path
          @reporter.info "[#{index + 1}/#{total}] Skipping existing #{File.basename(skip_path)}"
          return
        end

        @reporter.info "[#{index + 1}/#{total}] #{post.display_title}"

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
            @reporter.info "  saved #{File.basename(pdf_path)} (#{File.size(pdf_path)} bytes)"
          else
            @reporter.info "  saved #{File.basename(html_path)} (#{File.size(html_path)} bytes)"
          end
        rescue StandardError => error
          @error_log.record(post, error)
          @reporter.warn "  failed: #{error.class}: #{error.message}"
          @scraper.reset if @scraper
        ensure
          sleep(rand(PAUSE_RANGE))
        end
      end

      def report_dry_run(post, index, total, html_path, pdf_path)
        if already_exported?(post) && !@force
          @reporter.info "[#{index + 1}/#{total}] Would skip existing #{post.slug}"
          return
        end

        @reporter.info "[#{index + 1}/#{total}] Would export #{post.display_title}"
        @reporter.info "  html: #{html_path}"
        @reporter.info "  pdf:  #{pdf_path}" if @pdf
      end

      def build_html(post)
        scraped_html = @scraper.fetch(post.canonical_url)
        @builder_factory.call(post).build(post, scraped_html)
      end

      def already_exported?(post)
        @library.exported?(post, require_pdf: @pdf)
      end

      def warn_unmatched(selection)
        return if selection.unmatched.empty?

        @reporter.warn "Warning: #{selection.unmatched.size} --post value(s) did not match any archive post."
      end
    end
  end
end
