# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/substack_to_pdf"

class PostTest < Minitest::Test
  def build_post(attributes = {})
    SubstackPdf::Domain::Post.new(
      id: attributes.fetch(:id, 1),
      title: attributes.fetch(:title, "Title"),
      subtitle: attributes.fetch(:subtitle, ""),
      slug: attributes.fetch(:slug, "my-post"),
      canonical_url: attributes.fetch(:canonical_url, "https://example.substack.com/p/my-post"),
      published_at: attributes.fetch(:published_at, Time.utc(2026, 1, 2))
    )
  end

  def test_matches_slug_url_and_url_path
    post = build_post

    assert post.matches?("my-post")
    assert post.matches?("https://example.substack.com/p/my-post")
    assert post.matches?("https://example.substack.com/p/my-post?utm_source=test")
    assert post.matches?("https://example.substack.com/p/my-post/")
    assert post.matches?("example.substack.com/p/my-post")
    refute post.matches?("another-post")
  end

  def test_display_title_falls_back_to_slug
    post = build_post(title: "")

    assert_equal "my-post", post.display_title
  end

  def test_from_archive_parses_date
    post = SubstackPdf::Domain::Post.from_archive(
      "id" => 10,
      "title" => " Post ",
      "slug" => "post",
      "canonical_url" => "https://example.substack.com/p/post",
      "post_date" => "2026-03-04T10:20:30.000Z"
    )

    assert_equal 10, post.id
    assert_equal "Post", post.title
    assert_equal "2026-03-04", post.date_string
  end
end

class PostSelectorTest < Minitest::Test
  def post(id)
    SubstackPdf::Domain::Post.new(
      id: id,
      title: "Post #{id}",
      subtitle: "",
      slug: "post-#{id}",
      canonical_url: "https://example.substack.com/p/post-#{id}",
      published_at: Time.utc(2026, 1, id)
    )
  end

  def test_filters_and_limits_posts
    selector = SubstackPdf::Domain::PostSelector.new(only: ["post-2"], limit: 5)
    selection = selector.call([post(1), post(2), post(3)])

    assert_equal [2], selection.posts.map(&:id)
    assert_empty selection.unmatched
  end

  def test_reports_unmatched_references
    selector = SubstackPdf::Domain::PostSelector.new(only: %w[post-1 missing])
    selection = selector.call([post(1)])

    assert_equal [1], selection.posts.map(&:id)
    assert_equal ["missing"], selection.unmatched
  end
end

class CheckNewPostsTest < Minitest::Test
  FakeArchive = Struct.new(:posts) do
    def all_posts
      posts
    end
  end

  FakeLibrary = Struct.new(:saved_ids) do
    def saved?(post)
      saved_ids.include?(post.id)
    end
  end

  def post(id)
    SubstackPdf::Domain::Post.new(
      id: id,
      title: "Post #{id}",
      subtitle: "",
      slug: "post-#{id}",
      canonical_url: "https://example.substack.com/p/post-#{id}",
      published_at: Time.utc(2026, 1, id)
    )
  end

  def test_reports_only_posts_without_saved_html
    archive = FakeArchive.new([post(1), post(2)])
    library = FakeLibrary.new([1])
    selector = SubstackPdf::Domain::PostSelector.new
    use_case = SubstackPdf::UseCases::CheckNewPosts.new(
      archive: archive,
      library: library,
      selector: selector
    )

    output, = capture_io { @new_posts = use_case.call }

    assert_equal [2], @new_posts.map(&:id)
    assert_includes output, "1 new post(s)"
  end

  def test_limit_counts_only_unsaved_posts
    archive = FakeArchive.new([post(1), post(2), post(3)])
    library = FakeLibrary.new([1])
    selector = SubstackPdf::Domain::PostSelector.new(limit: 1)
    use_case = SubstackPdf::UseCases::CheckNewPosts.new(
      archive: archive,
      library: library,
      selector: selector,
      limit: 1
    )

    _output, error = capture_io { @new_posts = use_case.call }

    assert_equal [2], @new_posts.map(&:id)
    assert_includes error, "--limit 1 counts only posts that are not saved yet"
  end
