# frozen_string_literal: true

require "cgi"

module SubstackPdf
  module Infrastructure
    # Renders notes and restacks from a Substack profile feed payload. Regular
    # posts keep using ArticleBuilder, which scrapes the publication page.
    class FeedEntryBuilder
      EXTRA_CSS = <<~CSS
        .feed-label { text-transform: uppercase; letter-spacing: 0.08em; font-size: 0.75em; }
        .post-card { border: 1px solid #d8d8d8; border-radius: 8px; padding: 12px; margin: 16px 0; }
        .post-card a { color: inherit; text-decoration: none; }
        .post-card img { max-width: 100%; height: auto; border-radius: 6px; margin-bottom: 8px; }
        .post-card-title { display: block; font-weight: bold; margin-bottom: 4px; }
        .post-card-subtitle { display: block; color: #555; }
        .post-card-publication { display: block; color: #888; font-size: 0.85em; margin-top: 6px; }
        .restack-link { display: inline-block; margin: 12px 0; padding: 10px 14px;
          border: 1px solid #d8d8d8; border-radius: 8px; text-decoration: none; }
        .note-attachment { border-left: 3px solid #d8d8d8; padding-left: 12px; margin: 16px 0; }
        .image-error { color: #888; font-style: italic; }
      CSS

      def initialize(media_cache, base_url:)
        @media_cache = media_cache
        @base_url = base_url
      end

      def build(post)
        content = post.restack? ? restack_html(post) : note_html(post)
        document_html(post, content)
      end

      private

      def note_html(post)
        comment = post.payload.to_h["comment"] || {}
        body = comment["body_json"] ? render_node(comment["body_json"]) : paragraphs(comment["body"])
        body + render_attachments(comment["attachments"])
      end

      def restack_html(post)
        payload = post.payload.to_h

        if payload["post"].is_a?(Hash)
          data = payload["post"]
          title = CGI.escapeHTML(data["title"].to_s)
          subtitle = data["subtitle"].to_s.strip
          subtitle_html = subtitle.empty? ? "" : %(<p>#{CGI.escapeHTML(subtitle)}</p>)
          %(<p><strong>#{title}</strong></p>#{subtitle_html}) +
            %(<p><a class="restack-link" href="#{href(post.canonical_url)}">Open original post</a></p>)
        else
          comment = payload["comment"] || {}
          name = comment["name"].to_s.strip
          note = name.empty? ? "original note" : "note by #{CGI.escapeHTML(name)}"
          %(<p>Restacked #{note}.</p>) +
            %(<p><a class="restack-link" href="#{href(post.canonical_url)}">Open original note</a></p>)
        end
      end

      def render_attachments(attachments)
        Array(attachments).map { |attachment| render_attachment(attachment) }.join
      end

      def render_attachment(attachment)
        return "" unless attachment.is_a?(Hash)

        case attachment["type"].to_s
        when "image"
          image_figure(attachment["imageUrl"], attachment["caption"])
        when "post"
          post_card(attachment["post"] || {}, attachment["publication"])
        when "comment"
          comment_attachment(attachment["comment"] || {})
        when "link"
          href = attachment["url"] || attachment["href"]
          href.to_s.empty? ? "" : %(<p><a href="#{href(href)}">#{CGI.escapeHTML(href.to_s)}</a></p>)
        else
          ""
        end
      end

      def comment_attachment(comment)
        body = comment["body_json"] ? render_node(comment["body_json"]) : paragraphs(comment["body"])
        name = comment["name"].to_s.strip
        author = name.empty? ? "Quoted note" : "Quoted note from #{CGI.escapeHTML(name)}"
        %(<blockquote class="note-attachment"><p><strong>#{author}</strong></p>#{body}#{render_attachments(comment['attachments'])}</blockquote>)
      end

      def image_figure(url, caption = nil)
        source = url.to_s
        return "" if source.empty?

        data = @media_cache.data_uri(source)
        image = if data
                  %(<img src="#{data}" alt="#{CGI.escapeHTML(caption.to_s)}">)
                else
                  %(<span class="image-error">[Image unavailable]</span>)
                end
        caption_html = caption.to_s.empty? ? "" : "<figcaption>#{CGI.escapeHTML(caption.to_s)}</figcaption>"
        %(<figure>#{image}#{caption_html}</figure>)
      end

      def post_card(post, publication)
        return "" unless post.is_a?(Hash)

        url = post["canonical_url"].to_s
        title = post["title"].to_s.strip
        title = post["description"].to_s.strip if title.empty?
        subtitle = post["subtitle"].to_s.strip
        publication_name = publication.is_a?(Hash) ? publication["name"].to_s.strip : ""

        cover = post["cover_image"].to_s
        image = cover.empty? ? "" : image_figure(cover)
        subtitle_html = subtitle.empty? ? "" : %(<span class="post-card-subtitle">#{CGI.escapeHTML(subtitle)}</span>)
        publication_html = publication_name.empty? ? "" : %(<span class="post-card-publication">#{CGI.escapeHTML(publication_name)}</span>)
        title_html = %(<span class="post-card-title">#{CGI.escapeHTML(title)}</span>)

        content = image + title_html + subtitle_html + publication_html
        content = %(<a href="#{href(url)}">#{content}</a>) unless url.empty?
        %(<figure class="post-card">#{content}</figure>)
      end

      def render_node(node)
        return "" unless node.is_a?(Hash)

        type = node["type"].to_s
        children = render_children(node)

        case type
        when "doc"
          children
        when "paragraph"
          "<p>#{children}</p>"
        when "text"
          render_text(node)
        when "hard_break"
          "<br>"
        when "heading"
          level = node.dig("attrs", "level").to_i
          level = 2 unless (1..6).cover?(level)
          "<h#{level}>#{children}</h#{level}>"
        when "bullet_list"
          "<ul>#{children}</ul>"
        when "ordered_list"
          "<ol>#{children}</ol>"
        when "list_item"
          "<li>#{children}</li>"
        when "blockquote"
          "<blockquote>#{children}</blockquote>"
        when "code_block"
          "<pre><code>#{CGI.escapeHTML(node['text'].to_s)}</code></pre>"
        when "horizontal_rule"
          "<hr>"
        when "image"
          image_figure(node.dig("attrs", "src"), node.dig("attrs", "alt"))
        else
          children
        end
      end

      def render_children(node)
        Array(node["content"]).map { |child| render_node(child) }.join
      end

      def render_text(node)
        text = CGI.escapeHTML(node["text"].to_s)

        Array(node["marks"]).each do |mark|
          case mark["type"].to_s
          when "bold", "strong"
            text = "<strong>#{text}</strong>"
          when "italic", "em"
            text = "<em>#{text}</em>"
          when "code"
            text = "<code>#{text}</code>"
          when "underline"
            text = "<u>#{text}</u>"
          when "strike"
            text = "<s>#{text}</s>"
          when "link"
            url = mark.dig("attrs", "href").to_s
            text = %(<a href="#{href(url)}">#{text}</a>) unless url.empty?
          end
        end

        text
      end

      def paragraphs(value)
        text = value.to_s.strip
        return "" if text.empty?

        text.split(/\n{2,}/).map do |paragraph|
          "<p>#{CGI.escapeHTML(paragraph).gsub("\n", '<br>')}</p>"
        end.join
      end

      def document_html(post, content)
        subtitle_html = post.subtitle.empty? ? "" : %(<p class="post-subtitle">#{CGI.escapeHTML(post.subtitle)}</p>)
        label = post.restack? ? "Restack" : "Note"
        author = feed_author(post)

        <<~HTML
          <!DOCTYPE html>
          <html lang="pt-BR">
          <head>
            <meta charset="utf-8">
            <title>#{CGI.escapeHTML(post.display_title)}</title>
            <style>
          #{ArticleStylesheet::CSS.lines.map { |line| "    #{line}" }.join}
          #{EXTRA_CSS.lines.map { |line| "    #{line}" }.join}
            </style>
          </head>
          <body>
            <article class="post">
              <header class="post-header">
                <h1 class="post-title">#{CGI.escapeHTML(post.display_title)}</h1>
                #{subtitle_html}
                <p class="post-meta">
                  <span class="feed-label">#{label}</span>
                  #{author.empty? ? "" : "&middot; #{CGI.escapeHTML(author)}"}
                  #{post.published_at ? "&middot; #{post.published_at.strftime('%d/%m/%Y')}" : ""}
                  &middot; <a href="#{href(post.canonical_url)}">Original</a>
                </p>
              </header>
              <div class="post-body">
          #{content}
              </div>
            </article>
          </body>
          </html>
        HTML
      end

      def feed_author(post)
        payload = post.payload.to_h
        comment = payload["comment"] || {}
        post_data = payload["post"] || {}
        comment["name"].to_s.strip.then do |name|
          next name unless name.empty?

          post_data["publishedBylines"].to_a.map { |byline| byline["name"].to_s }.reject(&:empty?).join(", ")
        end
      end

      def href(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end
