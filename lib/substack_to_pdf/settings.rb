# frozen_string_literal: true

require "uri"

module SubstackPdf
  # Immutable user configuration shared by every use case.
  class Settings
    ORDERS = %w[asc desc].freeze
    POST_URL_PATTERN = %r{\A(?:https?://)?[^/\s]+/(?:.*/)?p/}i
    SUBSTACK_PROFILE_PATTERN = %r{\A/@([^/]+)}i
    SUBSTACK_HANDLE_PATTERN = /\A[a-z0-9][a-z0-9_-]*\z/i

    attr_reader :base_url, :author_slug, :output_dir, :limit, :only, :force, :first, :order

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
      resolved_base_url = base_url || base_url_from_only(@only)
      if resolved_base_url.nil? || resolved_base_url.to_s.strip.empty?
        raise ArgumentError, "publication is required; pass --publication, a --post URL, or --config"
      end

      @base_url = normalize_base_url(resolved_base_url)
      @author_slug = derive_author_slug(@base_url)
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

    private

    def normalize_base_url(value)
      raw = value.to_s.strip
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
    # publication subdomain (https://author.substack.com). Every other host,
    # including custom domains, keeps only its origin. Paths and query strings,
    # such as /archive, /posts or utm_* parameters, are never part of the base.
    def origin_for(uri)
      host = uri.host.to_s.downcase
      port = uri.port == uri.default_port ? "" : ":#{uri.port}"

      if %w[substack.com www.substack.com].include?(host)
        handle = substack_handle(uri.path)
        host = "#{handle}.substack.com" if handle
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
        next unless value.match?(POST_URL_PATTERN)

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
