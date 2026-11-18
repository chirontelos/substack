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
    assert post.matches?("https://substack.com/@example/p/my-post")
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

class FileSizeTest < Minitest::Test
  def test_formats_bytes_as_megabytes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "file.pdf")
      File.binwrite(path, "x" * (1_048_576 + 524_288))

      assert_equal "1.50 MB", SubstackPdf::Infrastructure::FileSize.format(path)
    end
  end

  def test_formats_small_files_with_two_decimals
    Dir.mktmpdir do |dir|
      path = File.join(dir, "file.html")
      File.binwrite(path, "x" * 10_240)

      assert_equal "0.01 MB", SubstackPdf::Infrastructure::FileSize.format(path)
    end
  end
end

class FeedEntryBuilderTest < Minitest::Test
  FakeMediaCache = Struct.new(:data) do
    def data_uri(_source, quiet: false)
      data
    end
  end

  def builder
    SubstackPdf::Infrastructure::FeedEntryBuilder.new(
      FakeMediaCache.new("data:image/png;base64,AAA"),
      base_url: "https://substack.com/@kaisoku"
    )
  end

  def note
    SubstackPdf::Domain::Post.new(
      id: 10,
      title: "A note title",
      subtitle: "",
      slug: "c-10",
      canonical_url: "https://substack.com/@kaisoku/note/c-10",
      published_at: Time.utc(2026, 1, 1),
      kind: :note,
      payload: {
        "comment" => {
          "name" => "Kaisoku",
          "body" => "A note title\n\nBody text",
          "body_json" => {
            "type" => "doc",
            "content" => [
              {
                "type" => "paragraph",
                "content" => [
                  { "type" => "text", "text" => "Body ", "marks" => [] },
                  { "type" => "text", "text" => "bold", "marks" => [{ "type" => "bold" }] }
                ]
              }
            ]
          },
          "attachments" => [
            {
              "type" => "post",
              "post" => {
                "title" => "Referenced post",
                "subtitle" => "Referenced subtitle",
                "canonical_url" => "https://example.substack.com/p/referenced",
                "cover_image" => "https://example.substack.com/cover.jpg"
              },
              "publication" => { "name" => "Example" }
            }
          ]
        }
      }
    )
  end

  def restack
    SubstackPdf::Domain::Post.new(
      id: 20,
      title: "Original post",
      subtitle: "Original subtitle",
      slug: "original-post",
      canonical_url: "https://example.substack.com/p/original-post",
      published_at: Time.utc(2026, 1, 2),
      kind: :restack,
      payload: {
        "post" => {
          "title" => "Original post",
          "subtitle" => "Original subtitle",
          "canonical_url" => "https://example.substack.com/p/original-post",
          "cover_image" => "https://example.substack.com/cover.jpg"
        },
        "publication" => { "name" => "Example" }
      }
    )
  end

  def test_renders_note_body_and_referenced_post_card
    output = builder.build(note)

    assert_includes output, "<p>Body <strong>bold</strong></p>"
    assert_includes output, "https://example.substack.com/p/referenced"
    assert_includes output, "Referenced post"
    assert_includes output, "Referenced subtitle"
  end

  def test_restack_links_the_original_post_without_its_body
    output = builder.build(restack)

    assert_includes output, "https://example.substack.com/p/original-post"
    assert_includes output, "Open original post"
    refute_includes output, "Body text"
  end
end

