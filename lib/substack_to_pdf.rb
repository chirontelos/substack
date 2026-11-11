# frozen_string_literal: true

module SubstackPdf
  ROOT = File.expand_path("..", __dir__)
  VERSION = "2.1.0"
end

require_relative "substack_to_pdf/settings"

require_relative "substack_to_pdf/domain/post"
require_relative "substack_to_pdf/domain/post_selector"

require_relative "substack_to_pdf/infrastructure/stealth_browser"
require_relative "substack_to_pdf/infrastructure/archive_client"
require_relative "substack_to_pdf/infrastructure/article_scraper"
require_relative "substack_to_pdf/infrastructure/media_cache"
require_relative "substack_to_pdf/infrastructure/article_stylesheet"
require_relative "substack_to_pdf/infrastructure/article_builder"
require_relative "substack_to_pdf/infrastructure/html_document"
require_relative "substack_to_pdf/infrastructure/html_archive"
require_relative "substack_to_pdf/infrastructure/pdf_renderer"
require_relative "substack_to_pdf/infrastructure/error_log"
require_relative "substack_to_pdf/infrastructure/post_library"
require_relative "substack_to_pdf/infrastructure/reporter"

require_relative "substack_to_pdf/use_cases/export_posts"
require_relative "substack_to_pdf/use_cases/list_posts"
require_relative "substack_to_pdf/use_cases/check_new_posts"
require_relative "substack_to_pdf/use_cases/convert_html_to_pdf"
require_relative "substack_to_pdf/use_cases/combine_posts_into_pdf"

require_relative "substack_to_pdf/cli"
