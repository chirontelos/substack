# frozen_string_literal: true

require "fileutils"

module SubstackPdf
  module UseCases
    # Merges every selected saved article into one continuous PDF.
    class CombinePostsIntoPdf
      LIBERATION_FONT_GLOB = "/usr/share/fonts/truetype/liberation/Liberation*.ttf"
      TITLE = "L.S.C. - Posts"
      SUBJECT = "Coleção de posts"

      def initialize(
        library:,
        renderer:,
        error_log:,
        only: [],
        first: [],
        order: "asc",
        limit: nil,
        force: false,
        output_name: nil,
        output_path: nil,
        dry_run: false,
        reporter: Infrastructure::Reporter.new
      )
        @library = library
        @renderer = renderer
        @error_log = error_log
        @only = only
        @first = first
        @order = order
        @limit = limit
        @force = force
        @output_name = output_name
        @output_path = output_path
        @dry_run = dry_run
        @reporter = reporter
      end

      def call
        html_files = @library.html_archive.ordered(
          only: @only,
          first: @first,
          order: @order,
          limit: @limit
        )

        if html_files.empty?
          @reporter.warn "No HTML files found in #{@library.html_dir}."
          return nil
        end

        output_path = destination
        custom = @library.custom_combined_pdf?(name: @output_name, path: @output_path)

        if custom && File.exist?(output_path) && !@force
          @reporter.warn "Refusing to overwrite #{output_path}; use --force to replace it."
          return :exists
        end

        if @dry_run
          @reporter.info "Would combine #{html_files.size} HTML file(s) into #{output_path}"
          return output_path
        end

        FileUtils.mkdir_p(File.dirname(output_path))
        @reporter.info "Combining #{html_files.size} HTML file(s) into #{output_path}"

        combined_html = build_combined_html(html_files)
        @library.write(@library.combined_html_path, combined_html)

        @renderer.render(
          combined_html,
          output_path,
          title: TITLE,
          subject: SUBJECT,
          streaming: true,
          fonts: liberation_fonts
        )

        @reporter.info "  saved #{File.basename(output_path)} (#{File.size(output_path)} bytes)"
        output_path
      rescue StandardError => error
        @error_log.record("single PDF", error)
        @reporter.warn "  failed: #{error.class}: #{error.message}"
        nil
      end

      private

      def destination
        @library.combined_pdf_path(name: @output_name, path: @output_path)
      end

      def build_combined_html(html_files)
        sections = html_files.each_with_index.map do |html_path, index|
          article_html = Infrastructure::HtmlDocument.read(html_path).article_html
          section_class = index.zero? ? "post-section first" : "post-section"
          %(<section class="#{section_class}">#{article_html}</section>)
        end

        <<~HTML
          <!DOCTYPE html>
          <html lang="pt-BR">
          <head>
            <meta charset="utf-8">
            <title>#{TITLE}</title>
            <style>
          #{Infrastructure::ArticleStylesheet.for_combined_pdf.lines.map { |line| "    #{line}" }.join}
              .post-section {
                page-break-before: always;
              }

              .post-section.first {
                page-break-before: avoid;
              }

              body {
                background: transparent;
              }
            </style>
          </head>
          <body>
          #{sections.join("\n")}
          </body>
          </html>
        HTML
      end

      def liberation_fonts
        Dir[LIBERATION_FONT_GLOB].sort
      end
    end
  end
end
