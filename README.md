# Substack to PDF

Download the posts of a Substack publication, store a clean offline copy of each article as HTML, and render them as PDFs.

The tool was originally written for [onlylsc.substack.com](https://onlylsc.substack.com), but the publication URL can be changed with `--base-url` / `--publication`.

## Features

- Reads the public Substack archive API and paginates through every post.
- Detects posts that have not been downloaded yet (`--check-new`).
- Saves article HTML with remote images embedded as data URIs, so the files work offline.
- Keeps each publication in its own author folder, with separate HTML and PDF directories.
- Renders individual PDFs, or one combined PDF containing every saved post.
- Stores all combined PDFs in a shared `single-pdfs/` folder, named after the author by default.
- Skips files that already exist unless `--force` is used.
- Keeps a log of failures in `<output>/<author>/errors.log`.

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

By default everything is written under the `output/` directory next to the script, grouped by author. For example, `onlylsc.substack.com` goes to `output/onlylsc/`, and `kauanacoimbra.substack.com` goes to `output/kauanacoimbra/`.

## How "new posts" are detected

A post is considered new when its generated HTML file does not exist in the author's HTML directory, for example `output/kauanacoimbra/html/`. Every successful export always writes an HTML file, even when PDF generation is enabled, so the HTML library is used as the record of what has already been downloaded.

`--check-new` only reports the missing posts and exits; it does not download them. Run the exporter normally afterwards and the existing posts will be skipped automatically:

```bash
bundle exec ruby substack_to_pdf.rb --check-new
bundle exec ruby substack_to_pdf.rb
```

`--limit` and `--only` also apply to `--check-new`, which makes it easy to inspect a specific subset.

## Options

| Option | Description |
| --- | --- |
| `--output DIR` | Root directory for generated files. Default: `./output`. Each author gets a subfolder inside it. |
| `--base-url URL`, `--publication URL` | Publication to scrape. Accepts the homepage or the `/archive` URL, with or without `https://`. Only the scheme, host and port are used. Default: `https://onlylsc.substack.com`. |
| `--limit N` | Process only the first N posts from the selected archive results. |
| `--only SLUG_OR_URL` | Process only the matching post. Repeat the option or separate values with commas to select several posts. If you pass a full post URL and omit `--publication`/`--base-url`, the publication is inferred from that URL. |
| `--force` | Overwrite existing HTML/PDF files. |
| `--no-pdf` | Save only the scraped HTML; do not generate PDFs. |
| `--pdf-only` | Convert HTML files already present in the author's `html/` folder to PDFs, without scraping the archive. |
| `--single-pdf [NAME_OR_PATH]` | Combine the author's saved HTML files into one PDF. Default: `output/single-pdfs/<author>-all-posts.pdf`. A bare name such as `minha-colecao` creates `output/single-pdfs/minha-colecao.pdf`; a path with directories is used exactly as given. |
| `--first SLUG_OR_FILE` | Place the given saved post first in the combined PDF. Repeat the option or separate values with commas to select several posts. |
| `--order ORDER` | Sort the remaining numbered posts in `asc` or `desc` order for the combined PDF. Default: `asc`. |
| `--list` | List the archive posts and exit. |
| `--check-new` | List archive posts that have no saved HTML yet and exit. |
| `-h`, `--help` | Show the command help. |

When more than one mode is supplied, they are evaluated in this order: `--list`, `--check-new`, `--single-pdf`, `--pdf-only`, and finally the normal export.

`--pdf-only` and `--single-pdf` use the publication selected by `--publication` / `--base-url` to find that author's HTML folder. Pass the same publication URL that was used to download the posts.

### Selecting posts

`--only` accepts any of these forms:

```bash
--only my-post-slug
--only https://onlylsc.substack.com/p/my-post-slug
--only my-post-slug,another-post
--only my-post-slug --only another-post
```

When `--only` contains a full post URL, it also selects the publication. This works without `--base-url` / `--publication`, and the post is saved under that author's folder:

```bash
bundle exec ruby substack_to_pdf.rb \
  --only https://kauanacoimbra.substack.com/p/a-redencao-androgina \
  --no-pdf
```

The same holds for `--pdf-only`, `--single-pdf`, `--check-new`, and `--list`. An explicit `--base-url` always wins. Passing post URLs from more than one publication in the same run is rejected.

`--first` accepts a slug, an HTML file name, or an absolute path to an HTML file:

```bash
--first my-post-slug
--first 2026-09-23-my-post-slug.html
--first /path/to/output/kauanacoimbra/html/2026-09-23-my-post-slug.html
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

The default output is `output/single-pdfs/<author>-all-posts.pdf`.

Generate a combined PDF with a custom name in the shared `single-pdfs/` folder:

```bash
bundle exec ruby substack_to_pdf.rb --single-pdf minha-colecao
```

That creates `output/single-pdfs/minha-colecao.pdf`.

Generate a combined PDF at an explicit path:

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

When switching publications, you no longer need separate `--output` directories for isolation: each author automatically gets its own subfolder. You may still use `--output` to choose a different root directory.

## Output layout

```text
output/
├── kauanacoimbra/
│   ├── assets/          # Cached images, keyed by the SHA-256 of their URL
│   ├── html/            # One clean, self-contained HTML file per post
│   ├── pdf/             # One PDF per post
│   ├── combined.html    # Last generated combined document for this author
│   └── errors.log       # Failures for this author
├── onlylsc/
│   ├── assets/
│   ├── html/
│   ├── pdf/
│   ├── combined.html
│   └── errors.log
└── single-pdfs/
    ├── kauanacoimbra-all-posts.pdf
    ├── onlylsc-all-posts.pdf
    └── minha-colecao.pdf
```

The author folder name is derived from the publication host: `kauanacoimbra.substack.com` becomes `kauanacoimbra`, and `onlylsc.substack.com` becomes `onlylsc`. A custom domain uses the domain name with `www.` removed.

All combined PDFs go to the shared `output/single-pdfs/` folder, regardless of author. The default file name includes the author slug, so generating one for each publication does not overwrite the other.

### Upgrading from the old flat layout

Older versions stored files directly in `output/html`, `output/pdf`, `output/assets` and `output/errors.log`. These are not moved automatically. To keep the existing `onlylsc` download, move them into the new author folder:

```bash
cd /home/ubuntu/substack
mkdir -p output/onlylsc
mv output/html output/onlylsc/html
mv output/pdf output/onlylsc/pdf
mv output/assets output/onlylsc/assets
mv output/errors.log output/onlylsc/errors.log 2>/dev/null || true
mv output/combined.html output/onlylsc/combined.html 2>/dev/null || true
```

If you previously used a flat directory such as `output-kauana`, move it the same way into `output/kauanacoimbra/` or keep using `--output output-kauana`. Otherwise, the program will simply treat the posts as new and download them again.

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
- **A post keeps failing**: Inspect `<output>/<author>/errors.log` for the error type and backtrace. Use `--force` after fixing the problem to retry the file.
