# frozen_string_literal: true

module SubstackPdf
  module UseCases
    # Converts HTML files that are already on disk into individual PDFs.
    class ConvertHtmlToPdf
      def initialize(library:, renderer:, error_log:, only: [], limit: nil, force: false)
        @library = library
        @renderer = renderer
        @error_log = error_log
        @only = only
        @limit = limit
        @force = force
      end

      def call
        html_files = @library.html_archive.matching(only: @only)
        html_files = html_files.first(@limit) if @limit

        if html_files.empty?
          warn "No HTML files found in #{@library.html_dir}."
          return
        end

        puts "Converting #{html_files.size} HTML file(s) to PDF..."

        html_files.each_with_index do |html_path, index|
          convert(html_path, index, html_files.size)
        end
      end

      private

      def convert(html_path, index, total)
        basename = File.basename(html_path, ".html")
        pdf_path = File.join(@library.pdf_dir, "#{basename}.pdf")

        if File.exist?(pdf_path) && !@force
          puts "[#{index + 1}/#{total}] Skipping existing #{File.basename(pdf_path)}"
          return
        end

        puts "[#{index + 1}/#{total}] #{basename}"

        begin
          html = File.binread(html_path).force_encoding("UTF-8")
          document = Infrastructure::HtmlDocument.new(html, source: File.basename(html_path))
          title = document.title
          title = basename if title.nil? || title.empty?

          @renderer.render(html, pdf_path, title: title, subject: document.subtitle)
          puts "  saved #{File.basename(pdf_path)} (#{File.size(pdf_path)} bytes)"
        rescue StandardError => error
          @error_log.record(html_path, error)
          warn "  failed: #{error.class}: #{error.message}"
        end
      end
    end
  end
end
