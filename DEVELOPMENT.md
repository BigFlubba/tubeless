# Local Development Guide

## Dev Server (Docker — recommended)

Uses the prebuilt CI base image with all tooling (Elixir, Node, yt-dlp, ffmpeg, Deno, Apprise) baked in. Source is volume-mounted so edits reflect live.

```bash
docker compose up
# App at http://localhost:4008
```

## Dev Server (Native)

Requires Elixir 1.17+, OTP 27, Node 24, Yarn, yt-dlp, ffmpeg.

```bash
mix setup              # deps + DB create/migrate/seed + assets
iex -S mix phx.server  # http://localhost:4008
```

## Tests

```bash
mix test                                      # all tests (auto creates/migrates test DB)
mix test test/path/to/file_test.exs           # single file
mix test test/path/to/file_test.exs:42        # single test by line
```

Tests mock yt-dlp/apprise via `test/scripts/yt-dlp-mocks/` — no real network calls.

**On macOS** the suite can't run natively (needs the Linux SQLean `.so` extensions
and the yt-dlp/ffmpeg/Deno/Apprise toolchain). Run tests through Docker instead —
same pinned ci-base image as CI, with a shared warm build cache:

```bash
tooling/test.sh                               # whole suite (fast iteration loop)
tooling/test.sh test/path/to/file_test.exs    # single file — args pass through to `mix test`
tooling/test.sh test/path/to/file_test.exs:42 # single test by line
tooling/test.sh --failed                      # re-run only last run's failures
tooling/lint_test.sh                          # full `mix check` — the pre-commit gate
```

## Quality Checks

```bash
mix check              # full CI suite: formatter + compiler + sobelow + prettier + ex_unit
```

Individual:

```bash
mix credo              # Elixir style
mix sobelow --config   # security scan
yarn run lint:check    # Prettier (JS/CSS)
yarn run lint:fix      # Prettier auto-fix
```

## Production Docker Build

```bash
# Standard (depends on CI base image)
docker build -f docker/selfhosted.Dockerfile -t tubeless:local .

# Self-contained (no external base image dependency)
docker build -f selfhosted.og.Dockerfile -t tubeless:local .
```

`tooling/docker-build-local.sh` wraps the standard build and adds a run/shell
loop on top, for smoke-testing the actual release image without pushing a PR:

```bash
tooling/docker-build-local.sh                # build only, tag tubeless:local
tooling/docker-build-local.sh --run           # build, then follow its logs (Ctrl-C tears it down)
tooling/docker-build-local.sh --shell         # build, run detached, then attach a shell
tooling/docker-build-local.sh --no-cache      # ignore Docker layer cache
tooling/docker-build-local.sh --tag foo:bar   # build under a different tag
```

### `docker-build-local.sh` vs. `docker compose up`

They exercise different halves of the project and aren't interchangeable:

|            | `docker compose up`                                            | `tooling/docker-build-local.sh`                                                    |
| ---------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Dockerfile | `docker/dev.Dockerfile`                                        | `docker/selfhosted.Dockerfile` (the real release image, same as `docker-pr` in CI) |
| Source     | Bind-mounted (`.:/app`) — live edits, no rebuild               | Baked into the image at build time — edit, then rebuild to see changes             |
| App start  | `mix phx.server` via `docker-run.dev.sh` (compiles on the fly) | The compiled OTP release's `docker_start` entrypoint                               |
| State      | Whatever's on disk under the repo (DB, downloads live in-tree) | Persisted separately in `tmp/docker-local/{config,downloads,podcasts}`             |
| Port       | Fixed `4008`                                                   | `PORT` env, default `8945`                                                         |
| Use case   | Day-to-day feature/bugfix work with fast iteration             | Verifying the shippable image builds and boots correctly before/instead of a PR    |

Rule of thumb: use `docker compose up` while writing code; reach for
`tooling/docker-build-local.sh --run` (or `--shell` to poke around inside) when
you want to confirm the actual production image works — e.g. after touching
the Dockerfile, release config, or anything only the compiled release path
exercises.

## Utility: List Published GHCR Images

Requires `gh` CLI auth.

```bash
bash tooling/list-images.sh                         # CommunityMaintained/tubeless
bash tooling/list-images.sh MyOrg my-image-name    # custom org/image
```

## Indexing System

