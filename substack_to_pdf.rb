#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "cgi"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "nokogiri"
require "optparse"
require "sghtmltopdf"
require "time"
require "uri"
require "ferrum"

class StealthBrowser
  REAL_USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
                    "(KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36"
  ACCEPT_LANGUAGE = "pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7"

  STEALTH_JS = <<~'JS'
    (() => {
      const defineGetter = (target, property, getter) => {
        try {
          Object.defineProperty(target, property, { get: getter, configurable: true });
        } catch (error) {}
      };

      defineGetter(navigator, "webdriver", () => false);
      defineGetter(navigator, "language", () => "pt-BR");
      defineGetter(navigator, "languages", () => ["pt-BR", "pt", "en-US", "en"]);
      defineGetter(navigator, "platform", () => "Linux x86_64");
      defineGetter(navigator, "vendor", () => "Google Inc.");
      defineGetter(navigator, "hardwareConcurrency", () => 8);
      defineGetter(navigator, "deviceMemory", () => 8);
      defineGetter(navigator, "maxTouchPoints", () => 0);
      defineGetter(navigator, "pdfViewerEnabled", () => true);
      defineGetter(navigator, "doNotTrack", () => null);

      const pdfMime = {
        type: "application/pdf",
        suffixes: "pdf",
        description: "Portable Document Format",
        enabledPlugin: null
      };

      const plugins = [
        { name: "PDF Viewer", filename: "internal-pdf-viewer", description: "Portable Document Format", length: 1, 0: pdfMime },
        { name: "Chrome PDF Viewer", filename: "internal-pdf-viewer", description: "Portable Document Format", length: 1, 0: pdfMime },
        { name: "Chromium PDF Viewer", filename: "internal-pdf-viewer", description: "Portable Document Format", length: 1, 0: pdfMime }
      ];
      plugins.item = (index) => plugins[index] || null;
      plugins.namedItem = (name) => plugins.find((plugin) => plugin.name === name) || null;
      plugins.refresh = () => {};

      const mimeTypes = [
        { type: "application/pdf", suffixes: "pdf", description: "Portable Document Format", enabledPlugin: plugins[0] },
        { type: "application/x-google-chrome-pdf", suffixes: "pdf", description: "Portable Document Format", enabledPlugin: plugins[1] }
      ];
      mimeTypes.item = (index) => mimeTypes[index] || null;
      mimeTypes.namedItem = (name) => mimeTypes.find((mime) => mime.type === name) || null;

      defineGetter(navigator, "plugins", () => plugins);
      defineGetter(navigator, "mimeTypes", () => mimeTypes);

      const brands = [
        { brand: "Chromium", version: "155" },
        { brand: "Google Chrome", version: "155" },
        { brand: "Not_A Brand", version: "24" }
      ];
      const highEntropy = {
        brands: brands,
        mobile: false,
        platform: "Linux",
        platformVersion: "6.0.0",
        architecture: "x86",
        bitness: "64",
        model: "",
        uaFullVersion: "155.0.0.0",
        wow64: false
      };
      const userAgentData = {
        brands: brands,
        mobile: false,
        platform: "Linux",
        getHighEntropyValues: async () => highEntropy,
        toJSON: () => ({ brands: brands, mobile: false, platform: "Linux" })
      };
      defineGetter(navigator, "userAgentData", () => userAgentData);

      for (const constructor of [window.WebGLRenderingContext, window.WebGL2RenderingContext]) {
        if (!constructor) continue;

        const originalGetParameter = constructor.prototype.getParameter;
        constructor.prototype.getParameter = function(parameter) {
          if (parameter === 37445) return "Google Inc. (Intel)";
          if (parameter === 37446) {
            return "ANGLE (Intel, Mesa Intel(R) UHD Graphics 620 (KBL GT2), OpenGL 4.6 (Core Profile) Mesa 22.0.5)";
          }
          return originalGetParameter.call(this, parameter);
        };
      }

      if (!window.chrome) window.chrome = {};
      window.chrome.runtime = window.chrome.runtime || {};
      window.chrome.app = window.chrome.app || { isInstalled: false };
      window.chrome.csi = window.chrome.csi || function() { return {}; };
      window.chrome.loadTimes = window.chrome.loadTimes || function() { return {}; };

      if (window.Permissions && Permissions.prototype.query) {
        const originalQuery = Permissions.prototype.query;
        Permissions.prototype.query = function(parameters) {
          if (parameters && parameters.name === "notifications") {
            return Promise.resolve({ state: Notification.permission, onchange: null });
          }
          return originalQuery.apply(this, arguments);
        };
      }

      defineGetter(navigator, "connection", () => ({
        rtt: 50,
        downlink: 10,
        effectiveType: "4g",
        saveData: false,
        onchange: null
      }));
    })();
  JS

  BROWSER_OPTIONS = {
    "headless" => nil,
    "disable-gpu" => nil,
    "disable-blink-features" => "AutomationControlled",
    "disable-dev-shm-usage" => nil,
    "disable-setuid-sandbox" => nil,
    "no-sandbox" => nil,
    "no-first-run" => nil,
    "no-default-browser-check" => nil,
    "disable-background-networking" => nil,
    "disable-background-timer-throttling" => nil,
    "disable-backgrounding-occluded-windows" => nil,
    "disable-renderer-backgrounding" => nil,
    "disable-features" => "site-per-process,IsolateOrigins,Translate,TranslateUI,AcceptCHFrame,MediaRouter,InterestFeedContentSuggestion,OptimizationHints",
    "disable-popup-blocking" => nil,
    "mute-audio" => nil,
    "hide-scrollbars" => nil,
    "force-color-profile" => "srgb",
    "remote-allow-origins" => "*",
    "user-agent" => REAL_USER_AGENT,
    "lang" => "pt-BR"
  }.freeze

  attr_reader :page

  def initialize
    @browser = Ferrum::Browser.new(
      headless: false,
      timeout: 60,
      process_timeout: 30,
      window_size: [1920, 1080],
      ignore_default_browser_options: true,
      browser_options: BROWSER_OPTIONS.dup
    )

    @page = @browser.create_page
    @page.headers.set("Accept-Language" => ACCEPT_LANGUAGE)
    @page.evaluate_on_new_document(STEALTH_JS)

    begin
      @page.command("Emulation.setTimezoneOverride", timezoneId: "America/Sao_Paulo")
      @page.command("Emulation.setLocaleOverride", locale: "pt-BR")
    rescue StandardError
      nil
    end
  end

  def quit
    @browser.quit
  end

  def visit(url)
    page.go_to(url)
    page.network.wait_for_idle(timeout: 30)
  rescue Ferrum::TimeoutError
    nil
  ensure
    human_pause(1.8, 3.2)
    wait_for_article
    human_scroll
    wait_for_images
    human_pause(1.2, 2.4)
  end

  def article_html
    page.evaluate(<<~JS)
      (() => {
        const article = document.querySelector("article");
        return article ? article.outerHTML : null;
      })()
    JS
  end

  private

  def human_pause(minimum, maximum)
    sleep(rand(minimum..maximum))
  end

  def wait_for_article
    deadline = Time.now + 30

    until page.evaluate("!!document.querySelector('article')")
      raise "article did not load" if Time.now > deadline

      sleep(0.5)
    end
  end

  def human_scroll
    height = page.evaluate("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)").to_i
    position = 0

    while position < height
      position += rand(450..900)
      page.mouse.move(x: rand(200..1600), y: rand(150..850))
      page.mouse.scroll_to(position, 0)
      sleep(rand(0.45..0.9))
      height = page.evaluate("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)").to_i
    end

    human_pause(0.8, 1.5)
    page.evaluate("void window.scrollTo(0, 0)")
  end

  def wait_for_images
    page.evaluate(<<~JS, timeout: 20)
      await new Promise((resolve) => {
        const images = Array.from(document.images);
        if (images.length === 0) return resolve(true);

        let pending = images.length;
        let done = false;
        const finish = () => {
          if (done) return;
          done = true;
          resolve(true);
        };

        const complete = () => {
          pending -= 1;
          if (pending <= 0) finish();
        };

        images.forEach((image) => {
          if (image.complete) return complete();
          image.addEventListener("load", complete, { once: true });
          image.addEventListener("error", complete, { once: true });
        });

        setTimeout(finish, 15000);
      })
    JS
  rescue Ferrum::TimeoutError
    nil
  end
