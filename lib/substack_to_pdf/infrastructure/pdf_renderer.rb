# frozen_string_literal: true

require "sghtmltopdf"

module SubstackPdf
  module Infrastructure
    # Adapter around sghtmltopdf, keeping PDF options in one place.
    class PdfRenderer
      PAGE_OPTIONS = {
        page_size: "A4",
        margin_top: "18mm",
        margin_bottom: "20mm",
        margin_left: "16mm",
        margin_right: "16mm",
        author: "L.S.C.",
        encoding: "utf-8",
        load_media_error_handling: "ignore"
      }.freeze

      def render(html, output_path, title:, subject:, streaming: false, fonts: nil)
        options = PAGE_OPTIONS.merge(
          title: title,
          subject: subject.to_s
        )
        options[:streaming] = true if streaming
        options[:font] = fonts if fonts && !fonts.empty?

        Sghtmltopdf.render_to_file(html, output_path, **options)
      end
    end
  end
end