Tubeless uses two complementary indexing strategies to detect new media. Together they balance detection latency against API/bandwidth cost.

### Fast Indexing

**Worker:** `lib/pinchflat/fast_indexing/fast_indexing_worker.ex`
**Queue:** `fast_indexing` (concurrency: `YT_DLP_WORKER_CONCURRENCY`, default 2)

Runs every 10 minutes per source (when `fast_index: true`). Cheap — only checks recent items, no full yt-dlp crawl.

**Execution flow:**

1. Fetches up to 50 recent media IDs for the source:
   - Prefers YouTube Data API v3 (`playlistItems` endpoint) if a `youtube_api_key` is configured. Multiple keys are supported and round-robined via an Agent.
   - Falls back to parsing `<yt:videoId>` tags from the YouTube RSS feed.
2. Queries the database for existing `MediaItem` records matching those IDs.
3. For each **new** media ID: constructs the watch URL, runs yt-dlp with `--simulate --skip-download` to fetch metadata, then upserts a `MediaItem` via `Media.create_media_item_from_backend_attrs/2` (conflict target: `[:source_id, :media_id]`).
4. Immediately kicks off a download job for each newly created pending item.
5. Calls `DownloadingHelpers.enqueue_pending_download_tasks/1` as a cleanup pass to catch any stragglers.
6. Sends an Apprise notification if new downloadable items were found (and `download_media: true`).
7. Reschedules itself 10 minutes out.

Fast indexing is started by the slow indexing worker after slow indexing completes, and only runs while `source.fast_index` is true.

### Slow Indexing

**Worker:** `lib/pinchflat/slow_indexing/media_collection_indexing_worker.ex`
**Queue:** `media_collection_indexing` (concurrency: `YT_DLP_WORKER_CONCURRENCY`, default 2)

A full yt-dlp metadata fetch of the entire source. Expensive but thorough. Runs on a schedule (`index_frequency_minutes`, default 1440 = 24 h). When fast indexing is enabled for a source, slow indexing is backed off to every 30 days — fast indexing covers the gap.

**Execution flow:**

1. **File follower setup** — starts `FileFollowerServer`, a GenServer that polls the yt-dlp output file every second. As yt-dlp writes JSON lines, the follower immediately parses each one, upserts a `MediaItem`, and kicks off a download job. This means downloads can begin before the full index completes.

2. **Download archive** (channels only, scheduled re-indexing) — queries the most recent 50 media items for the source, skips the 20 newest, and writes the next 30 as a yt-dlp archive file (`youtube {media_id}` one per line). This is passed with `--break-on-existing` so yt-dlp stops when it reaches known media and doesn't re-crawl the full history.

3. **Per-tab crawl** (YouTube channels only) — channels are indexed as three separate yt-dlp invocations against `/videos`, `/shorts`, and `/streams` tab URLs. This is required because `--break-on-existing` aborts the entire yt-dlp process when it hits a known item, not just the current content type — a single bare-channel-URL run would stop at the first known video and never reach shorts or streams tabs. Each tab gets its own archive filtered to its content type. Playlists and non-YouTube sources are indexed as a single URL. A tab that errors (e.g. channel has no Shorts) is skipped; the run fails only if all tabs fail.

4. **Deduplication** — after all tabs complete, results are deduped by `media_id` before the final upsert pass.

5. **Cleanup** — updates `source.last_indexed_at`, then calls `DownloadingHelpers.enqueue_pending_download_tasks/1` to enqueue anything the file follower may have missed.

6. **Fast indexing handoff** — deletes any pending fast-indexing jobs for the source and re-enqueues them fresh (so their 10-minute clock starts from now, not from before the slow index ran).

### How They Complement Each Other

|                     | Fast                              | Slow                                   |
| ------------------- | --------------------------------- | -------------------------------------- |
| Frequency           | Every 10 min                      | Every 24 h (or 30 d with fast enabled) |
| Scope               | Last ~50 items via RSS/API        | Full channel/playlist history          |
| yt-dlp calls        | One per new video (metadata only) | One per content tab (full crawl)       |
| Real-time downloads | Yes (per new ID)                  | Yes (via file follower)                |
| Download archive    | No                                | Yes (channels, scheduled re-index)     |