class ArticleBuilderTest < Minitest::Test
  FakeMediaCache = Struct.new(:data) do
    def data_uri(_source, quiet: false)
      data
    end
  end

  def build_html(body)
    <<~HTML
      <html>
        <body>
          <article>
            <h1 class="post-title">Post title</h1>
            <div class="body markup">#{body}</div>
          </article>
        </body>
      </html>
    HTML
  end

  def post
    SubstackPdf::Domain::Post.new(
      id: 1,
      title: "Post title",
      subtitle: "",
      slug: "post-1",
      canonical_url: "https://example.substack.com/p/post-1",
      published_at: Time.utc(2026, 1, 1)
    )
  end

  def test_removes_install_app_embed
    html = build_html(<<~HTML)
      <p>Before</p>
      <div class="install-substack-app-embed install-substack-app-embed-web">
        <img class="install-substack-app-embed-img" src="https://substackcdn.com/app.png">
        <div class="install-substack-app-embed-text">
          <div class="install-substack-app-header">Get more from the author in the Substack app</div>
          <div class="install-substack-app-text">Available for iOS and Android</div>
        </div>
        <a class="install-substack-app-embed-link" href="https://substack.com/app">Get the app</a>
      </div>
      <p>After</p>
    HTML

    builder = SubstackPdf::Infrastructure::ArticleBuilder.new(
      FakeMediaCache.new(nil),
      base_url: "https://example.substack.com"
    )

    output = builder.build(post, html)

    assert_includes output, "<p>Before</p>"
    assert_includes output, "<p>After</p>"
    refute_includes output, "install-substack-app"
    refute_includes output, "Get more from the author"
    refute_includes output, "Available for iOS and Android"
    refute_includes output, "Get the app"
  end
end

class ArchiveClientTest < Minitest::Test
  class StubArchiveClient < SubstackPdf::Infrastructure::ArchiveClient
    attr_reader :pages_fetched

    def initialize(pages)
      super(base_url: "https://example.substack.com", user_agent: "test")
      @pages = pages
      @pages_fetched = 0
    end

    private

    def fetch_page(cursor:, offset:, legacy:)
      @pages_fetched += 1
      @pages.shift || { "posts" => [], "nextCursor" => nil }
    end
  end

  def page(ids, next_cursor)
    {
      "posts" => ids.map do |id|
        {
          "id" => id,
          "title" => "Post #{id}",
          "slug" => "post-#{id}",
          "canonical_url" => "https://example.substack.com/p/post-#{id}",
          "post_date" => "2026-01-0#{id}T00:00:00.000Z"
        }
      end,
      "nextCursor" => next_cursor
    }
  end

  def test_all_posts_still_reads_every_page
    client = StubArchiveClient.new([page([1], "next"), page([2], nil)])

    assert_equal [1, 2], client.all_posts.map(&:id)
    assert_equal 2, client.pages_fetched
  end

  def test_each_post_stops_fetching_when_the_caller_breaks
    client = StubArchiveClient.new([page([1], "next"), page([2], nil)])
    seen = []

    client.each_post do |post|
      seen << post.id
      break if seen.size == 1
    end

    assert_equal [1], seen
    assert_equal 1, client.pages_fetched
  end
end

