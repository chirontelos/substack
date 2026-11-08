# frozen_string_literal: true

module SubstackPdf
  module Infrastructure
    # Fetches the rendered article HTML, recycling the browser periodically.
    class ArticleScraper
      DEFAULT_RESTART_EVERY = 20

      def initialize(restart_every: DEFAULT_RESTART_EVERY, browser_factory: -> { StealthBrowser.new })
        @restart_every = restart_every
        @browser_factory = browser_factory
        @browser = nil
        @uses = 0
      end

      def fetch(url)
        restart_if_stale
        @uses += 1

        browser.visit(url)
        html = browser.article_html
        raise "article HTML was empty" if html.nil? || html.empty?

        html
      rescue StandardError
        reset
        raise
      end

      def reset
        @browser&.quit
      rescue StandardError
        nil
      ensure
        @browser = nil
        @uses = 0
      end

      def close
        reset
      end

      private

      def browser
        @browser ||= @browser_factory.call
      end

      def restart_if_stale
        reset if @browser && @uses >= @restart_every
      end
    end
  end
end
