# frozen_string_literal: true

module SubstackPdf
  module Infrastructure
    # Centralizes normal output, data output and warnings so that --quiet and
    # --json behave consistently across use cases.
    class Reporter
      def initialize(quiet: false, json: false)
        @quiet = quiet
        @json = json
      end

      def quiet?
        @quiet
      end

      def json?
        @json
      end

      # Progress and informational messages, silenced by --quiet.
      def info(message)
        $stdout.puts(message) unless @quiet
      end

      # Primary command output such as listings. Never silenced by --quiet.
      def data(message)
        $stdout.puts(message)
      end

      # Warnings always go to stderr, even in quiet or JSON mode.
      def warn(message)
        $stderr.puts(message)
      end
    end
  end
end