class ProfileClientTest < Minitest::Test
  class StubProfileClient < SubstackPdf::Infrastructure::ProfileClient
    attr_reader :pages_fetched

    def initialize(pages)
      super(handle: "kaisoku", user_agent: "test")
      @pages = pages
      @pages_fetched = 0
    end

    private

    def profile_id
      123
    end

    def fetch_page(_cursor)
      @pages_fetched += 1
      @pages.shift || {}
    end
  end

  def post_data(id)
    {
      "id" => id,
      "title" => "Post #{id}",
      "subtitle" => "Subtitle #{id}",
      "slug" => "post-#{id}",
      "canonical_url" => "https://example.substack.com/p/post-#{id}",
      "post_date" => "2026-01-0#{id}T00:00:00.000Z"
    }
  end

  def note_item(id, date: "2026-01-01T00:00:00.000Z", context: "note", handle: "kaisoku")
    {
      "entity_key" => "c-#{id}",
      "type" => "comment",
      "context" => { "type" => context, "timestamp" => date },
      "comment" => {
        "id" => id,
        "name" => "Kaisoku",
        "handle" => handle,
        "body" => "First line\n\nSecond paragraph",
        "date" => date,
        "attachments" => []
      }
    }
  end

  def test_maps_notes_and_restacks_to_posts
    page = {
      "items" => [
        note_item(10, context: "note"),
        note_item(11, context: "comment_restack", handle: "other"),
        {
          "entity_key" => "p-12",
          "type" => "post",
          "context" => { "type" => "post_restack", "timestamp" => "2026-01-02T00:00:00.000Z" },
          "post" => post_data(2),
          "publication" => { "name" => "Example" }
        }
      ],
      "nextCursor" => nil
    }

    posts = StubProfileClient.new([page]).all_posts

    assert_equal %i[note restack restack], posts.map(&:kind)
    assert_equal ["First line", "Restacked note by Kaisoku", "Post 2"], posts.map(&:title)
    assert_equal "https://substack.com/@kaisoku/note/c-10", posts[0].canonical_url
    assert_equal "https://substack.com/@other/note/c-11", posts[1].canonical_url
    assert_equal "https://example.substack.com/p/post-2", posts[2].canonical_url
  end

  def test_follows_feed_cursor_until_exhausted
    first = { "items" => [note_item(1)], "nextCursor" => "next" }
    second = { "items" => [note_item(2)], "nextCursor" => nil }
    client = StubProfileClient.new([first, second])

    assert_equal [1, 2], client.all_posts.map(&:id)
    assert_equal 2, client.pages_fetched
  end
end

class CombinedArchiveTest < Minitest::Test
  FakeStreamArchive = Struct.new(:posts) do
    def each_post(&block)
      return enum_for(:each_post) unless block

      posts.each(&block)
    end
  end

  def post(id, date)
    SubstackPdf::Domain::Post.new(
      id: id,
      title: "Post #{id}",
      subtitle: "",
      slug: "post-#{id}",
      canonical_url: "https://example.substack.com/p/post-#{id}",
      published_at: Time.utc(2026, 1, date)
    )
  end

  def test_merges_archives_by_date_and_removes_duplicates
    archive = FakeStreamArchive.new([post(1, 3), post(2, 1)])
    profile = FakeStreamArchive.new([post(3, 4), post(2, 1)])
    combined = SubstackPdf::Infrastructure::CombinedArchive.new([archive, profile])

    assert_equal [3, 1, 2], combined.each_post.map(&:id)
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

  def test_stops_consuming_posts_once_the_limit_is_reached
    posts = [post(1), post(2), post(3)]
    consumed = []
    source = Enumerator.new do |yielder|
      posts.each do |item|
        consumed << item.id
        yielder << item
      end
    end

    selection = SubstackPdf::Domain::PostSelector.new(limit: 2).call(source)

    assert_equal [1, 2], selection.posts.map(&:id)
    assert_equal [1, 2], consumed
  end

  def test_limit_applies_after_the_filter
    posts = [post(1), post(2), post(3)]
    consumed = []
    source = Enumerator.new do |yielder|
      posts.each do |item|
        consumed << item.id
        yielder << item
      end
    end

    selection = SubstackPdf::Domain::PostSelector.new(limit: 1).call(
      source,
      filter: ->(item) { item.id.even? }
    )

    assert_equal [2], selection.posts.map(&:id)
    assert_equal [1, 2], consumed
  end

  def test_zero_limit_does_not_consume_posts
    consumed = []
    source = Enumerator.new do |yielder|
      [post(1)].each do |item|
        consumed << item.id
        yielder << item
      end
    end

    selection = SubstackPdf::Domain::PostSelector.new(limit: 0).call(source)

    assert_empty selection.posts
    assert_empty consumed
  end
end