end

class HtmlArchiveTest < Minitest::Test
  def with_archive
    Dir.mktmpdir do |dir|
      %w[
        2026-01-01-first.html
        2026-01-02-second-2.html
        2026-01-03-third-1.html
      ].each { |name| File.write(File.join(dir, name), "<html></html>") }

      yield SubstackPdf::Infrastructure::HtmlArchive.new(dir)
    end
  end

  def test_orders_numbered_files_ascending
    with_archive do |archive|
      names = archive.ordered.map { |path| File.basename(path) }

      assert_equal(
        %w[2026-01-03-third-1.html 2026-01-02-second-2.html 2026-01-01-first.html],
        names
      )
    end
  end

  def test_orders_numbered_files_descending
    with_archive do |archive|
      names = archive.ordered(order: "desc").map { |path| File.basename(path) }

      assert_equal(
        %w[2026-01-02-second-2.html 2026-01-03-third-1.html 2026-01-01-first.html],
        names
      )
    end
  end

  def test_places_first_files_before_the_rest
    with_archive do |archive|
      names = archive.ordered(first: ["first"]).map { |path| File.basename(path) }

      assert_equal "2026-01-01-first.html", names.first
    end
  end
end

class PostLibraryTest < Minitest::Test
  def build_post
    SubstackPdf::Domain::Post.new(
      id: 7,
      title: "Title",
      subtitle: "",
      slug: "My Post!",
      canonical_url: "https://example.substack.com/p/my-post",
      published_at: Time.utc(2026, 5, 6)
    )
  end

  def test_filenames_use_date_and_slug
    Dir.mktmpdir do |dir|
      library = SubstackPdf::Infrastructure::PostLibrary.new(
        output_dir: dir,
        author_slug: "example"
      )
      post = build_post

      assert_equal "2026-05-06-My-Post", library.filename_for(post)
      assert library.html_path(post).end_with?("2026-05-06-My-Post.html")
    end
  end

  def test_uses_author_specific_html_and_pdf_directories
    Dir.mktmpdir do |dir|
      library = SubstackPdf::Infrastructure::PostLibrary.new(
        output_dir: dir,
        author_slug: "kauanacoimbra"
      )

      assert_equal File.join(dir, "kauanacoimbra", "html"), library.html_dir
      assert_equal File.join(dir, "kauanacoimbra", "pdf"), library.pdf_dir
      assert_equal File.join(dir, "kauanacoimbra", "assets"), library.asset_dir
    end
  end

  def test_single_pdfs_share_one_directory_and_default_name_uses_author
    Dir.mktmpdir do |dir|
      library = SubstackPdf::Infrastructure::PostLibrary.new(
        output_dir: dir,
        author_slug: "kauanacoimbra"
      )

      assert_equal File.join(dir, "single-pdfs"), library.single_pdf_dir
      assert_equal(
        File.join(dir, "single-pdfs", "kauanacoimbra-all-posts.pdf"),
        library.default_combined_pdf_path
      )
      assert_equal(
        File.join(dir, "single-pdfs", "custom-name.pdf"),
        library.combined_pdf_path(name: "custom-name")
      )
    end
  end

  def test_single_pdf_accepts_an_explicit_path
    Dir.mktmpdir do |dir|
      library = SubstackPdf::Infrastructure::PostLibrary.new(
        output_dir: dir,
        author_slug: "onlylsc"
      )

      assert_equal(
        File.join(dir, "custom", "combined.pdf"),
        library.combined_pdf_path(path: File.join(dir, "custom", "combined.pdf"))
      )
      assert library.custom_combined_pdf?(path: File.join(dir, "custom", "combined.pdf"))
      refute library.custom_combined_pdf?
    end
  end

  def test_can_skip_directory_creation_for_dry_runs
    Dir.mktmpdir do |dir|
      root = File.join(dir, "root")
      library = SubstackPdf::Infrastructure::PostLibrary.new(
        output_dir: root,
        author_slug: "onlylsc",
        create_dirs: false
      )

      refute File.exist?(root)
      assert_equal File.join(root, "onlylsc", "html"), library.html_dir
    end
  end
end

