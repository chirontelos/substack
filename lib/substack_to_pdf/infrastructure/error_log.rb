# frozen_string_literal: true

require "time"

module SubstackPdf
  module Infrastructure
    # Appends failures to a shared log without interrupting the batch.
    class ErrorLog
      def initialize(path)
        @path = path
      end

      def record(source, error)
        label = source.respond_to?(:canonical_url) ? source.canonical_url : source.to_s

        File.open(@path, "a") do |file|
          file.puts("[#{Time.now.iso8601}] #{label}")
          file.puts("  #{error.class}: #{error.message}")
          Array(error.backtrace).first(8).each { |line| file.puts("  #{line}") }
        end
      rescue StandardError
        nil
      end
    end
  end
end