class ListPostsTest < Minitest::Test
  FakeListArchive = Struct.new(:posts) do
    def all_posts
      posts
    end

    def each_post(&block)
      return enum_for(:each_post) unless block

      posts.each(&block)
    end
  end

  def test_prints_only_the_date_and_slug
    post = SubstackPdf::Domain::Post.new(
      id: 1,
      title: "A readable title",
      subtitle: "",
      slug: "my-post",
      canonical_url: "https://example.substack.com/p/my-post",
      published_at: Time.utc(2026, 1, 2)
    )
    use_case = SubstackPdf::UseCases::ListPosts.new(
      archive: FakeListArchive.new([post]),
      selector: SubstackPdf::Domain::PostSelector.new
    )

    output, = capture_io { use_case.call }

    assert_equal "2026-01-02  my-post\n", output
  end

  def test_limit_stops_reading_the_archive_early
    posts = (1..2).map do |id|
      SubstackPdf::Domain::Post.new(
        id: id,
        title: "Post #{id}",
        subtitle: "",
        slug: "post-#{id}",
        canonical_url: "https://example.substack.com/p/post-#{id}",
        published_at: Time.utc(2026, 1, id)
      )
    end
    consumed = []
    archive = Object.new
    archive.define_singleton_method(:each_post) do |&block|
      return enum_for(:each_post) unless block

      posts.each do |item|
        consumed << item.id
        block.call(item)
      end
    end

    use_case = SubstackPdf::UseCases::ListPosts.new(
      archive: archive,
      selector: SubstackPdf::Domain::PostSelector.new(limit: 1)
    )

    output, = capture_io { use_case.call }

    assert_equal [1], consumed
    assert_equal "2026-01-01  post-1\n", output
  end
end

class CheckNewPostsTest < Minitest::Test
  FakeArchive = Struct.new(:posts) do
    def all_posts
      posts
    end

    def each_post(&block)
      return enum_for(:each_post) unless block

      posts.each(&block)
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
    assert_includes output, "2026-01-02  post-2"
    refute_includes output, "Post 2"
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

  def test_limit_stops_reading_the_archive_after_enough_unsaved_posts
    posts = [post(1), post(2), post(3)]
    consumed = []
    archive = Object.new
    archive.define_singleton_method(:each_post) do |&block|
      return enum_for(:each_post) unless block

      posts.each do |item|
        consumed << item.id
        block.call(item)
      end
    end

    use_case = SubstackPdf::UseCases::CheckNewPosts.new(
      archive: archive,
      library: FakeLibrary.new([1]),
      selector: SubstackPdf::Domain::PostSelector.new,
      limit: 1
    )

    capture_io { @new_posts = use_case.call }

    assert_equal [2], @new_posts.map(&:id)
    assert_equal [1, 2], consumed
  end
end

class ExportPostsTest < Minitest::Test
  FakeExportArchive = Struct.new(:posts) do
    def all_posts
      posts
    end

    def each_post(&block)
      return enum_for(:each_post) unless block

      posts.each(&block)
    end
  end

  FakeExportLibrary = Struct.new(:output_dir, :exported) do
    def html_path(post)
      File.join(output_dir, "#{post.slug}.html")
    end

    def pdf_path(post)
      File.join(output_dir, "#{post.slug}.pdf")
    end

    def exported?(_post, require_pdf: true)
      !!exported
    end
  end

  def post(id = 1)
    SubstackPdf::Domain::Post.new(
      id: id,
      title: "Post #{id}",
      subtitle: "",
      slug: "post-#{id}",
      canonical_url: "https://example.substack.com/p/post-#{id}",
      published_at: Time.utc(2026, 1, id)
    )
  end

  def test_says_when_selected_posts_are_already_saved
    use_case = SubstackPdf::UseCases::ExportPosts.new(
      archive: FakeExportArchive.new([post]),
      library: FakeExportLibrary.new(Dir.tmpdir, true),
      scraper: nil,
      builder_factory: nil,
      renderer: nil,
      selector: SubstackPdf::Domain::PostSelector.new(only: ["post-1"]),
      error_log: nil,
      pdf: false
    )

    _output, error = capture_io { assert_empty use_case.call }

    assert_includes error, "already saved"
    assert_includes error, "--force"
  end

  def test_limit_stops_reading_the_archive_early
    posts = [post(1), post(2)]
    consumed = []
    archive = Object.new
    archive.define_singleton_method(:each_post) do |&block|
      return enum_for(:each_post) unless block

      posts.each do |item|
        consumed << item.id
        block.call(item)
      end
    end

    use_case = SubstackPdf::UseCases::ExportPosts.new(
      archive: archive,
      library: FakeExportLibrary.new(Dir.tmpdir, false),
      scraper: nil,
      builder_factory: nil,
      renderer: nil,
      selector: SubstackPdf::Domain::PostSelector.new,
      error_log: nil,
      pdf: false,
      limit: 1,
      dry_run: true
    )

    output, error = capture_io { use_case.call }

    assert_equal [1], consumed
    assert_includes output, "[1/1] Would export Post 1"
    assert_includes error, "--limit 1 counts only posts that are not saved yet"
  end