On first source creation, slow indexing runs immediately to build the full media catalog. Once that completes, fast indexing takes over for low-latency detection of new uploads. Both paths use the same `create_media_item_from_backend_attrs/2` upsert so concurrent runs are idempotent.

### How yt-dlp Is Invoked During Indexing

All yt-dlp calls funnel through `YtDlp.CommandRunner.run/5` (`lib/pinchflat/yt_dlp/command_runner.ex`), which implements the `YtDlpCommandRunner` behaviour (mockable in tests via the `yt_dlp_runner` config). The runner builds the argument list, shells out, and reads results back from a file.

**Execution wrapper.** yt-dlp is never called directly — it's launched through `priv/cmd_wrapper.sh`, which runs the command in the background and kills it (`kill -KILL`) the moment its stdin closes. This is what lets Oban terminate the external yt-dlp process when a job is cancelled or the worker dies, rather than leaving an orphaned 30-minute crawl running.

**Output capture.** Commands do **not** parse stdout (yt-dlp writes warnings/progress there and pollutes JSON). Instead every call appends `--print-to-file "<template>" <filepath>`, writing one JSON object per line to a tmpfile. `ResponseDecoder` (`response_decoder.ex`) reads the file back and decodes each line independently, returning a clean `{:error, binary()}` on malformed/truncated output instead of raising.

**Option building.** A keyword list of options is converted to CLI args by `CliUtils.parse_options/1` (`lib/pinchflat/utils/cli_utils.ex`): atom keys become kebab-cased flags (`:skip_download` → `--skip-download`, `ignore_no_formats_error` → `--ignore-no-formats-error`), and key/value pairs become `--flag value` (`sleep_interval: 2.5` → `--sleep-interval 2.5`). `CommandRunner` concatenates option groups in a fixed order: caller opts → print-to-file → cookies → rate-limit → misc → globals. Globals always applied: `--windows-filenames --quiet --cache-dir <tmp>/yt-dlp-cache`.

**Download quality selection.** `Downloading.QualityOptionBuilder` converts a MediaProfile's resolution, codec, container, and audio-track preferences into yt-dlp `--format` and `--format-sort` options. If `ignore_youtube_super_resolution` is enabled, it adds `[format_note!*=?AI-upscaled]` to every selected stream and fallback branch. The unknown-inclusive `?` keeps formats that do not expose `format_note`; filtering the final `best` fallback prevents it from re-selecting an AI-upscaled video. The option is off by default and affects downloads and predicted output paths, not collection indexing.

**Cross-cutting options** (added by `CommandRunner`, not the callers):

- **Cookies** — `--cookies <extras>/cookies.txt` is added only when the caller passes `use_cookies: true` _and_ a non-empty cookies file exists. Callers decide via `Sources.use_cookies?(source, :metadata | :indexing)`.
- **Rate limiting** — `--limit-rate` from the `throughput_limit` setting, plus jittered `--sleep-requests`/`--sleep-interval`/`--sleep-subtitles` (unless the caller passes `skip_sleep_interval: true`). Jitter is applied per-run via `NumberUtils.add_jitter`.
- **Misc** — `--restrict-filenames` when that setting is enabled.

**Slow indexing command** — built in `SlowIndexingHelpers` and run via `MediaCollection.get_media_attributes_for_collection/3`. Base flags:

```
--simulate --skip-download --ignore-no-formats-error --no-warnings
```

`--ignore-no-formats-error` keeps premiere/upcoming videos from aborting the crawl; `--no-warnings` keeps the JSON output clean. For scheduled channel re-indexing it also adds `--break-on-existing --download-archive <tmpfile>`, where the archive is a `youtube <media_id>` list of recent-but-not-newest items (skip the 20 newest, take the next 30) so yt-dlp halts once it reaches known media. If the source has an `index_cutoff_date`, each YouTube channel tab additionally gets `--break-match-filters "upload_date >= YYYYMMDD"` plus `--break-match-filters "!upload_date"` (repeated filters are OR'd — break only when a video _has_ an upload date and it's older than the cutoff), aborting the crawl at the cutoff even on first/forced indexes; playlists and non-YouTube sources never get this since their listing order isn't newest-first. The indexing output template captures the fields needed to build a `MediaItem`:

```
%(.{id,title,live_status,original_url,description,aspect_ratio,duration,upload_date,timestamp,playlist_index,filename})j
```

