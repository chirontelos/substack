# frozen_string_literal: true

module SubstackPdf
  module Infrastructure
    # Merges several newest-first archives into one chronological stream.
    # Used to combine a publication archive with a profile activity feed.
    class CombinedArchive
      def initialize(archives)
        @archives = archives
      end

      def all_posts
        each_post.to_a
      end

      def each_post
        return enum_for(:each_post) unless block_given?

        streams = @archives.map { |archive| archive.each_post }
        heads = streams.map { |stream| [stream, next_post(stream)] }
        seen = {}

        loop do
          available = heads.each_index.select { |index| heads[index][1] }
          break if available.empty?

          index = available.max_by { |position| timestamp(heads[position][1]) }
          post = heads[index][1]
          heads[index][1] = next_post(heads[index][0])

          key = post.dedupe_key
          next if seen[key]

          seen[key] = true
          yield post
        end
      end

      private

      def next_post(stream)
        stream.next
      rescue StopIteration
        nil
      end

      def timestamp(post)
        post.published_at ? post.published_at.to_f : -Float::INFINITY
      end
    end
  end
end
