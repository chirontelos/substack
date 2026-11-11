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

      def initialize(output_dir:, author_slug:, create_dirs: true)
        @root_dir = File.expand_path(output_dir)
        @author_slug = author_slug
        @author_dir = File.join(@root_dir, @author_slug)
        @html_dir = File.join(@author_dir, "html")
        @pdf_dir = File.join(@author_dir, "pdf")
        @asset_dir = File.join(@author_dir, "assets")
        @single_pdf_dir = File.join(@root_dir, "single-pdfs")
        @error_log_path = File.join(@author_dir, "errors.log")

        if create_dirs
          [@root_dir, @author_dir, @html_dir, @pdf_dir, @asset_dir, @single_pdf_dir].each do |dir|
            FileUtils.mkdir_p(dir)
          end
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

      # Resolves the single-PDF destination:
      #   name -> <root>/single-pdfs/<name>.pdf
      #   path -> that exact path
      #   neither -> <root>/single-pdfs/<author>-all-posts.pdf
      def combined_pdf_path(name: nil, path: nil)
        explicit_path = path.to_s.strip
        return File.expand_path(explicit_path) unless explicit_path.empty?

        explicit_name = name.to_s.strip
        return default_combined_pdf_path if explicit_name.empty?

        explicit_name = "#{explicit_name}.pdf" unless explicit_name.downcase.end_with?(".pdf")
        File.join(@single_pdf_dir, explicit_name)
      end

      def custom_combined_pdf?(name: nil, path: nil)
        !path.to_s.strip.empty? || !name.to_s.strip.empty?
      end

      def default_combined_pdf_path
        File.join(@single_pdf_dir, "#{@author_slug}-all-posts.pdf")
      end

      # A post is fully exported when its HTML exists, and when the PDF also
      # exists if PDF output is enabled.
      def exported?(post, require_pdf: true)
        return false unless exist?(html_path(post))
        return true unless require_pdf

        exist?(pdf_path(post))
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