The output filepath is passed explicitly (not auto-generated) so the `FileFollowerServer` can tail the same file line-by-line as yt-dlp appends to it. Exit codes are interpreted loosely for indexing: `0` is success, and `101` (break-on-existing / max-downloads hit) and `1` (a missing tab on a channel) are treated as expected rather than failures.

**Fast indexing command** — RSS/API supplies the recent media IDs (no yt-dlp), then each _new_ ID is resolved individually via `YtDlp.Media.get_media_attributes/3` with:

```
--simulate --skip-download
```

reusing the same indexing output template. There's no file follower here — it's a blocking call per video that returns the full JSON.

### Per-Source Indexing Settings

| Setting                                         | Default | Description                                                                                                                                                                 |
| ----------------------------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fast_index`                                    | `false` | Enable fast indexing (RSS/API polling every 10 min)                                                                                                                         |
| `index_frequency_minutes`                       | `1440`  | Slow indexing interval; `0` = index once and stop; forced to 43,200 (30 d) when `fast_index: true`                                                                          |
| `download_media`                                | `true`  | Whether indexed items are added to the download queue                                                                                                                       |
| `download_cutoff_date`                          | —       | Skip media uploaded before this date                                                                                                                                        |
| `index_cutoff_date`                             | —       | Stop slow indexing once it reaches videos uploaded before this date (YouTube channels only; set a few days before the download cutoff). Applies to first/forced indexes too |
| `title_filter_regex`                            | —       | Only download media whose title matches this pattern                                                                                                                        |
| `min_duration_seconds` / `max_duration_seconds` | —       | Filter by duration                                                                                                                                                          |
| `enabled`                                       | `true`  | When false, indexing tasks are deleted and no downloads run                                                                                                                 |

### Global Indexing Settings

| Setting                            | Description                                                                                                                       |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `youtube_api_key`                  | Comma-separated YouTube Data API v3 keys; fast indexing uses these in round-robin. Without this, fast indexing falls back to RSS. |
| `extractor_sleep_interval_seconds` | Delay between yt-dlp requests (rate limiting, default 0)                                                                          |
| `ignore_unavailable_media`         | Mark members-only/private/removed videos as permanently unavailable instead of retrying                                           |

## Podcast Support

Two delivery modes, sharing the same feed builders (`lib/pinchflat/podcasts/`):

### Dynamic feeds (served by Tubeless)

The original mode. `GET /sources/opml` (all sources, `route_token`-protected), `GET /sources/:uuid/feed`
(per-source RSS), and image/`/media/:uuid/stream` endpoints render everything per-request. These routes
deliberately bypass basic auth so podcast apps work — fine on a trusted LAN, not something to expose
to the internet.

### Static podcasts (serve-in-place)

For setups where Tubeless is never reachable by the podcast client. Podcast sources download
**straight into** the servable podcast library — nothing is copied — and any static web server
(nginx etc.) hosts it independently:

```
<PODCAST_PATH>/                 # the podcast library; default: <media dir>/podcasts
  opml.xml                      # all published sources
  lex-fridman/                  # the source's stable slug
    feed.xml                    # generated
    cover.jpg                   # generated (small copy of the source cover)
    2026-07-19 dQw4w9WgXcQ.mp3  # the download itself — never duplicated
    2026-07-19 dQw4w9WgXcQ.jpg  # episode thumbnail (when downloaded)
```

Episode filenames are deliberately minimal — date for browsability, video ID for uniqueness.
Titles live in the feed, and simple names make simple, robust enclosure URLs.

- **Enablement**: the `MediaProfile.podcast_enabled` toggle. Every source using a publishing
  profile is served in place; there is no per-source toggle. Audio vs video follows the profile's
  `Preferred Resolution` — `Audio Only` makes an audio podcast, anything else keeps the video.
- **`Podcast URL Base` setting** (required): the public origin the static server serves the library
  at (e.g. `http://pods.local`). All feed links are built from it; until it's set, exports cancel
  (visible in the job diagnostics) and the source page shows a warning banner.
- **Naming**: each source gets a stable, unique, readable `slug` (from its name, suffixed on
  collision) that names its folder and feed URL. Slugs are kept across renames so subscriptions
  don't break. Enclosure/thumbnail URLs are each file's real library-relative path, URL-encoded.
  Sources created before slugs existed are backfilled by the `BackfillSourceSlugs` migration — a
  nil slug otherwise crashes the output-path template parser for **every** source's download, not
  just podcast ones.