class SettingsTest < Minitest::Test
  def settings(base_url)
    SubstackPdf::Settings.new(output_dir: Dir.tmpdir, base_url: base_url)
  end

  def test_accepts_publication_homepage
    assert_equal(
      "https://onlylsc.substack.com",
      settings("https://onlylsc.substack.com/").base_url
    )
  end

  def test_accepts_archive_url_and_keeps_only_the_origin
    assert_equal(
      "https://kauanacoimbra.substack.com",
      settings("https://kauanacoimbra.substack.com/archive?sort=new").base_url
    )
  end

  def test_accepts_host_without_scheme
    assert_equal(
      "https://kauanacoimbra.substack.com",
      settings("kauanacoimbra.substack.com/archive").base_url
    )
  end

  def test_preserves_non_default_port
    assert_equal(
      "http://example.test:8080",
      settings("http://example.test:8080/archive").base_url
    )
  end

  def test_rejects_non_http_schemes
    assert_raises(ArgumentError) { settings("ftp://example.test/archive") }
  end

  def test_derives_author_slug_from_substack_subdomain
    assert_equal "kauanacoimbra", settings("https://kauanacoimbra.substack.com/archive").author_slug
  end

  def test_derives_author_slug_from_custom_domain
    assert_equal "example.com", settings("https://www.example.com/archive").author_slug
  end

  def test_infers_publication_from_post_url_in_only
    settings = SubstackPdf::Settings.new(
      output_dir: Dir.tmpdir,
      only: ["https://kauanacoimbra.substack.com/p/a-redencao-androgina"]
    )

    assert_equal "https://kauanacoimbra.substack.com", settings.base_url
    assert_equal "kauanacoimbra", settings.author_slug
  end

  def test_infers_publication_from_scheme_less_post_url_in_only
    settings = SubstackPdf::Settings.new(
      output_dir: Dir.tmpdir,
      only: ["kauanacoimbra.substack.com/p/a-redencao-androgina"]
    )

    assert_equal "https://kauanacoimbra.substack.com", settings.base_url
  end

  def test_explicit_base_url_wins_over_only_url
    settings = SubstackPdf::Settings.new(
      output_dir: Dir.tmpdir,
      base_url: "https://onlylsc.substack.com",
      only: ["https://kauanacoimbra.substack.com/p/a-redencao-androgina"]
    )

    assert_equal "https://onlylsc.substack.com", settings.base_url
  end

  def test_rejects_post_urls_from_multiple_publications
    error = assert_raises(ArgumentError) do
      SubstackPdf::Settings.new(
        output_dir: Dir.tmpdir,
        only: [
          "https://kauanacoimbra.substack.com/p/one",
          "https://onlylsc.substack.com/p/two"
        ]
      )
    end

    assert_match(/more than one publication/, error.message)
  end
end

