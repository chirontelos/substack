# Substack to PDF

Download the posts of a Substack publication, store a clean offline copy of each article as HTML, and render them as PDFs.

The tool was originally written for [onlylsc.substack.com](https://onlylsc.substack.com), but the publication URL can be changed with `--publication` or a configuration file.

## Features

- Reads the public Substack archive API and paginates through every post.
- Detects posts that have not been downloaded yet (`--check-new`).
- Saves article HTML with remote images embedded as data URIs, so the files work offline.
- Keeps each publication in its own author folder, with separate HTML and PDF directories.
- Renders individual PDFs, or one combined PDF containing every saved post.
- Stores all combined PDFs in a shared `single-pdfs/` folder, named after the author by default.
- Skips files that already exist unless `--force` is used.
- Reads defaults from a YAML file with `--config`.
- Keeps a log of failures in `<root>/<author>/errors.log`.

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

A publication is required unless a configuration file or a full `--post` URL provides it.

```bash
# Download every post and generate both HTML and PDF files
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com

# Show the posts available in the archive
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --list

# Show only the posts that have not been downloaded yet
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --check-new

# Download only the first 5 posts that are not saved yet
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --limit 5
```

Or save the publication once in a config file:

```bash
cp substack_to_pdf.example.yml substack_to_pdf.yml
# edit substack_to_pdf.yml
bundle exec ruby substack_to_pdf.rb --config substack_to_pdf.yml
```

By default everything is written under the `output/` directory next to the script, grouped by author. For example, `onlylsc.substack.com` goes to `output/onlylsc/`, and `kauanacoimbra.substack.com` goes to `output/kauanacoimbra/`.

## How "new posts" are detected

A post is considered new when its generated HTML file does not exist in the author's HTML directory, for example `output/kauanacoimbra/html/`. Every successful export always writes an HTML file, even when PDF generation is enabled, so the HTML library is used as the record of what has already been downloaded.

`--check-new` only reports the missing posts and exits; it does not download them. Run the exporter normally afterwards and the existing posts will be skipped automatically:

```bash
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --check-new
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com
```

`--limit` and `--post` also apply to `--check-new`. For export and `--check-new`, `--limit` counts only posts that are not saved yet. A warning is printed so the behavior is explicit.

## Configuration file

`--config FILE` reads defaults from a YAML file. Command-line flags always win over config values.

```yaml
publication: https://kauanacoimbra.substack.com
root: ./output
limit: 5
post:
  - a-redencao-androgina
first:
  - welcome
order: asc
force: false
html_only: false
quiet: false
json: false
```

Supported keys:

| Key | Type | Equivalent option |
| --- | --- | --- |
| `publication` | string | `--publication` |
| `root` | string | `--root` |
| `limit` | integer | `--limit` |
| `post` | string or list | `--post` |
| `first` | string or list | `--first` |
| `order` | `asc` or `desc` | `--order` |
| `force` | boolean | `--force` |
| `html_only` | boolean | `--html-only` |
| `quiet` | boolean | `--quiet` |
| `json` | boolean | `--json` |

Modes such as `--list`, `--check-new`, `--pdf-only`, and `--single-pdf` are intentionally not part of the config file. Choose them on the command line. Unknown keys produce a warning.

See `substack_to_pdf.example.yml` for a commented template.

## Options

| Option | Description |
| --- | --- |
| `--config FILE` | Load defaults from a YAML configuration file. CLI flags override config values. |
| `--root DIR` | Root directory for generated files. Default: `./output`. Each author gets a subfolder inside it. |
| `--publication URL` | Publication to scrape. Accepts the homepage or the `/archive` URL, with or without `https://`. Only the scheme, host and port are used. Required unless set by `--config` or inferred from a full `--post` URL. |
| `--post SLUG_OR_URL` | Process only the matching post. Repeat the option or separate values with commas to select several posts. If you pass a full post URL and omit `--publication`, the publication is inferred from that URL. |
| `--limit N` | Process at most N posts. For export and `--check-new`, only posts that are not saved yet are counted. |
| `--list` | List the archive posts and exit. |
| `--check-new` | List archive posts that have no saved HTML yet and exit. |
| `--pdf-only` | Convert HTML files already present in the author's `html/` folder to PDFs, without scraping the archive. |
| `--single-pdf` | Combine the author's saved HTML files into one PDF. Default: `output/single-pdfs/<author>-all-posts.pdf`. |
| `--name NAME` | With `--single-pdf`, write to `<root>/single-pdfs/NAME.pdf`. A custom name is not overwritten unless `--force` is used. |
| `--path PATH` | With `--single-pdf`, write the combined PDF to exactly this path. A custom path is not overwritten unless `--force` is used. |
| `--first SLUG_OR_FILE` | With `--single-pdf`, place the given saved post first. Repeat the option or separate values with commas to select several posts. |
| `--order ORDER` | With `--single-pdf`, sort the remaining numbered posts in `asc` or `desc` order. Default: `asc`. |
| `--force` | Overwrite existing HTML/PDF files, including custom single PDFs. |
| `--html-only` | Save only the scraped HTML; do not generate PDFs. |
| `--dry-run` | Print what would be downloaded, converted, or written without writing files or launching the browser. |
| `--allow-empty` | Exit with status 0 when no posts or files are selected. Without it, an empty result exits with status 2. |
| `--quiet` | Suppress progress messages. Data and warnings are still printed. |
| `--json` | Emit JSON instead of text for `--list` and `--check-new`. |
| `--version` | Show the program version. |
| `-h`, `--help` | Show the command help. |

Only one mode can be selected at a time: `--list`, `--check-new`, `--pdf-only`, or `--single-pdf`. Combining modes is an error rather than silently choosing one.

Flags that do not apply to the selected mode produce a warning and are ignored. For example, `--first` is only used by `--single-pdf`, and `--json` is only used by `--list` and `--check-new`.

`--pdf-only` and `--single-pdf` use `--publication` to find that author's HTML folder. Pass the same publication URL that was used to download the posts, or a post URL with `--post`, which also identifies the publication.

### Selecting posts

`--post` accepts any of these forms:

```bash
--post my-post-slug
--post https://onlylsc.substack.com/p/my-post-slug
--post my-post-slug,another-post
--post my-post-slug --post another-post
```

When `--post` contains a full post URL, it also selects the publication. This works without `--publication`, and the post is saved under that author's folder:

```bash
bundle exec ruby substack_to_pdf.rb \
  --post https://kauanacoimbra.substack.com/p/a-redencao-androgina \
  --html-only
```

The same holds for `--pdf-only`, `--single-pdf`, `--check-new`, and `--list`. An explicit `--publication` always wins. Passing post URLs from more than one publication in the same run is rejected.

`--first` accepts a slug, an HTML file name, or an absolute path to an HTML file:

```bash
--first my-post-slug
--first 2026-09-23-my-post-slug.html
--first /path/to/output/kauanacoimbra/html/2026-09-23-my-post-slug.html
```

### Exit codes

```text
0  success
1  usage or configuration error
2  the requested work produced nothing
```

Exit status 2 is used when `--list` or export selects no posts, or when `--pdf-only` / `--single-pdf` finds no HTML files. Use `--allow-empty` when an empty result is expected, for example in a cron job. `--check-new` treats “no new posts” as success.

### Dry runs, quiet mode, and JSON

Preview work without writing files or launching Chrome:

```bash
bundle exec ruby substack_to_pdf.rb \
  --post https://onlylsc.substack.com/p/my-post-slug \
  --dry-run
```

Suppress progress messages:

```bash
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --limit 5 --quiet
```

Emit machine-readable output for listing commands:

```bash
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --list --json
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --check-new --json
```

The JSON output is an array of objects with `date`, `slug`, `title`, and `url`. Warnings still go to stderr, so stdout remains valid JSON.

## Examples

Download everything:

```bash
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com
```

Save only the HTML for the latest three unsaved posts:

```bash
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --limit 3 --html-only
```

Download a single post and overwrite it if it already exists:

```bash
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --post my-post-slug --force
```

Use a different root directory:

```bash
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --root ~/Documents/substack
```

Generate PDFs from HTML files that were saved earlier:

```bash
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --pdf-only
```

Generate a single combined PDF, with the intro post first:

```bash
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --single-pdf --first welcome
```

The default output is `output/single-pdfs/<author>-all-posts.pdf`.

Generate a combined PDF with a custom name in the shared `single-pdfs/` folder:

```bash
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --single-pdf --name minha-colecao
```

That creates `output/single-pdfs/minha-colecao.pdf`. If that file already exists, the command refuses to overwrite it unless `--force` is passed.

Generate a combined PDF at an explicit path:

```bash
bundle exec ruby substack_to_pdf.rb --publication https://onlylsc.substack.com --single-pdf --path ~/Documents/all-posts.pdf
```

Read another publication:

```bash
bundle exec ruby substack_to_pdf.rb \
  --publication https://kauanacoimbra.substack.com/archive \
  --root output-kauana
```

The URL may be the publication homepage, its `/archive` page, or just the host:

```bash
bundle exec ruby substack_to_pdf.rb --publication kauanacoimbra.substack.com/archive
```

The scraper does not read the publication homepage. It reads the public archive API at `/api/v1/archive` and then each post's canonical URL. This means a customized homepage layout does not affect the result. Passing the `/archive` URL is still supported and is normalized to the publication origin.

When switching publications, you no longer need separate `--root` directories for isolation: each author automatically gets its own subfolder. You may still use `--root` to choose a different root directory.

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

If you previously used a flat directory such as `output-kauana`, move it the same way into `output/kauanacoimbra/` or keep using `--root output-kauana`. Otherwise, the program will simply treat the posts as new and download them again.

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

- **`publication is required`**: Pass `--publication`, use a full post URL with `--post`, or set `publication` in a `--config` file.
- **`archive HTTP 400`**: Confirm that `--publication` points to a valid Substack publication. The archive API rejects unsupported pagination parameters and page sizes above 25.
- **Browser does not start**: Make sure Chrome/Chromium is installed and that a display is available. On a headless server, run the command through `xvfb-run`.
- **Unlock keyring prompt**: Chromium is trying to use GNOME Keyring/KWallet to protect its temporary profile. The browser is launched with `--password-store=basic` and `--use-mock-keychain`, which avoid the prompt and are safe for this automation-only profile.
- **Some images are missing**: Image downloads are independent from article scraping. Failures are printed as warnings and the affected image is replaced with a note in the HTML. Re-running the command after fixing network access will use newly downloaded images.
- **A post keeps failing**: Inspect `<output>/<author>/errors.log` for the error type and backtrace. Use `--force` after fixing the problem to retry the file.
