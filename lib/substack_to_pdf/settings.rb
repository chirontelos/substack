# frozen_string_literal: true

require "uri"

module SubstackPdf
  # Immutable user configuration shared by every use case.
  class Settings
    ORDERS = %w[asc desc].freeze
    POST_URL_PATTERN = %r{\A(?:https?://)?[^/\s]+/(?:.*/)?p/}i
    SOURCE_URL_PATTERN = %r{\A(?:https?://)?[^/\s]+/(?:.*/)?(?:p|note)/}i
    SUBSTACK_PROFILE_PATTERN = %r{\A/@([^/]+)}i
    SUBSTACK_HANDLE_PATTERN = /\A[a-z0-9][a-z0-9_-]*\z/i

    attr_reader :base_url, :author_slug, :output_dir, :limit, :only, :force, :first,
                :order, :profile_handle

    def initialize(
      output_dir:,
      base_url: nil,
      limit: nil,
      only: [],
      force: false,
      pdf: true,
      first: [],
      order: "asc"
    )
      @only = normalize_list(only).freeze
      if base_url && base_url.to_s.strip.match?(SOURCE_URL_PATTERN)
        raise ArgumentError, "publication cannot be a post or note URL; pass it with --post instead"
      end

      resolved_base_url = base_url || base_url_from_only(@only)
      if resolved_base_url.nil? || resolved_base_url.to_s.strip.empty?
        raise ArgumentError, "publication is required; pass --publication, --author, a --post URL, or --config"
      end

      @base_url = normalize_base_url(resolved_base_url)
      @author_slug = derive_author_slug(@base_url)
      @profile_handle = self.class.profile_handle_for(@base_url)
      @output_dir = File.expand_path(output_dir)
      @limit = validate_limit(limit)
      @force = !!force
      @pdf = !!pdf
      @first = normalize_list(first).freeze
      @order = validate_order(order)
      freeze
    end

    def pdf?
      @pdf
    end

    def force?
      @force
    end

    # Substack-hosted authors expose a reader activity feed (posts, notes,
    # restacks) at their <handle>.substack.com publication. Custom domains have
    # no reliable profile handle, so only Substack subdomains qualify.
    def self.profile_handle_for(url)
      host = URI.parse(url).host.to_s.downcase
      return nil unless host.end_with?(".substack.com")
      return nil if %w[substack.com www.substack.com].include?(host)

      handle = host.delete_suffix(".substack.com")
      handle.match?(SUBSTACK_HANDLE_PATTERN) ? handle : nil
    rescue URI::InvalidURIError
      nil
    end

    private

    def normalize_base_url(value)
      raw = value.to_s.strip
      raise ArgumentError, "base URL cannot be empty" if raw.empty?

      raw = raw.sub(/\A@/, "")
      raise ArgumentError, "base URL cannot be empty" if raw.empty?

      unless raw.match?(%r{\Ahttps?://}i)
        if raw.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
          raise ArgumentError, "base URL must use http or https"
        end

        raw = "https://#{raw}"
      end

      uri = URI.parse(raw)

      unless uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty?
        raise ArgumentError, "base URL must be an http(s) URL"
      end

      origin_for(uri)
    rescue URI::InvalidURIError
      raise ArgumentError, "invalid base URL: #{value}"
    end

    # Substack profile URLs (https://substack.com/@author) point at the
    # publication subdomain (https://author.substack.com). Bare inputs such as
    # `kaisoku`, `@kaisoku` or `kaisoku/archive` are treated as handles too.
    # Every other host, including custom domains, keeps only its origin. Paths
    # and query strings, such as /archive, /posts or utm_* parameters, are never
    # part of the base.
    def origin_for(uri)
      host = uri.host.to_s.downcase
      port = uri.port == uri.default_port ? "" : ":#{uri.port}"

      if %w[substack.com www.substack.com].include?(host)
        handle = substack_handle(uri.path)
        host = "#{handle}.substack.com" if handle
      elsif host != "localhost" && host.match?(SUBSTACK_HANDLE_PATTERN)
        host = "#{host}.substack.com"
      end

      "#{uri.scheme.downcase}://#{host}#{port}"
    end

    def substack_handle(path)
      match = path.to_s.match(SUBSTACK_PROFILE_PATTERN)
      return nil unless match

      handle = match[1].downcase
      handle.match?(SUBSTACK_HANDLE_PATTERN) ? handle : nil
    end

    # When --publication is omitted, a full post URL in --post also identifies
    # the publication, so `--post https://author.substack.com/p/slug` works
    # on its own.
    def base_url_from_only(references)
      origins = references.filter_map do |reference|
        value = reference.to_s.strip
        next unless value.match?(SOURCE_URL_PATTERN)

        value = "https://#{value}" unless value.match?(%r{\Ahttps?://}i)
        normalize_base_url(value)
      rescue ArgumentError
        nil
      end.uniq

      return nil if origins.empty?
      if origins.size > 1
        raise ArgumentError, "post URLs refer to more than one publication: #{origins.join(", ")}"
      end

      origins.first
    end

    def derive_author_slug(url)
      host = URI.parse(url).host.to_s.downcase
      slug = host.sub(/\Awww\./, "").sub(/\.substack\.com\z/, "")
      slug = slug.gsub(/[^a-z0-9._-]+/, "-").gsub(/\A-+|-+\z/, "")
      slug.empty? ? "publication" : slug
    end

    # Values are split once by the CLI. Settings only normalizes what it receives.
    def normalize_list(values)
      Array(values)
        .map { |value| value.to_s.strip }
        .reject(&:empty?)
        .uniq
    end

    def validate_limit(value)
      return nil if value.nil?

      limit = Integer(value)
      raise ArgumentError, "limit must be zero or greater" if limit.negative?

      limit
    end

    def validate_order(value)
      order = value.to_s
      unless ORDERS.include?(order)
        raise ArgumentError, "order must be one of: #{ORDERS.join(", ")}"
      end

      order
    end
  end
end
