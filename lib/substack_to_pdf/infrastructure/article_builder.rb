# frozen_string_literal: true

require "cgi"
require "json"
require "nokogiri"
require "uri"

module SubstackPdf
  module Infrastructure
    # Receives the scraped article and produces a self-contained, print-ready HTML page.
    class ArticleBuilder
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
        title = post.title if title.nil? || title.empty?

        subtitle = article.at_css("h3.subtitle")&.text&.strip
        subtitle = post.subtitle if subtitle.nil? || subtitle.empty?

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
          #{ArticleStylesheet::CSS.lines.map { |line| "    #{line}" }.join}
            </style>
          </head>
          <body>
            <article class="post">
              <header class="post-header">
                <h1 class="post-title">#{CGI.escapeHTML(title)}</h1>
                #{subtitle_html}
                <p class="post-meta">Publicado em #{format_date(post.published_at)} &middot; <a href="#{CGI.escapeHTML(post.canonical_url)}">Post original</a></p>
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
        value ? value.strftime("%d/%m/%Y") : ""
      end
    end
  end
end
