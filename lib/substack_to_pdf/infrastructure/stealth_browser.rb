# frozen_string_literal: true

require "ferrum"

module SubstackPdf
  module Infrastructure
    # Low-level Ferrum wrapper that makes the headless browser look less automated.
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
        "password-store" => "basic",
        "use-mock-keychain" => nil,
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
  end
end
