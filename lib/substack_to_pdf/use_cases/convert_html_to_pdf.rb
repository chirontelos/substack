# frozen_string_literal: true

module SubstackPdf
  module UseCases
    # Converts HTML files that are already on disk into individual PDFs.
    class ConvertHtmlToPdf
      def initialize(
        library:,
        renderer:,
        error_log:,
        only: [],
        limit: nil,
        force: false,
        dry_run: false,
        reporter: Infrastructure::Reporter.new
      )
        @library = library
        @renderer = renderer
        @error_log = error_log
        @only = only
        @limit = limit
        @force = force
        @dry_run = dry_run
        @reporter = reporter
      end

      def call
        html_files = @library.html_archive.matching(only: @only)
        html_files = html_files.first(@limit) if @limit

        if html_files.empty?
          @reporter.warn "No HTML files found in #{@library.html_dir}."
          return []
        end

        if @dry_run
          @reporter.info "Would convert #{html_files.size} HTML file(s) to PDF..."
        else
          @reporter.info "Converting #{html_files.size} HTML file(s) to PDF..."
        end

        html_files.each_with_index do |html_path, index|
          convert(html_path, index, html_files.size)
        end

        html_files
      end

      private

      def convert(html_path, index, total)
        basename = File.basename(html_path, ".html")
        pdf_path = File.join(@library.pdf_dir, "#{basename}.pdf")

        if File.exist?(pdf_path) && !@force
          @reporter.info "[#{index + 1}/#{total}] Skipping existing #{File.basename(pdf_path)}"
          return
        end

        if @dry_run
          @reporter.info "[#{index + 1}/#{total}] Would convert #{basename} -> #{File.basename(pdf_path)}"
          return
        end

        @reporter.info "[#{index + 1}/#{total}] #{basename}"

        begin
          html = File.binread(html_path).force_encoding("UTF-8")
          document = Infrastructure::HtmlDocument.new(html, source: File.basename(html_path))
          title = document.title
          title = basename if title.nil? || title.empty?

          @renderer.render(html, pdf_path, title: title, subject: document.subtitle)
          @reporter.info "  saved #{File.basename(pdf_path)} (#{File.size(pdf_path)} bytes)"
        rescue StandardError => error
          @error_log.record(html_path, error)
          @reporter.warn "  failed: #{error.class}: #{error.message}"
        end
      end
    end
  end
end
