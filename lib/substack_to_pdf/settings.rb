# frozen_string_literal: true

require "uri"

module SubstackPdf
  # Immutable user configuration shared by every use case.
  class Settings
    ORDERS = %w[asc desc].freeze

    attr_reader :base_url, :author_slug, :output_dir, :limit, :only, :force, :first, :order

    def initialize(
      output_dir:,
      base_url: DEFAULT_BASE_URL,
      limit: nil,
      only: [],
      force: false,
      pdf: true,
      first: [],
      order: "asc"
    )
      @base_url = normalize_base_url(base_url)
      @author_slug = derive_author_slug(@base_url)
      @output_dir = File.expand_path(output_dir)
      @limit = validate_limit(limit)
      @only = normalize_list(only).freeze
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

      port = uri.port == uri.default_port ? "" : ":#{uri.port}"
      "#{uri.scheme.downcase}://#{uri.host}#{port}"
    rescue URI::InvalidURIError
      raise ArgumentError, "invalid base URL: #{value}"
    end

    def derive_author_slug(url)
      host = URI.parse(url).host.to_s.downcase
      slug = host.sub(/\Awww\./, "").sub(/\.substack\.com\z/, "")
      slug = slug.gsub(/[^a-z0-9._-]+/, "-").gsub(/\A-+|-+\z/, "")
      slug.empty? ? "publication" : slug
    end

    def normalize_list(values)
      Array(values)
        .flat_map { |value| value.to_s.split(",") }
        .map(&:strip)
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
