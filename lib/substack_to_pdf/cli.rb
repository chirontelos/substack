# frozen_string_literal: true

require "optparse"
require "yaml"

module SubstackPdf
  # Command-line boundary: parses arguments and wires the use cases together.
  class CLI
    class UsageError < StandardError; end

    MODES = {
      list: "--list",
      check_new: "--check-new",
      single_pdf: "--single-pdf",
      pdf_only: "--pdf-only"
    }.freeze

    CONFIG_KEYS = %w[
      publication root limit post first order force html_only quiet json
    ].freeze

    BOOLEAN_CONFIG_KEYS = %w[force html_only quiet json].freeze

    def initialize(argv)
      @argv = argv.dup
    end

    def run
      options = defaults
      parser = build_parser(options)
      parser.parse!(@argv)

      if options[:help]
        puts parser
        return 0
      end

      if options[:version]
        puts "substack_to_pdf #{SubstackPdf::VERSION}"
        return 0
      end

      config = options[:config_path] ? load_config(options[:config_path]) : {}
      apply_config!(options, config)
      normalize_lists!(options)
      reporter = Infrastructure::Reporter.new(quiet: options[:quiet], json: options[:json])
      mode = validate_options!(options, reporter)

      settings = build_settings(options)
      result = dispatch(mode, options, settings, reporter)
      exit_code_for(result, options)
    rescue OptionParser::ParseError, UsageError => error
      warn "Error: #{error.message}"
      warn "Run with --help for usage."
      1
    end

    private

    def defaults
      {
        config_path: nil,
        root_dir: nil,
        publication: nil,
        limit: nil,
        posts: [],
        force: false,
        html_only: false,
        list: false,
        check_new: false,
        pdf_only: false,
        single_pdf: false,
        single_pdf_name: nil,
        single_pdf_path: nil,
        first: [],
        order: "asc",
        order_given: false,
        dry_run: false,
        allow_empty: false,
        quiet: false,
        json: false,
        version: false,
        help: false
      }
    end

    def build_parser(options)
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby substack_to_pdf.rb [options]"

        parser.separator ""
        parser.separator "Configuration:"

        parser.on("--config FILE", "Load defaults from a YAML configuration file") do |value|
          options[:config_path] = value
        end

        parser.separator ""
        parser.separator "Publication and output:"

        parser.on("--root DIR", "Root directory for generated files (default: ./output)") do |value|
          options[:root_dir] = value
        end

        parser.on("--publication URL", "Publication homepage or /archive URL (required unless set by --config or a --post URL)") do |value|
          options[:publication] = value
        end

        parser.separator ""
        parser.separator "Selection:"

        parser.on("--post SLUG_OR_URL", "Process only the matching post; repeat or use commas. A post URL also selects its publication") do |value|
          options[:posts] << value
        end

        parser.on("--limit N", Integer, "Process at most N posts (unsaved only for export and --check-new)") do |value|
          options[:limit] = value
        end

        parser.separator ""
        parser.separator "Modes (choose at most one):"

        parser.on("--list", "List the archive posts and exit") do
          options[:list] = true
        end

        parser.on("--check-new", "List archive posts that have no saved HTML yet and exit") do
          options[:check_new] = true
        end

        parser.on("--pdf-only", "Convert saved HTML files to PDFs, without scraping") do
          options[:pdf_only] = true
        end

        parser.on("--single-pdf", "Combine saved HTML files into one PDF") do
          options[:single_pdf] = true
        end

        parser.separator ""
        parser.separator "Single PDF options:"

        parser.on("--name NAME", "Custom file name inside <root>/single-pdfs") do |value|
          options[:single_pdf_name] = value
        end

        parser.on("--path PATH", "Exact output path for the combined PDF") do |value|
          options[:single_pdf_path] = value
        end

        parser.on("--first SLUG_OR_FILE", "Place this saved post first; repeat or use commas for several") do |value|
          options[:first] << value
        end

        parser.on("--order ORDER", Settings::ORDERS, "Order numbered posts ascending or descending (default: asc)") do |value|
          options[:order] = value
          options[:order_given] = true
        end

        parser.separator ""
        parser.separator "Behavior:"

        parser.on("--force", "Overwrite existing files, including custom single PDFs") do
          options[:force] = true
        end

        parser.on("--html-only", "Save only the scraped HTML, without generating PDFs") do
          options[:html_only] = true
        end

        parser.on("--dry-run", "Show what would be done without writing files or launching the browser") do
          options[:dry_run] = true
        end

        parser.on("--allow-empty", "Exit successfully when no posts or files are selected") do
          options[:allow_empty] = true
        end

        parser.on("--quiet", "Suppress progress messages (warnings and data are still printed)") do
          options[:quiet] = true
        end

        parser.on("--json", "Emit JSON for --list and --check-new") do
          options[:json] = true
        end

        parser.separator ""
        parser.separator "General:"

        parser.on("--version", "Show the program version") do
          options[:version] = true
        end

        parser.on("-h", "--help", "Show this help") do
          options[:help] = true
        end
      end
    end

    def load_config(path)
      raw = File.read(path)
      data = YAML.safe_load(raw, permitted_classes: [], aliases: false) || {}
      raise UsageError, "config file must contain a mapping: #{path}" unless data.is_a?(Hash)

      config = data.transform_keys(&:to_s)
      unknown = config.keys - CONFIG_KEYS
      unknown.each { |key| warn "Warning: unknown config key: #{key}" }
      validate_config!(config, path)
      config
    rescue Errno::ENOENT
      raise UsageError, "config file not found: #{path}"
    rescue Errno::EACCES
      raise UsageError, "config file is not readable: #{path}"
    rescue Psych::Exception => error
      raise UsageError, "invalid config file #{path}: #{error.message}"
    end

    def validate_config!(config, path)
      BOOLEAN_CONFIG_KEYS.each do |key|
        next unless config.key?(key)
        next if [true, false].include?(config[key])

        raise UsageError, "config key #{key} must be true or false in #{path}"
      end

      %w[post first].each do |key|
        next unless config.key?(key)

        value = config[key]
        valid = value.is_a?(String) || value.nil? ||
                (value.is_a?(Array) && value.all? { |item| item.is_a?(String) })
        next if valid

        raise UsageError, "config key #{key} must be a string or a list of strings in #{path}"
      end

      %w[publication root order].each do |key|
        next unless config.key?(key)
        next if config[key].is_a?(String)

        raise UsageError, "config key #{key} must be a string in #{path}"
      end
    end

    # CLI values win over config values; config wins over built-in defaults.
    def apply_config!(options, config)
      options[:root_dir] ||= config["root"]
      options[:publication] ||= config["publication"]
      options[:limit] ||= config["limit"]
      options[:order] = config["order"] if !options[:order_given] && config.key?("order")
      options[:posts] = Array(config["post"]) if options[:posts].empty? && config.key?("post")
      options[:first] = Array(config["first"]) if options[:first].empty? && config.key?("first")

      options[:force] = true if config["force"]
      options[:html_only] = true if config["html_only"]
      options[:quiet] = true if config["quiet"]
      options[:json] = true if config["json"]

      options[:root_dir] ||= File.join(SubstackPdf::ROOT, "output")
    end

    # The CLI is the single place that splits comma-separated values. Settings
    # and use cases treat the resulting array as final.
    def normalize_lists!(options)
      options[:posts] = split_list(options[:posts])
      options[:first] = split_list(options[:first])
    end

    def split_list(values)
      Array(values)
        .flat_map { |value| value.to_s.split(",") }
        .map(&:strip)
        .reject(&:empty?)
        .uniq
    end

    def validate_options!(options, reporter)
      mode = selected_mode(options)

      if options[:single_pdf_name] && options[:single_pdf_path]
        raise UsageError, "--name and --path cannot be used together"
      end

      warn_irrelevant_flags(options, mode, reporter)
      mode
    end

    def selected_mode(options)
      modes = MODES.keys.select { |key| options[key] }
      return :export if modes.empty?
      return modes.first if modes.size == 1

      names = modes.map { |key| MODES[key] }
      raise UsageError, "#{names.join(" and ")} cannot be used together"
    end

    def warn_irrelevant_flags(options, mode, reporter)
      warn_if(reporter, mode != :export && options[:html_only], "--html-only", mode)
      warn_if(reporter, mode != :single_pdf && !options[:first].empty?, "--first", mode)
      warn_if(reporter, mode != :single_pdf && options[:order_given], "--order", mode)
      warn_if(reporter, mode != :single_pdf && options[:single_pdf_name], "--name", mode)
      warn_if(reporter, mode != :single_pdf && options[:single_pdf_path], "--path", mode)
      warn_if(reporter, !%i[list check_new].include?(mode) && options[:json], "--json", mode)
      warn_if(reporter, %i[list check_new].include?(mode) && options[:dry_run], "--dry-run", mode)
      warn_if(reporter, mode == :check_new && options[:allow_empty], "--allow-empty", mode)
      warn_if(reporter, %i[list check_new].include?(mode) && options[:force], "--force", mode)
    end

    def warn_if(reporter, condition, flag, mode)
      return unless condition

      target = MODES[mode] || "the default export"
      reporter.warn "Warning: #{flag} is ignored with #{target}."
    end

    def build_settings(options)
      Settings.new(
        output_dir: options[:root_dir],
        base_url: options[:publication],
        limit: options[:limit],
        only: options[:posts],
        force: options[:force],
        pdf: !options[:html_only],
        first: options[:first],
        order: options[:order]
      )
    rescue ArgumentError => error
      raise UsageError, error.message
    end

    def dispatch(mode, options, settings, reporter)
      library = Infrastructure::PostLibrary.new(
        output_dir: settings.output_dir,
        author_slug: settings.author_slug,
        create_dirs: !options[:dry_run]
      )
      archive = build_archive(settings)
      selector = Domain::PostSelector.new(only: settings.only)
      error_log = Infrastructure::ErrorLog.new(library.error_log_path)

      case mode
      when :list
        list_selector = Domain::PostSelector.new(only: settings.only, limit: settings.limit)
        UseCases::ListPosts.new(archive: archive, selector: list_selector, reporter: reporter).call
      when :check_new
        UseCases::CheckNewPosts.new(
          archive: archive,
          library: library,
          selector: selector,
          limit: settings.limit,
          reporter: reporter
        ).call
        :ok
      when :single_pdf
        combine_posts(options, settings, library, error_log, reporter)
      when :pdf_only
        convert_posts(options, settings, library, error_log, reporter)
      else
        export_posts(options, settings, library, archive, selector, error_log, reporter)
      end
    end

    def build_archive(settings)
      Infrastructure::ArchiveClient.new(
        base_url: settings.base_url,
        user_agent: Infrastructure::StealthBrowser::REAL_USER_AGENT
      )
    end

    def export_posts(options, settings, library, archive, selector, error_log, reporter)
      scraper = nil
      builder_factory = nil

      unless options[:dry_run]
        media_cache = Infrastructure::MediaCache.new(
          library.asset_dir,
          base_url: settings.base_url,
          user_agent: Infrastructure::StealthBrowser::REAL_USER_AGENT
        )
        builder_factory = lambda do |post|
          Infrastructure::ArticleBuilder.new(media_cache, base_url: post.canonical_url)
        end
        scraper = Infrastructure::ArticleScraper.new
      end

      UseCases::ExportPosts.new(
        archive: archive,
        library: library,
        scraper: scraper,
        builder_factory: builder_factory,
        renderer: Infrastructure::PdfRenderer.new,
        selector: selector,
        error_log: error_log,
        force: settings.force?,
        pdf: settings.pdf?,
        limit: settings.limit,
        dry_run: options[:dry_run],
        reporter: reporter
      ).call
    end

    def convert_posts(options, settings, library, error_log, reporter)
      UseCases::ConvertHtmlToPdf.new(
        library: library,
        renderer: Infrastructure::PdfRenderer.new,
        error_log: error_log,
        only: settings.only,
        limit: settings.limit,
        force: settings.force?,
        dry_run: options[:dry_run],
        reporter: reporter
      ).call
    end

    def combine_posts(options, settings, library, error_log, reporter)
      UseCases::CombinePostsIntoPdf.new(
        library: library,
        renderer: Infrastructure::PdfRenderer.new,
        error_log: error_log,
        only: settings.only,
        first: settings.first,
        order: settings.order,
        limit: settings.limit,
        force: settings.force?,
        output_name: options[:single_pdf_name],
        output_path: options[:single_pdf_path],
        dry_run: options[:dry_run],
        reporter: reporter
      ).call
    end

    def exit_code_for(result, options)
      return 0 if result == :ok
      return 2 if result == :exists

      empty = result.nil? || (result.respond_to?(:empty?) && result.empty?)
      return 0 unless empty
      return 0 if options[:allow_empty]

      2
    end
  end
end
