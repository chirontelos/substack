# frozen_string_literal: true

require "fileutils"

module SubstackPdf
  module Infrastructure
    # Owns the output directory layout and translates posts into file paths.
    #
    # Layout:
    #   <root>/<author>/html
    #   <root>/<author>/pdf
    #   <root>/<author>/assets
    #   <root>/<author>/errors.log
    #   <root>/<author>/combined.html
    #   <root>/single-pdfs/<author>-all-posts.pdf
    class PostLibrary
      attr_reader :root_dir, :author_slug, :author_dir, :html_dir, :pdf_dir,
                  :asset_dir, :single_pdf_dir, :error_log_path

      def initialize(output_dir:, author_slug:)
        @root_dir = File.expand_path(output_dir)
        @author_slug = author_slug
        @author_dir = File.join(@root_dir, @author_slug)
        @html_dir = File.join(@author_dir, "html")
        @pdf_dir = File.join(@author_dir, "pdf")
        @asset_dir = File.join(@author_dir, "assets")
        @single_pdf_dir = File.join(@root_dir, "single-pdfs")
        @error_log_path = File.join(@author_dir, "errors.log")

        [@root_dir, @author_dir, @html_dir, @pdf_dir, @asset_dir, @single_pdf_dir].each do |dir|
          FileUtils.mkdir_p(dir)
        end
      end

      # Kept as a convenience for callers that want to report the author folder.
      def output_dir
        @author_dir
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
        File.join(@author_dir, "combined.html")
      end

      # Resolves the --single-pdf value:
      #   nil/bare name  -> <root>/single-pdfs/<name or author>-all-posts.pdf
      #   path with dirs -> that exact path
      def combined_pdf_path(value = nil)
        return default_combined_pdf_path if value.nil? || value == true

        name = value.to_s.strip
        return default_combined_pdf_path if name.empty?

        unless File.dirname(name) == "."
          return File.expand_path(name)
        end

        name = "#{name}.pdf" unless name.downcase.end_with?(".pdf")
        File.join(@single_pdf_dir, name)
      end

      def default_combined_pdf_path
        File.join(@single_pdf_dir, "#{@author_slug}-all-posts.pdf")
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