end

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

  def initialize(directory)
    @directory = directory
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
    request["User-Agent"] = StealthBrowser::REAL_USER_AGENT
    request["Accept"] = "image/avif,image/webp,image/png,image/jpeg,image/*,*/*;q=0.8"
    request["Referer"] = "https://onlylsc.substack.com/"

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
      raise "image is too large" if body.bytesize > 25 * 1024 * 1024

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

class ArticleBuilder
  CSS = <<~CSS
    @page {
      size: A4;
      margin: 18mm 16mm 20mm 16mm;
    }

    body {
      margin: 0;
      color: #1b1b1b;
      background: #ffffff;
      font-family: "DejaVu Serif", serif;
      font-size: 11.5pt;
      line-height: 1.55;
    }

    article {
      margin: 0;
      padding: 0;
    }

    .post-header {
      margin: 0 0 1.6em 0;
    }

    .post-title {
      margin: 0 0 0.25em 0;
      color: #111111;
      font-family: "DejaVu Sans", sans-serif;
      font-size: 25pt;
      font-weight: bold;
      line-height: 1.15;
    }

    .post-subtitle {
      margin: 0 0 0.7em 0;
      color: #555555;
      font-size: 13pt;
      font-style: italic;
      line-height: 1.3;
    }

    .post-meta {
      margin: 0 0 1.4em 0;
      padding-bottom: 0.8em;
      border-bottom: 1px solid #dddddd;
      color: #666666;
      font-family: "DejaVu Sans", sans-serif;
      font-size: 9pt;
    }

    .post-body {
      margin: 0;
      padding: 0;
    }

    h1, h2, h3, h4, h5, h6 {
      color: #111111;
      font-family: "DejaVu Sans", sans-serif;
      font-weight: bold;
      line-height: 1.25;
      page-break-after: avoid;
    }

    h1 { font-size: 22pt; margin: 1.3em 0 0.6em 0; }
    h2 { font-size: 17pt; margin: 1.3em 0 0.55em 0; }
    h3 { font-size: 14pt; margin: 1.2em 0 0.5em 0; }
    h4 { font-size: 12pt; margin: 1.1em 0 0.45em 0; }
    h5, h6 { font-size: 11pt; margin: 1em 0 0.4em 0; }

    p {
      margin: 0 0 1em 0;
      text-align: justify;
    }

    a {
      color: #0b5cad;
      text-decoration: underline;
    }

    strong, b {
      color: #111111;
    }

    em, i {
      font-style: italic;
    }

    img {
      display: block;
      max-width: 100%;
      height: auto;
      margin: 1.1em auto;
    }

    figure {
      margin: 1.3em 0;
      page-break-inside: avoid;
    }

    figcaption {
      margin-top: 0.45em;
      color: #666666;
      font-family: "DejaVu Sans", sans-serif;
      font-size: 9pt;
      line-height: 1.35;
      text-align: center;
    }

    .captioned-image-container {
      margin: 1.3em 0;
      page-break-inside: avoid;
    }

    .image2-inset {
      margin: 0;
    }

    .pullquote, blockquote {
      margin: 1.3em 0;
      padding: 0.2em 0 0.2em 1em;
      border-left: 3px solid #b8b8b8;
      color: #333333;
      font-style: italic;
      page-break-inside: avoid;
    }

    .pullquote p, blockquote p {
      margin-bottom: 0.5em;
    }

    ul, ol {
      margin: 0 0 1em 1.5em;
      padding: 0;
    }

    li {
      margin: 0 0 0.35em 0;
    }

    hr {
      margin: 1.6em 0;
      border: 0;
      border-top: 1px solid #cccccc;
    }

    table {
      width: 100%;
      margin: 1.2em 0;
      border-collapse: collapse;
    }

    th, td {
      padding: 0.4em 0.6em;
      border: 1px solid #cccccc;
      text-align: left;
      vertical-align: top;
    }

    th {
      background: #f2f2f2;
      font-family: "DejaVu Sans", sans-serif;
      font-weight: bold;
    }

    pre {
      margin: 1em 0;
      padding: 0.8em;
      background: #f4f4f4;
      white-space: pre-wrap;
      word-wrap: break-word;
      font-family: "DejaVu Sans Mono", monospace;
      font-size: 9pt;
    }

    code {
      padding: 0.1em 0.25em;
      background: #f4f4f4;
      font-family: "DejaVu Sans Mono", monospace;
      font-size: 9.5pt;
    }

    .video {
      text-align: center;
    }

    .video img {
      width: 100%;
      max-width: 640px;
      margin-bottom: 0.4em;
    }

    .embed {
      margin: 1em 0;
      padding: 0.7em;
      background: #f7f7f7;
      border: 1px solid #e0e0e0;
      font-size: 9.5pt;
      text-align: left;
    }

    .image-error {
      color: #a00000;
      font-size: 9pt;
    }
  CSS

  REMOVE_SELECTORS = [
    "script",
    "style",
    "noscript",
    "form",
    "input",
    "textarea",
    "select",
    "button",
    "nav",
    ".post-footer",
    ".visibility-check",
    ".subscription-widget-wrap",
    ".subscription-widget",
    ".subscribe-widget",
    ".share-dialog",
    ".paywall",
    ".paywall-cta",
    ".post-ufi",
    "[data-component-name='SubscribeWidgetToDOM']"
  ].join(",")

  def initialize(media_cache, base_url:)
    @media_cache = media_cache
    @base_url = base_url
  end

  def build(post, scraped_html)
    document = Nokogiri::HTML(scraped_html)
    article = document.at_css("article")
    raise "article element not found" unless article

    title = article.at_css("h1.post-title")&.text&.strip
    title = post["title"].to_s.strip if title.nil? || title.empty?

    subtitle = article.at_css("h3.subtitle")&.text&.strip
    subtitle = post["subtitle"].to_s.strip if subtitle.nil? || subtitle.empty?

    body = article.at_css(".dt-post-body") ||
           article.at_css(".body.markup") ||
           article.at_css(".available-content") ||
           article

    from_article = body.equal?(article)
    body = body.dup
    body.css(".post-header, .post-footer, .visibility-check").remove if from_article

    clean(body)
    replace_iframes(body)
    rewrite_images(body)
    rewrite_links(body)
    strip_attributes(body)

    document_html(post, title, subtitle, body)
  end

  private

  def clean(body)
    body.css(REMOVE_SELECTORS).remove
    body.css("svg").remove
    body.css("[aria-hidden='true']").remove
  end

  def replace_iframes(body)
    body.css("iframe").each do |iframe|
      source = iframe["src"].to_s
      video_id = youtube_id(source)

      iframe.replace(video_id ? youtube_fragment(video_id) : embed_fragment(source))
    end
  end

  def youtube_id(source)
    uri = URI.parse(source)
    host = uri.host.to_s
    path = uri.path.to_s
    params = URI.decode_www_form(uri.query.to_s).to_h

    return params["v"] if host.include?("youtube.com") && path == "/watch" && params["v"]

    match = path.match(%r{\A/(?:embed|shorts|live)/([^/?#]+)}) if host.include?("youtube")
    return match[1] if match

    match = path.match(%r{\A/([^/?#]+)}) if host == "youtu.be"
    match && match[1]
  rescue URI::InvalidURIError
    nil
  end

  def youtube_fragment(video_id)
    watch_url = "https://www.youtube.com/watch?v=#{video_id}"
    thumbnail = @media_cache.data_uri("https://i.ytimg.com/vi/#{video_id}/maxresdefault.jpg", quiet: true)
    thumbnail ||= @media_cache.data_uri("https://i.ytimg.com/vi/#{video_id}/hqdefault.jpg", quiet: true)

    image_html = if thumbnail
                   %(<a href="#{CGI.escapeHTML(watch_url)}"><img src="#{thumbnail}" alt="Vídeo do YouTube"></a>)
                 else
                   ""
                 end

    Nokogiri::HTML.fragment(<<~HTML)
      <figure class="video">
        #{image_html}
        <figcaption><a href="#{CGI.escapeHTML(watch_url)}">Assistir no YouTube</a></figcaption>
      </figure>
    HTML
  end

  def embed_fragment(source)
    return Nokogiri::HTML.fragment("") if source.empty? || source.start_with?("about:")

    label = "Conteúdo incorporado: #{source}"
    Nokogiri::HTML.fragment(
      %(<p class="embed"><a href="#{CGI.escapeHTML(source)}">#{CGI.escapeHTML(label)}</a></p>)
    )
  end

  def rewrite_images(body)
    body.css("picture").each do |picture|
      image = picture.at_css("img")
      picture.replace(image ? image.dup : Nokogiri::HTML.fragment(""))
    end

    body.css("img").each do |image|
      source = best_image_source(image)

      if source.nil? || source.empty?
        image.remove
        next
      end

      data = @media_cache.data_uri(source)

      if data
        image["src"] = data
        image.remove_attribute("srcset")
        image.remove_attribute("sizes")
        image.remove_attribute("data-src")
        image.remove_attribute("data-srcset")
        image.remove_attribute("data-attrs")
        image.remove_attribute("loading")
        image.remove_attribute("width")
        image.remove_attribute("height")
        image["alt"] = image["alt"].to_s
        image.remove_attribute("alt") if image["alt"].empty?
      else
        image.replace(
          Nokogiri::HTML.fragment(
            %(<span class="image-error">[Imagem indisponível: #{CGI.escapeHTML(source)}]</span>)
          )
        )
      end
    end
  end

  def best_image_source(image)
    attributes = JSON.parse(image["data-attrs"].to_s)
    candidates = [
      attributes["src"],
      attributes["srcNoWatermark"],
      image["src"],
      image["data-src"]
    ].compact.map(&:to_s).reject(&:empty?)

    candidates << largest_srcset_source(image["srcset"].to_s) if candidates.empty?
    source = candidates.first
    return nil if source.nil?

    absolute_url(source)
  rescue JSON::ParserError
    absolute_url(image["src"].to_s)
  end

  def largest_srcset_source(srcset)
    srcset.split(",").map do |candidate|
      url, width = candidate.strip.split(/\s+/, 2)
      [url, width.to_i]
    end.max_by { |_url, width| width }&.first
  end

  def rewrite_links(body)
    body.css("a").each do |link|
      href = link["href"].to_s
      next if href.empty?

      if href.start_with?("javascript:")
        link.remove_attribute("href")
      elsif href.start_with?("#", "mailto:", "tel:", "data:")
        next
      else
        absolute = absolute_url(href)
        absolute ? link["href"] = absolute : link.remove_attribute("href")
      end
    end
  end

  def absolute_url(value)
    return nil if value.nil? || value.empty?
    return value if value.start_with?("data:", "mailto:", "tel:", "#")
    return "https:#{value}" if value.start_with?("//")

    URI.join(@base_url, value).to_s
  rescue URI::InvalidURIError
    nil
  end

  def strip_attributes(body)
    body.css("*").each do |node|
      node.attribute_nodes.each do |attribute|
        name = attribute.name
        node.remove_attribute(name) if name.start_with?("data-") || name.start_with?("on")
      end
    end
  end

  def document_html(post, title, subtitle, body)
    canonical_url = post["canonical_url"].to_s
    date = format_date(post["post_date"])
    subtitle_html = if subtitle.empty?
                      ""
                    else
                      %(<p class="post-subtitle">#{CGI.escapeHTML(subtitle)}</p>)
                    end

    <<~HTML
      <!DOCTYPE html>
      <html lang="pt-BR">
      <head>
        <meta charset="utf-8">
        <title>#{CGI.escapeHTML(title)}</title>
        <style>
      #{CSS.lines.map { |line| "    #{line}" }.join}
        </style>
      </head>
      <body>
        <article class="post">
          <header class="post-header">
            <h1 class="post-title">#{CGI.escapeHTML(title)}</h1>
            #{subtitle_html}
            <p class="post-meta">Publicado em #{date} &middot; <a href="#{CGI.escapeHTML(canonical_url)}">Post original</a></p>
          </header>
          <div class="post-body">
      #{body.inner_html}
          </div>
        </article>
      </body>
      </html>
    HTML
  end

  def format_date(value)
    Time.iso8601(value.to_s).strftime("%d/%m/%Y")
  rescue ArgumentError
    value.to_s
  end
end

class SubstackPdf
  BASE_URL = "https://onlylsc.substack.com"
  ARCHIVE_URL = "#{BASE_URL}/api/v1/archive"
  ARCHIVE_PAGE_SIZE = 50
  BROWSER_RESTART_EVERY = 20

  def initialize(output_dir:, limit: nil, only: [], force: false, pdf: true, first: [], order: "asc")
    @output_dir = File.expand_path(output_dir)
    @html_dir = File.join(@output_dir, "html")
    @pdf_dir = File.join(@output_dir, "pdf")
    @asset_dir = File.join(@output_dir, "assets")
    @error_log = File.join(@output_dir, "errors.log")
    @limit = limit
    @only = only.map(&:strip).reject(&:empty?)
    @force = force
    @pdf = pdf
    @first = first.map(&:strip).reject(&:empty?)
    @order = order

    FileUtils.mkdir_p(@html_dir)
    FileUtils.mkdir_p(@pdf_dir)
    FileUtils.mkdir_p(@asset_dir)

    @media_cache = MediaCache.new(@asset_dir)
  end

  def run
    posts = selected_posts
    if posts.empty?
      warn "No posts found."
      return
    end

    puts "Processing #{posts.size} post(s) into #{@output_dir}"
    browser = nil

    posts.each_with_index do |post, index|
      if browser.nil? || (index % BROWSER_RESTART_EVERY).zero?
        browser&.quit
        browser = StealthBrowser.new
      end

      title = post["title"].to_s.strip
      title = post["slug"].to_s if title.empty?
      basename = filename_for(post)
      html_path = File.join(@html_dir, "#{basename}.html")
      pdf_path = File.join(@pdf_dir, "#{basename}.pdf")

      target_path = @pdf ? pdf_path : html_path

      if File.exist?(target_path) && !@force
        puts "[#{index + 1}/#{posts.size}] Skipping existing #{File.basename(target_path)}"
        next
      end

      puts "[#{index + 1}/#{posts.size}] #{title}"

      begin
        browser.visit(post["canonical_url"])
        scraped_html = browser.article_html
        raise "article HTML was empty" if scraped_html.nil? || scraped_html.empty?

        builder = ArticleBuilder.new(@media_cache, base_url: post["canonical_url"])
        html = builder.build(post, scraped_html)

        File.write(html_path, html)

        if @pdf
          render_pdf(html, pdf_path, title: title, subject: post["subtitle"].to_s)
          puts "  saved #{File.basename(pdf_path)} (#{File.size(pdf_path)} bytes)"
        else
          puts "  saved #{File.basename(html_path)} (#{File.size(html_path)} bytes)"
        end
      rescue StandardError => error
        log_error(post, error)
        warn "  failed: #{error.class}: #{error.message}"
        browser&.quit
        browser = nil
      ensure
        sleep(rand(2.0..4.5))
      end
    end
  ensure
    browser&.quit
  end

  def list
    posts = selected_posts
    posts.each do |post|
      date = post["post_date"].to_s[0, 10]
      puts "#{date}  #{post["slug"]}  #{post["title"]}"
    end
  end

  def single_pdf(output_path: nil)
    html_files = ordered_html_files

    if html_files.empty?
      warn "No HTML files found in #{@html_dir}."
      return
    end

    output_path = File.join(@pdf_dir, "all-posts.pdf") if output_path.nil?
    output_path = File.expand_path(output_path)
    FileUtils.mkdir_p(File.dirname(output_path))

    puts "Combining #{html_files.size} HTML file(s) into #{output_path}"

    sections = html_files.each_with_index.map do |html_path, index|
      html = File.binread(html_path).force_encoding("UTF-8")
      document = Nokogiri::HTML(html)
      article = document.at_css("article")
      raise "article element not found in #{File.basename(html_path)}" unless article

      section_class = index.zero? ? "post-section first" : "post-section"
      %(<section class="#{section_class}">#{article.to_html}</section>)
    end

    combined_css = ArticleBuilder::CSS
                                 .gsub('"DejaVu Serif", serif', '"Liberation Serif"')
                                 .gsub('"DejaVu Sans", sans-serif', '"Liberation Sans"')
                                 .gsub('"DejaVu Sans Mono", monospace', '"Liberation Mono"')

    combined_html = <<~HTML
      <!DOCTYPE html>
      <html lang="pt-BR">
      <head>
        <meta charset="utf-8">
        <title>L.S.C. - Posts</title>
        <style>
      #{combined_css.lines.map { |line| "    #{line}" }.join}
          .post-section {
            page-break-before: always;
          }

          .post-section.first {
            page-break-before: avoid;
          }

          body {
            background: transparent;
          }
        </style>
      </head>
      <body>
      #{sections.join("\n")}
      </body>
      </html>
    HTML

    combined_path = File.join(@output_dir, "combined.html")
    File.write(combined_path, combined_html)

    fonts = Dir["/usr/share/fonts/truetype/liberation/Liberation*.ttf"].sort

    render_pdf(
      combined_html,
      output_path,
      title: "L.S.C. - Posts",
      subject: "Coleção de posts",
      streaming: true,
      fonts: fonts
    )

    puts "  saved #{File.basename(output_path)} (#{File.size(output_path)} bytes)"
  rescue StandardError => error
    log_error("single PDF", error)
    warn "  failed: #{error.class}: #{error.message}"
  end

  def pdf_only
    html_files = Dir[File.join(@html_dir, "*.html")].sort
    html_files = html_files.select { |path| matches_html_only?(path) } unless @only.empty?
    html_files = html_files.first(@limit) if @limit

    if html_files.empty?
      warn "No HTML files found in #{@html_dir}."
      return
    end

    puts "Converting #{html_files.size} HTML file(s) to PDF..."

    html_files.each_with_index do |html_path, index|
      basename = File.basename(html_path, ".html")
      pdf_path = File.join(@pdf_dir, "#{basename}.pdf")

      if File.exist?(pdf_path) && !@force
        puts "[#{index + 1}/#{html_files.size}] Skipping existing #{File.basename(pdf_path)}"
        next
      end

      puts "[#{index + 1}/#{html_files.size}] #{basename}"

      begin
        html = File.binread(html_path).force_encoding("UTF-8")
        document = Nokogiri::HTML(html)
        title = document.at_css("title")&.text&.strip
        title = basename if title.nil? || title.empty?
        subject = document.at_css(".post-subtitle")&.text&.strip.to_s

        render_pdf(html, pdf_path, title: title, subject: subject)
        puts "  saved #{File.basename(pdf_path)} (#{File.size(pdf_path)} bytes)"
      rescue StandardError => error
        log_error(html_path, error)
        warn "  failed: #{error.class}: #{error.message}"
      end
    end
  end

  private

  def render_pdf(html, pdf_path, title:, subject:, streaming: false, fonts: nil)
    options = {
      page_size: "A4",
      margin_top: "18mm",
      margin_bottom: "20mm",
      margin_left: "16mm",
      margin_right: "16mm",
      title: title,
      author: "L.S.C.",
      subject: subject.to_s,
      encoding: "utf-8",
      load_media_error_handling: "ignore"
    }
    options[:streaming] = true if streaming
    options[:font] = fonts if fonts && !fonts.empty?

    Sghtmltopdf.render_to_file(html, pdf_path, **options)
  end

  def ordered_html_files
    all_files = Dir[File.join(@html_dir, "*.html")].sort
    filtered = @only.empty? ? all_files : all_files.select { |path| matches_html_only?(path) }

    first_files = []
    @first.each do |item|
      match = find_html_file(all_files, item)
      if match
        first_files << match unless first_files.include?(match)
      else
        warn "Warning: --first #{item} did not match any HTML file."
      end
    end

    remaining = (filtered | first_files) - first_files
    ordered = first_files + sort_html_files(remaining)
    @limit ? ordered.first(@limit) : ordered
  end

  def find_html_file(files, item)
    normalized = item.sub(%r{\Ahttps?://[^/]+/p/}, "").split(/[?#]/).first
    normalized = File.basename(normalized, ".html")

    files.find do |path|
      basename = File.basename(path, ".html")
      File.basename(path) == item ||
        basename == normalized ||
        basename.end_with?("-#{normalized}")
    end
  end

  def sort_html_files(files)
    numbered, unnumbered = files.partition { |path| number_from_filename(path) }

    ordered = numbered.sort_by do |path|
      number = number_from_filename(path)
      @order == "desc" ? [-number, File.basename(path)] : [number, File.basename(path)]
    end

    ordered + unnumbered.sort_by { |path| File.basename(path) }
  end

  def number_from_filename(path)
    slug = File.basename(path, ".html").sub(/\A\d{4}-\d{2}-\d{2}-/, "")
    match = slug.match(/-(\d+)\z/)
    match && match[1].to_i
  end

  def matches_html_only?(path)
    basename = File.basename(path, ".html")

    @only.any? do |value|
      normalized = value.sub(%r{\Ahttps?://[^/]+/p/}, "").split(/[?#]/).first
      basename == value || basename == normalized || basename.end_with?("-#{normalized}")
    end
  end

  def selected_posts
    posts = archive_posts
    unless @only.empty?
      posts = posts.select { |post| matches_only?(post) }

      found = posts.length
      if found < @only.length
        warn "Warning: #{@only.length - found} --only value(s) did not match any archive post."
      end
    end

    @limit ? posts.first(@limit) : posts
  end

  def matches_only?(post)
    slug = post["slug"].to_s
    url = post["canonical_url"].to_s

    @only.any? do |value|
      normalized = value.sub(%r{\Ahttps?://[^/]+/p/}, "").split(/[?#]/).first
      value == slug || value == url || normalized == slug
    end
  end

  def archive_posts
    posts = []
    seen = {}
    offset = 0

    loop do
      batch = fetch_archive_page(offset)
      break if batch.empty?

      batch.each do |post|
        next if seen[post["id"]]

        seen[post["id"]] = true
        posts << post
      end

      offset += batch.length
      break if offset > 10_000
    end

    posts
  end

  def fetch_archive_page(offset)
    uri = URI.parse(ARCHIVE_URL)
    uri.query = URI.encode_www_form(sort: "new", search: "", offset: offset, limit: ARCHIVE_PAGE_SIZE)

    attempts = 0
    begin
      attempts += 1
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = StealthBrowser::REAL_USER_AGENT
      request["Accept"] = "application/json"

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: true,
        open_timeout: 15,
        read_timeout: 60
      ) { |http| http.request(request) }

      raise "archive HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue StandardError => error
      retry if attempts < 3

      warn "  archive error at offset #{offset}: #{error.class}: #{error.message}"
      []
    end
  end

  def filename_for(post)
    date = Time.iso8601(post["post_date"].to_s).strftime("%Y-%m-%d")
    slug = post["slug"].to_s
    slug = "post-#{post["id"]}" if slug.empty?
    slug = slug.gsub(/[^0-9A-Za-z._-]+/, "-").gsub(/\A-+|-+\z/, "")
    "#{date}-#{slug}"
  rescue ArgumentError
    "post-#{post["id"]}-#{post["slug"]}".gsub(/[^0-9A-Za-z._-]+/, "-")
  end

  def log_error(source, error)
    label = source.is_a?(Hash) ? source["canonical_url"] : source

    File.open(@error_log, "a") do |file|
      file.puts("[#{Time.now.iso8601}] #{label}")
      file.puts("  #{error.class}: #{error.message}")
      Array(error.backtrace).first(8).each { |line| file.puts("  #{line}") }
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  options = {
    output_dir: File.join(__dir__, "output"),
    limit: nil,
    only: [],
    force: false,
    list: false,
    pdf: true,
    pdf_only: false,
    single_pdf: false,
    first: [],
    order: "asc"
  }

  OptionParser.new do |parser|
    parser.banner = "Usage: ruby substack_to_pdf.rb [options]"

    parser.on("--output DIR", "Directory for the generated HTML, PDFs and assets (default: ./output)") do |value|
      options[:output_dir] = value
    end

    parser.on("--limit N", Integer, "Process only the first N posts from the archive") do |value|
      options[:limit] = value
    end

    parser.on("--only SLUG_OR_URL", "Process only the matching post; repeat or use commas for several") do |value|
      options[:only].concat(value.split(",").map(&:strip).reject(&:empty?))
    end

    parser.on("--force", "Overwrite files that already exist") do
      options[:force] = true
    end

    parser.on("--no-pdf", "Only save the scraped HTML, without generating PDFs") do
      options[:pdf] = false
    end

    parser.on("--pdf-only", "Convert HTML files already saved in output/html to PDFs, without scraping") do
      options[:pdf_only] = true
    end

    parser.on("--single-pdf [PATH]", "Combine the saved HTML files into one PDF (default: output/pdf/all-posts.pdf)") do |value|
      options[:single_pdf] = value || true
    end

    parser.on("--first SLUG_OR_FILE", "Place this saved post first; repeat or use commas for several") do |value|
      options[:first].concat(value.split(",").map(&:strip).reject(&:empty?))
    end

    parser.on("--order ORDER", %w[asc desc], "Order the remaining numbered posts ascending or descending (default: asc)") do |value|
      options[:order] = value
    end

    parser.on("--list", "List the archive posts and exit") do
      options[:list] = true
    end

    parser.on("-h", "--help", "Show this help") do
      puts parser
      exit
    end
  end.parse!

  app = SubstackPdf.new(
    output_dir: options[:output_dir],
    limit: options[:limit],
    only: options[:only],
    force: options[:force],
    pdf: options[:pdf],
    first: options[:first],
    order: options[:order]
  )

  if options[:list]
    app.list
  elsif options[:single_pdf]
    output_path = options[:single_pdf] == true ? nil : options[:single_pdf]
    app.single_pdf(output_path: output_path)
  elsif options[:pdf_only]
    app.pdf_only
  else
    app.run
  end
end
