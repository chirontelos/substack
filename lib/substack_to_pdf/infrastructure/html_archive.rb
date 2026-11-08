# frozen_string_literal: true

module SubstackPdf
  module Infrastructure
    # File-system query object for the saved HTML articles.
    class HtmlArchive
      def initialize(html_dir)
        @html_dir = html_dir
      end

      def files
        Dir[File.join(@html_dir, "*.html")].sort
      end

      def matching(only: [])
        return files if only.empty?

        files.select { |path| only.any? { |value| matches?(path, value) } }
      end

      def ordered(only: [], first: [], order: "asc", limit: nil)
        all_files = files
        filtered = only.empty? ? all_files : all_files.select do |path|
          only.any? { |value| matches?(path, value) }
        end

        first_files = first.filter_map do |item|
          match = find(item, all_files)
          warn "Warning: --first #{item} did not match any HTML file." unless match
          match
        end.uniq

        remaining = (filtered | first_files) - first_files
        ordered = first_files + sort_files(remaining, order: order)
        limit ? ordered.first(limit) : ordered
      end

      def find(reference, candidates = files)
        normalized = normalize(reference)
        candidates.find do |path|
          basename = File.basename(path, ".html")
          File.basename(path) == reference.to_s ||
            basename == normalized ||
            basename.end_with?("-#{normalized}")
        end
      end

      def matches?(path, reference)
        basename = File.basename(path, ".html")
        normalized = normalize(reference)

        basename == reference.to_s ||
          basename == normalized ||
          basename.end_with?("-#{normalized}")
      end

      private

      def normalize(reference)
        Domain::Post.normalize_reference(reference)
      end

      def sort_files(paths, order:)
        numbered, unnumbered = paths.partition { |path| number_from_filename(path) }

        ordered = numbered.sort_by do |path|
          number = number_from_filename(path)
          order == "desc" ? [-number, File.basename(path)] : [number, File.basename(path)]
        end

        ordered + unnumbered.sort_by { |path| File.basename(path) }
      end

      def number_from_filename(path)
        slug = File.basename(path, ".html").sub(/\A\d{4}-\d{2}-\d{2}-/, "")
        match = slug.match(/-(\d+)\z/)
        match && match[1].to_i
      end
    end
  end
end
