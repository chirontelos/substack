# frozen_string_literal: true

require "json"
require "net/http"
require "nokogiri"
require "uri"

module SubstackPdf
  module Infrastructure
    # Reads a Substack profile activity feed. Profiles can contain regular
    # posts, notes, restacked posts and restacked notes, including accounts
    # that never created a publication website.
    class ProfileClient
      FEED_URL = "https://substack.com/api/v1/reader/feed/profile"
      PROFILE_URL = "https://substack.com/@"
      MAX_ATTEMPTS = 3
      TITLE_LIMIT = 120

      def initialize(handle:, user_agent:)
        @handle = handle.to_s.strip.sub(/\A@/, "")
        @user_agent = user_agent
      end

      def all_posts
        each_post.to_a
      end

      def each_post
        return enum_for(:each_post) unless block_given?

        seen = {}
        cursor = nil

        loop do
          page = fetch_page(cursor)
          items = Array(page["items"])
          break if items.empty?

          added = 0

          items.each do |item|
            post = build_post(item)
            next unless post

            key = post.dedupe_key
            next if seen[key]

            seen[key] = true
            added += 1
            yield post
          end

          break if added.zero?

          cursor = page["nextCursor"]
          break if cursor.nil? || cursor.to_s.empty?
        end
      end

      private

      def build_post(item)
        case item["type"].to_s
        when "post"
          build_post_entry(item)
        when "comment"
          build_comment_entry(item)
        end
      end

      def build_post_entry(item)
        data = item["post"]
        return nil unless data.is_a?(Hash)

        restacked = context_type(item) == "post_restack"
        date = restacked ? item.dig("context", "timestamp") : data["post_date"]

        Domain::Post.new(
          id: data["id"],
          title: data["title"].to_s.strip,
          subtitle: data["subtitle"].to_s.strip,
          slug: data["slug"].to_s,
          canonical_url: data["canonical_url"].to_s,
          published_at: Domain::Post.parse_time(date),
          kind: restacked ? :restack : :post,
          payload: {
            "item" => item,
            "post" => data,
            "publication" => item["publication"]
          }
        )
      end

      def build_comment_entry(item)
        comment = item["comment"]
        return nil unless comment.is_a?(Hash)

        restacked = context_type(item).include?("restack")
        date = restacked ? item.dig("context", "timestamp") : comment["date"]
        body = comment["body"].to_s
        name = comment["name"].to_s.strip
        title = if restacked
                  name.empty? ? "Restacked note" : "Restacked note by #{name}"
                else
                  title_from_body(body, comment["id"])
                end

        Domain::Post.new(
          id: comment["id"],
          title: title,
          subtitle: "",
          slug: "c-#{comment['id']}",
          canonical_url: note_url(comment),
          published_at: Domain::Post.parse_time(date),
          kind: restacked ? :restack : :note,
          payload: {
            "item" => item,
            "comment" => comment
          }
        )
      end

      def context_type(item)
        item.dig("context", "type").to_s
      end

      def title_from_body(body, id)
        line = body.lines.map(&:strip).find { |value| !value.empty? }
        line = "Note c-#{id}" if line.nil? || line.empty?
        line.length > TITLE_LIMIT ? "#{line[0, TITLE_LIMIT - 1]}…" : line
      end

      def note_url(comment)
        handle = comment["handle"] || comment.dig("user", "handle")
        return "https://substack.com/note/c-#{comment['id']}" if handle.to_s.empty?

        "https://substack.com/@#{handle}/note/c-#{comment['id']}"
      end

      def fetch_page(cursor)
        uri = URI.parse("#{FEED_URL}/#{profile_id}")
        uri.query = URI.encode_www_form(cursor: cursor) if cursor

        JSON.parse(request(uri, accept: "application/json").body)
      rescue StandardError => error
        warn "  profile error: #{error.class}: #{error.message}"
        {}
      end

      def profile_id
        @profile_id ||= fetch_profile_id
      end

      def fetch_profile_id
        uri = URI.parse("#{PROFILE_URL}#{@handle}")
        body = request(uri, accept: "text/html").body
        document = Nokogiri::HTML(body)
        preloads = document.at_css("script#preloads-json")
        raise "profile data not found for @#{@handle}" unless preloads

        id = JSON.parse(preloads.text).dig("profile", "id")
        raise "profile id not found for @#{@handle}" if id.nil?

        id
      end

      def request(uri, accept:, redirects: 5)
        attempts = 0

        begin
          attempts += 1
          http_request = Net::HTTP::Get.new(uri)
          http_request["User-Agent"] = @user_agent
          http_request["Accept"] = accept

          response = Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: 15,
            read_timeout: 60
          ) { |http| http.request(http_request) }

          case response
          when Net::HTTPSuccess
            response
          when Net::HTTPRedirection
            raise "too many redirects" if redirects <= 0

            location = response["location"]
            raise "redirect without location" if location.nil?

            request(URI.join(uri.to_s, location), accept: accept, redirects: redirects - 1)
          else
            raise "profile HTTP #{response.code}"
          end
        rescue StandardError
          retry if attempts < MAX_ATTEMPTS

          raise
        end
      end
    end
  end
end
