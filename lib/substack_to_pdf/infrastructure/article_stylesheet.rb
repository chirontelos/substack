# frozen_string_literal: true

module SubstackPdf
  module Infrastructure
    # Print stylesheet shared by individual articles and the combined PDF.
    module ArticleStylesheet
      CSS = <<~CSS
        @page {
          size: A4;
          margin: 18mm 16mm 20mm 16mm;
        }

        body {
          margin: 0;
          color: #1b1b1b;
          background: #ffffff;
          font-family: "DejaVu Serif", serif;
          font-size: 11.5pt;
          line-height: 1.55;
        }

        article {
          margin: 0;
          padding: 0;
        }

        .post-header {
          margin: 0 0 1.6em 0;
        }

        .post-title {
          margin: 0 0 0.25em 0;
          color: #111111;
          font-family: "DejaVu Sans", sans-serif;
          font-size: 25pt;
          font-weight: bold;
          line-height: 1.15;
        }

        .post-subtitle {
          margin: 0 0 0.7em 0;
          color: #555555;
          font-size: 13pt;
          font-style: italic;
          line-height: 1.3;
        }

        .post-meta {
          margin: 0 0 1.4em 0;
          padding-bottom: 0.8em;
          border-bottom: 1px solid #dddddd;
          color: #666666;
          font-family: "DejaVu Sans", sans-serif;
          font-size: 9pt;
        }

        .post-body {
          margin: 0;
          padding: 0;
        }

        h1, h2, h3, h4, h5, h6 {
          color: #111111;
          font-family: "DejaVu Sans", sans-serif;
          font-weight: bold;
          line-height: 1.25;
          page-break-after: avoid;
        }

        h1 { font-size: 22pt; margin: 1.3em 0 0.6em 0; }
        h2 { font-size: 17pt; margin: 1.3em 0 0.55em 0; }
        h3 { font-size: 14pt; margin: 1.2em 0 0.5em 0; }
        h4 { font-size: 12pt; margin: 1.1em 0 0.45em 0; }
        h5, h6 { font-size: 11pt; margin: 1em 0 0.4em 0; }

        p {
          margin: 0 0 1em 0;
          text-align: justify;
        }

        a {
          color: #0b5cad;
          text-decoration: underline;
        }

        strong, b {
          color: #111111;
        }

        em, i {
          font-style: italic;
        }

        img {
          display: block;
          max-width: 100%;
          height: auto;
          margin: 1.1em auto;
        }

        figure {
          margin: 1.3em 0;
          page-break-inside: avoid;
        }

        figcaption {
          margin-top: 0.45em;
          color: #666666;
          font-family: "DejaVu Sans", sans-serif;
          font-size: 9pt;
          line-height: 1.35;
          text-align: center;
        }

        .captioned-image-container {
          margin: 1.3em 0;
          page-break-inside: avoid;
        }

        .image2-inset {
          margin: 0;
        }

        .pullquote, blockquote {
          margin: 1.3em 0;
          padding: 0.2em 0 0.2em 1em;
          border-left: 3px solid #b8b8b8;
          color: #333333;
          font-style: italic;
          page-break-inside: avoid;
        }

        .pullquote p, blockquote p {
          margin-bottom: 0.5em;
        }

        ul, ol {
          margin: 0 0 1em 1.5em;
          padding: 0;
        }

        li {
          margin: 0 0 0.35em 0;
        }

        hr {
          margin: 1.6em 0;
          border: 0;
          border-top: 1px solid #cccccc;
        }

        table {
          width: 100%;
          margin: 1.2em 0;
          border-collapse: collapse;
        }

        th, td {
          padding: 0.4em 0.6em;
          border: 1px solid #cccccc;
          text-align: left;
          vertical-align: top;
        }

        th {
          background: #f2f2f2;
          font-family: "DejaVu Sans", sans-serif;
          font-weight: bold;
        }

        pre {
          margin: 1em 0;
          padding: 0.8em;
          background: #f4f4f4;
          white-space: pre-wrap;
          word-wrap: break-word;
          font-family: "DejaVu Sans Mono", monospace;
          font-size: 9pt;
        }

        code {
          padding: 0.1em 0.25em;
          background: #f4f4f4;
          font-family: "DejaVu Sans Mono", monospace;
          font-size: 9.5pt;
        }

        .video {
          text-align: center;
        }

        .video img {
          width: 100%;
          max-width: 640px;
          margin-bottom: 0.4em;
        }

        .embed {
          margin: 1em 0;
          padding: 0.7em;
          background: #f7f7f7;
          border: 1px solid #e0e0e0;
          font-size: 9.5pt;
          text-align: left;
        }

        .image-error {
          color: #a00000;
          font-size: 9pt;
        }
      CSS

      FONT_REPLACEMENTS = {
        '"DejaVu Serif", serif' => '"Liberation Serif"',
        '"DejaVu Sans", sans-serif' => '"Liberation Sans"',
        '"DejaVu Sans Mono", monospace' => '"Liberation Mono"'
      }.freeze

      module_function

      def for_combined_pdf
        FONT_REPLACEMENTS.reduce(CSS) { |css, (from, to)| css.gsub(from, to) }
      end
    end
  end
end