class CLITest < Minitest::Test
  def cli(*args)
    SubstackPdf::CLI.new(args)
  end

  def test_version
    output, = capture_io { assert_equal 0, cli("--version").run }

    assert_equal "substack_to_pdf #{SubstackPdf::VERSION}\n", output
  end

  def test_rejects_multiple_modes
    _output, error = capture_io do
      assert_equal 1, cli("--list", "--pdf-only").run
    end

    assert_includes error, "cannot be used together"
  end

  def test_rejects_name_and_path_together
    _output, error = capture_io do
      assert_equal 1, cli("--single-pdf", "--name", "one", "--path", "two.pdf").run
    end

    assert_includes error, "--name and --path cannot be used together"
  end

  def test_irrelevant_flag_warns_but_does_not_fail
    Dir.mktmpdir do |dir|
      _output, error = capture_io do
        assert_equal 0, cli(
          "--pdf-only", "--json", "--allow-empty",
          "--root", dir, "--publication", "https://onlylsc.substack.com"
        ).run
      end

      assert_includes error, "Warning: --json is ignored with --pdf-only."
    end
  end

  def test_empty_conversion_exits_with_two_by_default
    Dir.mktmpdir do |dir|
      _output, error = capture_io do
        assert_equal 2, cli(
          "--pdf-only",
          "--root", dir,
          "--publication", "https://onlylsc.substack.com"
        ).run
      end

      assert_includes error, "No HTML files found"
    end
  end

  def test_allow_empty_makes_empty_conversion_successful
    Dir.mktmpdir do |dir|
      capture_io do
        assert_equal 0, cli(
          "--pdf-only", "--allow-empty",
          "--root", dir, "--publication", "https://onlylsc.substack.com"
        ).run
      end
    end
  end

  def test_dry_run_does_not_create_output_directories
    Dir.mktmpdir do |dir|
      root = File.join(dir, "root")
      capture_io do
        assert_equal 0, cli(
          "--pdf-only",
          "--dry-run",
          "--allow-empty",
          "--root", root,
          "--publication", "https://onlylsc.substack.com"
        ).run
      end

      refute File.exist?(root)
    end
  end

  def test_splits_comma_separated_values_once_in_the_cli
    options = { posts: ["one,two", "three"], first: ["welcome, intro"] }

    cli.send(:normalize_lists!, options)

    assert_equal %w[one two three], options[:posts]
    assert_equal %w[welcome intro], options[:first]
  end

  def test_publication_is_required_when_no_config_or_post_url_is_given
    Dir.mktmpdir do |dir|
      _output, error = capture_io do
        assert_equal 1, cli("--pdf-only", "--root", dir, "--allow-empty").run
      end

      assert_includes error, "publication is required"
    end
  end

  def test_config_supplies_publication_and_root
    Dir.mktmpdir do |dir|
      root = File.join(dir, "out")
      config = File.join(dir, "config.yml")
      File.write(config, "publication: https://onlylsc.substack.com\nroot: #{root}\n")

      capture_io do
        assert_equal 0, cli("--pdf-only", "--allow-empty", "--config", config).run
      end

      assert Dir.exist?(File.join(root, "onlylsc"))
    end
  end

  def test_cli_publication_overrides_config
    Dir.mktmpdir do |dir|
      root = File.join(dir, "out")
      config = File.join(dir, "config.yml")
      File.write(config, "publication: https://onlylsc.substack.com\nroot: #{root}\n")

      capture_io do
        assert_equal 0, cli(
          "--pdf-only", "--allow-empty", "--config", config,
          "--publication", "https://kauanacoimbra.substack.com"
        ).run
      end

      assert Dir.exist?(File.join(root, "kauanacoimbra"))
      refute Dir.exist?(File.join(root, "onlylsc"))
    end
  end

  def test_missing_config_file_is_a_usage_error
    _output, error = capture_io do
      assert_equal 1, cli("--config", "/does/not/exist.yml", "--pdf-only").run
    end

    assert_includes error, "config file not found"
  end

  def test_invalid_config_file_is_a_usage_error
    Dir.mktmpdir do |dir|
      config = File.join(dir, "config.yml")
      File.write(config, "[\n")

      _output, error = capture_io do
        assert_equal 1, cli("--config", config, "--pdf-only").run
      end

      assert_includes error, "invalid config file"
    end
  end

  def test_unknown_config_key_warns
    Dir.mktmpdir do |dir|
      config = File.join(dir, "config.yml")
      File.write(config, "publication: https://onlylsc.substack.com\nunknown_key: true\n")

      _output, error = capture_io do
        assert_equal 0, cli(
          "--pdf-only", "--allow-empty", "--config", config, "--root", dir
        ).run
      end

      assert_includes error, "Warning: unknown config key: unknown_key"
    end
  end

  def test_config_lists_and_booleans_are_applied
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "config.yml")
      File.write(config_path, <<~YAML)
        publication: https://onlylsc.substack.com
        post: [one, two]
        first: welcome, intro
        force: true
        html_only: true
        quiet: true
        json: true
      YAML

      options = cli.send(:defaults)
      config = cli.send(:load_config, config_path)
      cli.send(:apply_config!, options, config)
      cli.send(:normalize_lists!, options)

      assert_equal %w[one two], options[:posts]
      assert_equal %w[welcome intro], options[:first]
      assert options[:force]
      assert options[:html_only]
      assert options[:quiet]
      assert options[:json]
    end
  end
end
