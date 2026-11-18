# frozen_string_literal: true

require "time"

module SubstackPdf
  module Domain
    # A single publication post, independent of how it was obtained.
    class Post
      NOTE_REFERENCE_PATTERN = %r{\A(?:https?://)?[^/\s]+/(?:.*/)?note/([^/?#]+)}i

      attr_reader :id, :title, :subtitle, :slug, :canonical_url, :published_at,
                  :kind, :payload

      def self.from_archive(data)
        new(
          id: data["id"],
          title: data["title"].to_s.strip,
          subtitle: data["subtitle"].to_s.strip,
          slug: data["slug"].to_s,
          canonical_url: data["canonical_url"].to_s,
          published_at: parse_time(data["post_date"])
        )
      end

      def self.parse_time(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # Turns a slug, URL or URL path into the canonical slug used by the archive.
      def self.normalize_reference(value)
        raw = value.to_s
        note = raw.match(NOTE_REFERENCE_PATTERN)
        return note[1] if note

        raw.sub(%r{\A(?:https?://)?[^/\s]+/(?:.*/)?p/}i, "")
           .split(/[?#]/)
           .first
           .to_s
           .sub(%r{/+\z}, "")
      end

      def initialize(
        id:,
        title:,
        subtitle:,
        slug:,
        canonical_url:,
        published_at:,
        kind: :post,
        payload: nil
      )
        @id = id
        @title = title.to_s
        @subtitle = subtitle.to_s
        @slug = slug.to_s
        @canonical_url = canonical_url.to_s
        @published_at = published_at
        @kind = kind
        @payload = payload
      end

      def note?
        kind == :note
      end

      def restack?
        kind == :restack
      end

      # Notes and restacks are rendered from the feed payload instead of being
      # scraped from an article page.
      def feed_entry?
        kind != :post
      end

      def dedupe_key
        value = canonical_url.to_s
        value.empty? ? "#{kind}:#{id}" : value
      end

      def display_title
        title.empty? ? slug : title
      end

      def date_string
        published_at ? published_at.strftime("%Y-%m-%d") : ""
      end

      def matches?(reference)
        value = reference.to_s.strip
        return false if value.empty?

        value == slug ||
          value == canonical_url ||
          self.class.normalize_reference(value) == slug
      end

      def ==(other)
        other.is_a?(Post) && id == other.id
      end

      alias eql? ==

      def hash
        id.hash
      end
    end
  end
end