- **Layout wins over overrides**: for a podcast source the slug-rooted template is used even when the
  source has an `output_path_template_override`, because the static server and generated feed URLs
  depend on that layout.
- **Only in-library media is served**: media that isn't under `PODCAST_PATH` (e.g. episodes
  downloaded before the source became a podcast) is excluded from the static feed until re-downloaded
  into the library — its enclosure URL wouldn't resolve on the static server otherwise.
- **No duplication**: `PodcastExport` only ever writes `feed.xml`, `cover`, and `opml.xml`. Media is
  owned by the download/retention system; it lives here because it downloaded here (via a
  slug-rooted output template and `podcast_directory` base). Turning `PODCAST_PATH` into a separate
  volume just means downloads land there directly — still no copies.
- **Profile form UX**: while `Publish as Podcast` is on, the media profile form swaps the output
  path template for a read-only preview of the effective download path
  (`<PODCAST_PATH>/{{ source_slug }}/…`), relabels `Preferred Resolution` to `Podcast Format`, and
  links to the Podcast RSS Feeds wiki page.
- **Freshness**: `PodcastExportWorker` runs debounced (~30 s) after downloads, deletions,
  retention/culling, and relevant source/profile/settings edits; `PodcastSweepWorker` reconciles
  everything daily at 04:00 as a safety net (regenerating feeds and pruning generated feeds whose
  slug is no longer published — never touching media or unrelated folders).

Minimal nginx example for hosting the library:

```nginx
server {
  listen 80;
  server_name pods.local;
  root /downloads/podcasts;

  autoindex off;
  add_header X-Content-Type-Options nosniff;
  location / {
    try_files $uri =404;
  }
}
```

## Reconcile

Tools → Reconcile (`/reconciliation`) trues up already-downloaded files after
path-affecting settings changes — output path templates, the podcast toggle, restricted
filenames, sidecar toggles — **without re-downloading media**.

Flow: always **Scan and Build Plan first** (a background job builds a persisted, paginated report
of planned moves/backfills/deletions), then an explicit **Apply This Plan** confirmation. Applying
pauses all job queues, waits for executing jobs to finish (like database compaction does), moves
files + updates the DB, then resumes the queues. Saving a Source, Media Profile, or global Setting
marks any staged (ready) plan **stale**, since those edits can change predicted paths — build a
fresh plan after changing settings.

Three modes:

- **Local only** — zero network. New paths are rendered by feeding each item's stored metadata
  blob back to yt-dlp (`--load-info-json`), so yt-dlp applies filename sanitization exactly as a
  real download would. Moves/renames everything and rebuilds NFO/info.json sidecars from stored
  metadata.
- **Online mode** — additionally backfills sidecars that were never downloaded (missing
  thumbnails/subtitles) with one light yt-dlp fetch per affected video.
- **Full sync** — everything Online mode does (the full set of move/backfill/delete rows), _plus_
  schedules a full media re-download for items whose on-disk format no longer matches the profile
  (an audio-only↔video switch, or a container change). A format-mismatched item gets both: its
  normal move relocates the existing file offline, and the later re-download replaces it with the
  correct format at that same path (cleaning up the stale file itself). Detection is purely from the
  file extension — no JSON parsing — because that reflects the real post-remux file and the
  clearly-decidable cases; resolution/embed/sponsorblock state can't be judged reliably offline, so
  those never trigger a re-download. A video profile with no explicit container implies `.mp4`, so
  files in other containers are flagged. Re-downloads run after the reconcile window closes (reusing
  the "Redownload Existing" path) and do use bandwidth.

No mode ever uses the YouTube Data API. Sidecar files whose profile toggle is now off are
**deleted** on apply (the report lists them and the confirmation warns). Collisions (two files
resolving to the same target, or an occupied target path) are reported and skipped; apply and
re-run to resolve move chains. Caveat: offline rendering uses metadata as of download time, so a
video whose title changed on YouTube renders under its old title — consistent with what's on disk.

## Misc

### Channels with shorts uploaded mulitple times a day

- <https://www.youtube.com/@lyndseydotw>

### yt-dlp known issues/faq

- <https://github.com/yt-dlp/yt-dlp/issues/3766>
