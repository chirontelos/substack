# frozen_string_literal: true

require "nokogiri"

module SubstackPdf
  module Infrastructure
    # Small read-only view over a generated article HTML file.
    class HtmlDocument
      def self.read(path)
        new(File.binread(path).force_encoding("UTF-8"), source: File.basename(path))
      end

      def initialize(html, source: nil)
        @html = html
        @source = source
      end

      def title
        document.at_css("title")&.text&.strip
      end

      def subtitle
        document.at_css(".post-subtitle")&.text&.strip.to_s
      end

      def article_html
        article = document.at_css("article")
        raise "article element not found in #{@source}" unless article

        article.to_html
      end

      private

      def document
        @document ||= Nokogiri::HTML(@html)
      end
    end
  end
end
