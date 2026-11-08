# frozen_string_literal: true

require "fileutils"

module SubstackPdf
  module Infrastructure
    # Owns the output directory layout and translates posts into file paths.
    class PostLibrary
      attr_reader :output_dir, :html_dir, :pdf_dir, :asset_dir, :error_log_path

      def initialize(output_dir:)
        @output_dir = File.expand_path(output_dir)
        @html_dir = File.join(@output_dir, "html")
        @pdf_dir = File.join(@output_dir, "pdf")
        @asset_dir = File.join(@output_dir, "assets")
        @error_log_path = File.join(@output_dir, "errors.log")

        [@output_dir, @html_dir, @pdf_dir, @asset_dir].each { |dir| FileUtils.mkdir_p(dir) }
      end

      def html_archive
        @html_archive ||= HtmlArchive.new(@html_dir)
      end

      def html_path(post)
        File.join(@html_dir, "#{filename_for(post)}.html")
      end

      def pdf_path(post)
        File.join(@pdf_dir, "#{filename_for(post)}.pdf")
      end

      def saved?(post)
        File.exist?(html_path(post))
      end

      def exist?(path)
        File.exist?(path)
      end

      def write(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      def combined_html_path
        File.join(@output_dir, "combined.html")
      end

      def default_combined_pdf_path
        File.join(@pdf_dir, "all-posts.pdf")
      end

      def filename_for(post)
        if post.published_at
          "#{post.published_at.strftime("%Y-%m-%d")}-#{slug_for(post)}"
        else
          "post-#{post.id}-#{post.slug}".gsub(/[^0-9A-Za-z._-]+/, "-")
        end
      end

      private

      def slug_for(post)
        slug = post.slug.to_s
        slug = "post-#{post.id}" if slug.empty?
        slug.gsub(/[^0-9A-Za-z._-]+/, "-").gsub(/\A-+|-+\z/, "")
      end
    end
  end
end
