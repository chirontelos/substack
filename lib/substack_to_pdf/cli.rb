# frozen_string_literal: true

require "optparse"

module SubstackPdf
  # Command-line boundary: parses arguments and wires the use cases together.
  class CLI
    def initialize(argv)
      @argv = argv.dup
    end

    def run
      options = defaults
      parser = build_parser(options)
      parser.parse!(@argv)

      if options[:help]
        puts parser
        return 0
      end

      settings = build_settings(options)
      dispatch(options, settings)
      0
    rescue OptionParser::ParseError, ArgumentError => error
      warn "Error: #{error.message}"
      warn "Run with --help for usage."
      1
    end

    private

    def defaults
      {
        output_dir: File.join(SubstackPdf::ROOT, "output"),
        base_url: SubstackPdf::DEFAULT_BASE_URL,
        limit: nil,
        only: [],
        force: false,
        pdf: true,
        list: false,
        check_new: false,
        pdf_only: false,
        single_pdf: false,
        first: [],
        order: "asc",
        help: false
      }
    end

    def build_parser(options)
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby substack_to_pdf.rb [options]"

        parser.on("--output DIR", "Directory for HTML, PDFs and assets (default: ./output)") do |value|
          options[:output_dir] = value
        end

        parser.on("--base-url URL", "--publication URL", "Publication homepage or /archive URL (default: #{SubstackPdf::DEFAULT_BASE_URL})") do |value|
          options[:base_url] = value
        end

        parser.on("--limit N", Integer, "Process only the first N posts from the archive") do |value|
          options[:limit] = value
        end

        parser.on("--only SLUG_OR_URL", "Process only the matching post; repeat or use commas for several") do |value|
          options[:only].concat(value.split(",").map(&:strip).reject(&:empty?))
        end

        parser.on("--force", "Overwrite files that already exist") do
          options[:force] = true
        end

        parser.on("--no-pdf", "Only save the scraped HTML, without generating PDFs") do
          options[:pdf] = false
        end

        parser.on("--pdf-only", "Convert saved HTML files to PDFs, without scraping") do
          options[:pdf_only] = true
        end

        parser.on("--single-pdf [PATH]", "Combine saved HTML files into one PDF (default: output/pdf/all-posts.pdf)") do |value|
          options[:single_pdf] = value || true
        end

        parser.on("--first SLUG_OR_FILE", "Place this saved post first; repeat or use commas for several") do |value|
          options[:first].concat(value.split(",").map(&:strip).reject(&:empty?))
        end

        parser.on("--order ORDER", Settings::ORDERS, "Order numbered posts ascending or descending (default: asc)") do |value|
          options[:order] = value
        end

        parser.on("--list", "List the archive posts and exit") do
          options[:list] = true
        end

        parser.on("--check-new", "List archive posts that have no saved HTML yet and exit") do
          options[:check_new] = true
        end

        parser.on("-h", "--help", "Show this help") do
          options[:help] = true
        end
      end
    end

    def build_settings(options)
      Settings.new(
        output_dir: options[:output_dir],
        base_url: options[:base_url],
        limit: options[:limit],
        only: options[:only],
        force: options[:force],
        pdf: options[:pdf],
        first: options[:first],
        order: options[:order]
      )
    end

    def dispatch(options, settings)
      library = Infrastructure::PostLibrary.new(output_dir: settings.output_dir)
      archive = build_archive(settings)
      selector = Domain::PostSelector.new(only: settings.only, limit: settings.limit)
      error_log = Infrastructure::ErrorLog.new(library.error_log_path)

      if options[:list]
        UseCases::ListPosts.new(archive: archive, selector: selector).call
      elsif options[:check_new]
        UseCases::CheckNewPosts.new(archive: archive, library: library, selector: selector).call
      elsif options[:single_pdf]
        combine_posts(options, settings, library, error_log)
      elsif options[:pdf_only]
        convert_posts(settings, library, error_log)
      else
        export_posts(settings, library, archive, selector, error_log)
      end
    end

    def build_archive(settings)
      Infrastructure::ArchiveClient.new(
        base_url: settings.base_url,
        user_agent: Infrastructure::StealthBrowser::REAL_USER_AGENT
      )
    end

    def export_posts(settings, library, archive, selector, error_log)
      media_cache = Infrastructure::MediaCache.new(
        library.asset_dir,
        base_url: settings.base_url,
        user_agent: Infrastructure::StealthBrowser::REAL_USER_AGENT
      )
      builder_factory = lambda do |post|
        Infrastructure::ArticleBuilder.new(media_cache, base_url: post.canonical_url)
      end

      UseCases::ExportPosts.new(
        archive: archive,
        library: library,
        scraper: Infrastructure::ArticleScraper.new,
        builder_factory: builder_factory,
        renderer: Infrastructure::PdfRenderer.new,
        selector: selector,
        error_log: error_log,
        force: settings.force?,
        pdf: settings.pdf?
      ).call
    end

    def convert_posts(settings, library, error_log)
      UseCases::ConvertHtmlToPdf.new(
        library: library,
        renderer: Infrastructure::PdfRenderer.new,
        error_log: error_log,
        only: settings.only,
        limit: settings.limit,
        force: settings.force?
      ).call
    end

    def combine_posts(options, settings, library, error_log)
      output_path = options[:single_pdf] == true ? nil : options[:single_pdf]

      UseCases::CombinePostsIntoPdf.new(
        library: library,
        renderer: Infrastructure::PdfRenderer.new,
        error_log: error_log,
        only: settings.only,
        first: settings.first,
        order: settings.order,
        limit: settings.limit
      ).call(output_path: output_path)
    end
  end
end
