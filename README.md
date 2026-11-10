# Substack to PDF

Download the posts of a Substack publication, store a clean offline copy of each article as HTML, and render them as PDFs.

The tool was originally written for [onlylsc.substack.com](https://onlylsc.substack.com), but the publication URL can be changed with `--base-url` / `--publication`.

## Features

- Reads the public Substack archive API and paginates through every post.
- Detects posts that have not been downloaded yet (`--check-new`).
- Saves article HTML with remote images embedded as data URIs, so the files work offline.
- Renders individual PDFs, or one combined PDF containing every saved post.
- Skips files that already exist unless `--force` is used.
- Keeps a log of failures in `output/errors.log`.

## Requirements

- Ruby 3.1 or newer.
- Bundler.
- Google Chrome or Chromium, required by Ferrum.
- A graphical session (or Xvfb) because the scraper launches a visible Chromium window.

Install the dependencies:

```bash
bundle install
```

## Quick start

```bash
# Download every post and generate both HTML and PDF files
bundle exec ruby substack_to_pdf.rb

# Show the posts available in the archive
bundle exec ruby substack_to_pdf.rb --list

# Show only the posts that have not been downloaded yet
bundle exec ruby substack_to_pdf.rb --check-new

# Download only the first 5 posts
bundle exec ruby substack_to_pdf.rb --limit 5
```

By default everything is written to the `output/` directory next to the script.

## How "new posts" are detected

A post is considered new when its generated HTML file does not exist in `output/html/`. Every successful export always writes an HTML file, even when PDF generation is enabled, so the HTML library is used as the record of what has already been downloaded.

`--check-new` only reports the missing posts and exits; it does not download them. Run the exporter normally afterwards and the existing posts will be skipped automatically:

```bash
bundle exec ruby substack_to_pdf.rb --check-new
bundle exec ruby substack_to_pdf.rb
```

`--limit` and `--only` also apply to `--check-new`, which makes it easy to inspect a specific subset.

## Options

| Option | Description |
| --- | --- |
| `--output DIR` | Directory for generated HTML, PDFs, assets and the error log. Default: `./output`. |
| `--base-url URL`, `--publication URL` | Publication to scrape. Accepts the homepage or the `/archive` URL, with or without `https://`. Only the scheme, host and port are used. Default: `https://onlylsc.substack.com`. |
| `--limit N` | Process only the first N posts from the selected archive results. |
| `--only SLUG_OR_URL` | Process only the matching post. Repeat the option or separate values with commas to select several posts. |
| `--force` | Overwrite existing HTML/PDF files. |
| `--no-pdf` | Save only the scraped HTML; do not generate PDFs. |
| `--pdf-only` | Convert HTML files already present in `output/html` to PDFs, without scraping the archive. |
| `--single-pdf [PATH]` | Combine the saved HTML files into one PDF. Default path: `output/pdf/all-posts.pdf`. A custom path may be supplied. |
| `--first SLUG_OR_FILE` | Place the given saved post first in the combined PDF. Repeat the option or separate values with commas to select several posts. |
| `--order ORDER` | Sort the remaining numbered posts in `asc` or `desc` order for the combined PDF. Default: `asc`. |
| `--list` | List the archive posts and exit. |
| `--check-new` | List archive posts that have no saved HTML yet and exit. |
| `-h`, `--help` | Show the command help. |

When more than one mode is supplied, they are evaluated in this order: `--list`, `--check-new`, `--single-pdf`, `--pdf-only`, and finally the normal export.

### Selecting posts

`--only` accepts any of these forms:

```bash
--only my-post-slug
--only https://onlylsc.substack.com/p/my-post-slug
--only my-post-slug,another-post
--only my-post-slug --only another-post
```

`--first` accepts a slug, an HTML file name, or an absolute path to an HTML file:

```bash
--first my-post-slug
--first 2026-09-23-my-post-slug.html
--first /path/to/output/html/2026-09-23-my-post-slug.html
```

## Examples

Download everything using the default settings:

```bash
bundle exec ruby substack_to_pdf.rb
```

Save only the HTML for the latest three posts:

```bash
bundle exec ruby substack_to_pdf.rb --limit 3 --no-pdf
```

Download a single post and overwrite it if it already exists:

```bash
bundle exec ruby substack_to_pdf.rb --only my-post-slug --force
```

Use a different output directory:

```bash
bundle exec ruby substack_to_pdf.rb --output ~/Documents/substack
```

Generate PDFs from HTML files that were saved earlier:

```bash
bundle exec ruby substack_to_pdf.rb --pdf-only
```

Generate a single combined PDF, with the intro post first:

```bash
bundle exec ruby substack_to_pdf.rb --single-pdf --first welcome
```

Generate a combined PDF at a custom path:

```bash
bundle exec ruby substack_to_pdf.rb --single-pdf ~/Documents/all-posts.pdf
```

Read another publication:

```bash
bundle exec ruby substack_to_pdf.rb \
  --base-url https://kauanacoimbra.substack.com/archive \
  --output output-kauana
```

The URL may be the publication homepage, its `/archive` page, or just the host:

```bash
bundle exec ruby substack_to_pdf.rb --publication kauanacoimbra.substack.com/archive
```

The scraper does not read the publication homepage. It reads the public archive API at `/api/v1/archive` and then each post's canonical URL. This means a customized homepage layout does not affect the result. Passing the `/archive` URL is still supported and is normalized to the publication origin.

When switching publications, use a separate `--output` directory so posts from different publications do not share the same HTML library. Without `--output`, the default is `./output` for every publication.

## Output layout

```text
output/
├── assets/          # Cached images, keyed by the SHA-256 of their URL
├── html/            # One clean, self-contained HTML file per post
├── pdf/             # One PDF per post, plus all-posts.pdf
├── combined.html    # Last generated combined document
└── errors.log       # Appended whenever a post or conversion fails
```

Post files are named `YYYY-MM-DD-slug.html` and `YYYY-MM-DD-slug.pdf`. Posts without a valid publication date fall back to `post-<id>-<slug>`.

## Testing

Run the test suite with:

```bash
bundle exec ruby test/substack_to_pdf_test.rb
```

## Architecture

The script is a thin entry point. The implementation lives under `lib/substack_to_pdf/` and follows a small clean-architecture layering:

```text
substack_to_pdf.rb                  Entry point
lib/substack_to_pdf.rb              Loads the application
lib/substack_to_pdf/cli.rb          Command-line parsing and dependency wiring
lib/substack_to_pdf/settings.rb     Validated configuration value object
lib/substack_to_pdf/domain/         Post entity and archive selection rules
lib/substack_to_pdf/use_cases/      Application workflows
lib/substack_to_pdf/infrastructure/ External adapters and file-system access
```

- **Domain** (`Domain::Post`, `Domain::PostSelector`) contains the post model and selection rules without I/O.
- **Use cases** describe what the application does: export posts, list posts, check for new posts, convert HTML to PDF, and combine HTML files into one PDF.
- **Infrastructure** contains adapters for Ferrum, the Substack archive API, HTTP image caching, Nokogiri HTML processing, PDF rendering, and the output file system.
- **CLI** parses options, builds the concrete adapters, and injects them into the use cases. Dependencies point inward: use cases do not know how the archive or PDF renderer is implemented.

This separation makes each class independently replaceable and testable, and keeps command-line, network, browser, and file-system concerns out of the post logic.

## Troubleshooting

- **`archive HTTP 400`**: Confirm that `--base-url` points to a valid Substack publication. The archive API rejects unsupported pagination parameters and page sizes above 25.
- **Browser does not start**: Make sure Chrome/Chromium is installed and that a display is available. On a headless server, run the command through `xvfb-run`.
- **Unlock keyring prompt**: Chromium is trying to use GNOME Keyring/KWallet to protect its temporary profile. The browser is launched with `--password-store=basic` and `--use-mock-keychain`, which avoid the prompt and are safe for this automation-only profile.
- **Some images are missing**: Image downloads are independent from article scraping. Failures are printed as warnings and the affected image is replaced with a note in the HTML. Re-running the command after fixing network access will use newly downloaded images.
- **A post keeps failing**: Inspect `output/errors.log` for the error type and backtrace. Use `--force` after fixing the problem to retry the file.
