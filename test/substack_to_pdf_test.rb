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
  def test_filenames_use_date_and_slug
    Dir.mktmpdir do |dir|
      library = SubstackPdf::Infrastructure::PostLibrary.new(output_dir: dir)
      post = SubstackPdf::Domain::Post.new(
        id: 7,
        title: "Title",
        subtitle: "",
        slug: "My Post!",
        canonical_url: "https://example.substack.com/p/my-post",
        published_at: Time.utc(2026, 5, 6)
      )

      assert_equal "2026-05-06-My-Post", library.filename_for(post)
      assert library.html_path(post).end_with?("2026-05-06-My-Post.html")
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
end
