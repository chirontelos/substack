# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module SubstackPdf
  module Infrastructure
    # Reads the public Substack archive API and returns domain posts.
    #
    # The API currently paginates with an opaque cursor, but older deployments
    # returned a bare array and paginated with an offset. Both shapes are handled.
    class ArchiveClient
      PAGE_SIZE = 25
      MAX_POSTS = 10_000
      MAX_ATTEMPTS = 3

      def initialize(base_url:, user_agent:, page_size: PAGE_SIZE)
        @base_url = base_url
        @user_agent = user_agent
        @page_size = page_size
      end

      def all_posts
        posts = []
        seen = {}
        cursor = nil
        offset = 0
        legacy = false

        loop do
          page = fetch_page(cursor: cursor, offset: offset, legacy: legacy)
          batch, next_cursor, legacy = normalize_page(page)

          break if batch.empty?

          added = append_unique(posts, seen, batch)
          break if added.zero?

          if legacy
            offset += batch.length
            break if offset > MAX_POSTS
          else
            break if next_cursor.nil? || next_cursor.empty?
            break if posts.size >= MAX_POSTS

            cursor = next_cursor
          end
        end

        posts
      end

      private

      def normalize_page(page)
        return [page, nil, true] if page.is_a?(Array)

        data = page.is_a?(Hash) ? page : {}
        [Array(data["posts"]), data["nextCursor"], false]
      end

      def append_unique(posts, seen, batch)
        added = 0

        batch.each do |data|
          post = Domain::Post.from_archive(data)
          next if seen[post.id]

          seen[post.id] = true
          posts << post
          added += 1
        end

        added
      end

      def fetch_page(cursor:, offset:, legacy:)
        uri = archive_uri(cursor: cursor, offset: offset, legacy: legacy)
        attempts = 0

        begin
          attempts += 1
          request = Net::HTTP::Get.new(uri)
          request["User-Agent"] = @user_agent
          request["Accept"] = "application/json"

          response = Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: 15,
            read_timeout: 60
          ) { |http| http.request(request) }

          raise "archive HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        rescue StandardError => error
          retry if attempts < MAX_ATTEMPTS

          warn "  archive error: #{error.class}: #{error.message}"
          []
        end
      end

      def archive_uri(cursor:, offset:, legacy:)
        uri = URI.parse("#{@base_url}/api/v1/archive")
        params = { sort: "new", search: "", limit: @page_size }

        if legacy
          params[:offset] = offset
        elsif cursor
          params[:cursor] = cursor
        end

        uri.query = URI.encode_www_form(params)
        uri
      end
    end
  end
end
