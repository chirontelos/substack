# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "net/http"
require "uri"

module SubstackPdf
  module Infrastructure
    # Downloads remote images once and serves them as base64 data URIs.
    class MediaCache
      EXTENSIONS = {
        "image/jpeg" => ".jpg",
        "image/jpg" => ".jpg",
        "image/png" => ".png",
        "image/webp" => ".webp",
        "image/gif" => ".gif",
        "image/svg+xml" => ".svg",
        "image/avif" => ".avif"
      }.freeze

      CONTENT_TYPES = EXTENSIONS.invert.freeze
      MAX_BYTES = 25 * 1024 * 1024

      def initialize(directory, base_url:, user_agent: StealthBrowser::REAL_USER_AGENT)
        @directory = directory
        @base_url = base_url
        @user_agent = user_agent
        FileUtils.mkdir_p(@directory)
      end

      def data_uri(url, quiet: false)
        return url if url.start_with?("data:")

        key = Digest::SHA256.hexdigest(url)
        path = Dir.glob(File.join(@directory, "#{key}.*")).first

        unless path
          body, extension = fetch(url, quiet: quiet)
          return nil unless body

          path = File.join(@directory, "#{key}#{extension}")
          File.binwrite(path, body)
        end

        content_type = CONTENT_TYPES.fetch(File.extname(path).downcase, "application/octet-stream")
        "data:#{content_type};base64,#{Base64.strict_encode64(File.binread(path))}"
      end

      private

      def fetch(url, redirects: 5, quiet: false)
        uri = URI.parse(url.start_with?("//") ? "https:#{url}" : url)

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = @user_agent
        request["Accept"] = "image/avif,image/webp,image/png,image/jpeg,image/*,*/*;q=0.8"
        request["Referer"] = "#{@base_url}/"

        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: 15,
          read_timeout: 60
        ) { |http| http.request(request) }

        case response
        when Net::HTTPRedirection
          raise "too many redirects" if redirects <= 0

          location = response["location"]
          raise "redirect without location" if location.nil?

          fetch(URI.join(uri.to_s, location).to_s, redirects: redirects - 1, quiet: quiet)
        when Net::HTTPSuccess
          body = response.body.to_s.b
          raise "image is too large" if body.bytesize > MAX_BYTES

          content_type = response["content-type"].to_s.split(";").first
          extension = EXTENSIONS[content_type] || File.extname(uri.path)
          extension = ".jpg" if extension.nil? || extension.empty?
          [body, extension]
        else
          warn "  image failed (#{response.code}): #{url}" unless quiet
          nil
        end
      rescue StandardError => error
        warn "  image error: #{url} (#{error.class}: #{error.message})" unless quiet
        nil
      end
    end
  end
end