end

class CheckNewPostsForAllAuthorsTest < Minitest::Test
  FakeAllArchive = Struct.new(:posts) do
    def all_posts
      posts
    end

    def each_post(&block)
      return enum_for(:each_post) unless block

      posts.each(&block)
    end
  end

  FakeAllLibrary = Struct.new(:saved_ids) do
    def saved?(post)
      saved_ids.include?(post.id)
    end
  end

  def post(id, slug)
    SubstackPdf::Domain::Post.new(
      id: id,
      title: "Post #{id}",
      subtitle: "",
      slug: slug,
      canonical_url: "https://example.substack.com/p/#{slug}",
      published_at: Time.utc(2026, 1, id)
    )
  end

  def with_output
    Dir.mktmpdir do |dir|
      %w[kauanacoimbra kaisoku].each do |author|
        FileUtils.mkdir_p(File.join(dir, author, "html"))
      end
      FileUtils.mkdir_p(File.join(dir, "single-pdfs"))
      yield dir
    end
  end

  def build_use_case(root_dir, archives:, libraries:, reporter: SubstackPdf::Infrastructure::Reporter.new, limit: nil)
    SubstackPdf::UseCases::CheckNewPostsForAllAuthors.new(
      root_dir: root_dir,
      selector: SubstackPdf::Domain::PostSelector.new,
      limit: limit,
      reporter: reporter,
      archive_factory: ->(url) { FakeAllArchive.new(archives.fetch(url)) },
      library_factory: ->(author) { FakeAllLibrary.new(libraries.fetch(author)) }
    )
  end

  def test_checks_every_author_folder_under_the_root
    with_output do |dir|
      archives = {
        "https://kauanacoimbra.substack.com" => [post(1, "saved"), post(2, "new")],
        "https://kaisoku.substack.com" => [post(3, "also-new")]
      }
      libraries = { "kauanacoimbra" => [1], "kaisoku" => [] }
      use_case = build_use_case(dir, archives: archives, libraries: libraries)

      output, = capture_io { @new_posts = use_case.call }

      assert_equal [3, 2], @new_posts.map(&:id)
      assert_includes output, "kauanacoimbra: 1 new post(s):"
      assert_includes output, "kaisoku: 1 new post(s):"
    end
  end

  def test_json_output_includes_the_author
    with_output do |dir|
      archives = {
        "https://kauanacoimbra.substack.com" => [post(1, "new")],
        "https://kaisoku.substack.com" => []
      }
      libraries = { "kauanacoimbra" => [], "kaisoku" => [] }
      reporter = SubstackPdf::Infrastructure::Reporter.new(json: true)
      use_case = build_use_case(dir, archives: archives, libraries: libraries, reporter: reporter)

      output, = capture_io { use_case.call }
      payload = JSON.parse(output)

      assert_equal ["kauanacoimbra"], payload.map { |entry| entry["author"] }
      assert_equal ["new"], payload.map { |entry| entry["slug"] }
    end
  end

  def test_limit_applies_to_each_author
    with_output do |dir|
      archives = {
        "https://kauanacoimbra.substack.com" => [post(1, "one"), post(2, "two")],
        "https://kaisoku.substack.com" => [post(3, "three")]
      }
      libraries = { "kauanacoimbra" => [], "kaisoku" => [] }
      use_case = build_use_case(dir, archives: archives, libraries: libraries, limit: 1)

      output, error = capture_io { @new_posts = use_case.call }

      assert_equal [3, 1], @new_posts.map(&:id)
      assert_includes output, "kauanacoimbra: 1 new post(s):"
      assert_includes output, "kaisoku: 1 new post(s):"
      assert_includes error, "--limit 1 counts only posts that are not saved yet"
    end
  end

  def test_warns_when_no_author_folders_exist
    Dir.mktmpdir do |dir|
      use_case = build_use_case(dir, archives: {}, libraries: {})

      _output, error = capture_io { assert_empty use_case.call }

      assert_includes error, "No downloaded authors found"
    end
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

  def test_converts_substack_profile_url_to_publication_subdomain
    assert_equal(
      "https://kaisoku.substack.com",
      settings("https://substack.com/@kaisoku").base_url
    )
    assert_equal "kaisoku", settings("https://substack.com/@kaisoku").author_slug
  end

  def test_converts_substack_profile_posts_url_to_publication_subdomain
    assert_equal(
      "https://fefeobufao.substack.com",
      settings("https://substack.com/@fefeobufao/posts").base_url
    )
  end

  def test_converts_scheme_less_substack_profile_url
    assert_equal(
      "https://kaisoku.substack.com",
      settings("substack.com/@kaisoku").base_url
    )
  end

  def test_strips_query_strings_from_custom_domains
    assert_equal(
      "https://subscribe.martyrmade.com",
      settings("https://subscribe.martyrmade.com/?utm_source=homepage_recommendations&utm_campaign=2290196").base_url
    )
  end

  def test_accepts_host_without_scheme
    assert_equal(
      "https://kauanacoimbra.substack.com",
      settings("kauanacoimbra.substack.com/archive").base_url
    )
  end

  def test_accepts_bare_handle
    assert_equal "https://kaisoku.substack.com", settings("kaisoku").base_url
    assert_equal "kaisoku", settings("kaisoku").author_slug
  end

  def test_accepts_at_handle
    assert_equal "https://kaisoku.substack.com", settings("@kaisoku").base_url
  end

  def test_accepts_handle_with_archive_path
    assert_equal "https://kaisoku.substack.com", settings("kaisoku/archive").base_url
  end

  def test_rejects_post_url_as_publication
    error = assert_raises(ArgumentError) do
      settings("https://kauanacoimbra.substack.com/p/a-redencao-androgina")
    end

    assert_match(/--post/, error.message)
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

  def test_infers_publication_from_substack_profile_post_url
    settings = SubstackPdf::Settings.new(
      output_dir: Dir.tmpdir,
      only: ["https://substack.com/@kaisoku/p/some-post"]
    )

    assert_equal "https://kaisoku.substack.com", settings.base_url
    assert_equal "kaisoku", settings.author_slug
  end

  def test_explicit_base_url_wins_over_only_url
    settings = SubstackPdf::Settings.new(
      output_dir: Dir.tmpdir,
      base_url: "https://onlylsc.substack.com",
      only: ["https://kauanacoimbra.substack.com/p/a-redencao-androgina"]
    )

    assert_equal "https://onlylsc.substack.com", settings.base_url
  end

  def test_derives_profile_handle_for_substack_publications
    settings = SubstackPdf::Settings.new(
      output_dir: Dir.tmpdir,
      base_url: "https://substack.com/@kaisoku"
    )

    assert_equal "kaisoku", settings.profile_handle
  end

  def test_custom_domains_have_no_profile_handle
    settings = SubstackPdf::Settings.new(
      output_dir: Dir.tmpdir,
      base_url: "https://subscribe.martyrmade.com"
    )

    assert_nil settings.profile_handle
  end

  def test_infers_publication_from_note_url_in_only
    settings = SubstackPdf::Settings.new(
      output_dir: Dir.tmpdir,
      only: ["https://substack.com/@kaisoku/note/c-367417090"]
    )

    assert_equal "https://kaisoku.substack.com", settings.base_url
    assert_equal "kaisoku", settings.author_slug
    assert_equal "kaisoku", settings.profile_handle
  end

  def test_rejects_note_url_as_publication
    error = assert_raises(ArgumentError) do
      settings("https://substack.com/@kaisoku/note/c-367417090")
    end

    assert_match(/--post/, error.message)
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

  def test_check_new_without_publication_scans_author_folders
    Dir.mktmpdir do |dir|
      _output, error = capture_io do
        assert_equal 0, cli("--check-new", "--root", dir).run
      end

      assert_includes error, "No downloaded authors found"
    end
  end

  def test_check_new_all_authors_aliases_scan_author_folders
    %w[--all-authors --all-publications].each do |flag|
      Dir.mktmpdir do |dir|
        _output, error = capture_io do
          assert_equal 0, cli("--check-new", flag, "--root", dir).run
        end

        assert_includes error, "No downloaded authors found"
      end
    end
  end

  def test_all_authors_cannot_be_combined_with_publication
    _output, error = capture_io do
      assert_equal 1, cli(
        "--check-new", "--all-authors",
        "--publication", "https://onlylsc.substack.com"
      ).run
    end

    assert_includes error, "cannot be used with --publication"
  end

  def test_all_authors_cannot_be_combined_with_post_url
    _output, error = capture_io do
      assert_equal 1, cli(
        "--check-new", "--all-authors",
        "--post", "https://onlylsc.substack.com/p/my-post"
      ).run
    end

    assert_includes error, "cannot be used with a --post URL"
  end

  def test_all_authors_overrides_publication_from_config
    Dir.mktmpdir do |dir|
      config = File.join(dir, "config.yml")
      File.write(config, "publication: https://onlylsc.substack.com\nroot: #{dir}\n")

      _output, error = capture_io do
        assert_equal 0, cli("--check-new", "--all-authors", "--config", config).run
      end

      assert_includes error, "No downloaded authors found"
    end
  end

  def test_all_authors_warns_when_used_without_check_new
    Dir.mktmpdir do |dir|
      _output, error = capture_io do
        assert_equal 0, cli(
          "--pdf-only", "--allow-empty", "--root", dir,
          "--publication", "https://onlylsc.substack.com",
          "--all-authors"
        ).run
      end

      assert_includes error, "--all-authors/--all-publications is ignored"
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

  def test_cli_converts_substack_profile_url_to_author_folder
    Dir.mktmpdir do |dir|
      capture_io do
        assert_equal 0, cli(
          "--pdf-only", "--allow-empty", "--root", dir,
          "--publication", "https://substack.com/@kaisoku/posts"
        ).run
      end

      assert Dir.exist?(File.join(dir, "kaisoku"))
    end
  end

  def test_author_alias_accepts_bare_handle
    Dir.mktmpdir do |dir|
      capture_io do
        assert_equal 0, cli(
          "--pdf-only", "--allow-empty", "--root", dir,
          "--author", "kaisoku"
        ).run
      end

      assert Dir.exist?(File.join(dir, "kaisoku"))
    end
  end

  def test_post_url_is_rejected_as_publication
    _output, error = capture_io do
      assert_equal 1, cli(
        "--list",
        "--publication", "https://onlylsc.substack.com/p/my-post"
      ).run
    end

    assert_includes error, "--post"
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
