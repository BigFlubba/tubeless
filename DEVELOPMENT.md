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

**Cross-cutting options** (added by `CommandRunner`, not the callers):

- **Cookies** — `--cookies <extras>/cookies.txt` is added only when the caller passes `use_cookies: true` _and_ a non-empty cookies file exists. Callers decide via `Sources.use_cookies?(source, :metadata | :indexing)`.
- **Rate limiting** — `--limit-rate` from the `throughput_limit` setting, plus jittered `--sleep-requests`/`--sleep-interval`/`--sleep-subtitles` (unless the caller passes `skip_sleep_interval: true`). Jitter is applied per-run via `NumberUtils.add_jitter`.
- **Misc** — `--restrict-filenames` when that setting is enabled.

**Slow indexing command** — built in `SlowIndexingHelpers` and run via `MediaCollection.get_media_attributes_for_collection/3`. Base flags:

```
--simulate --skip-download --ignore-no-formats-error --no-warnings
```

`--ignore-no-formats-error` keeps premiere/upcoming videos from aborting the crawl; `--no-warnings` keeps the JSON output clean. For scheduled channel re-indexing it also adds `--break-on-existing --download-archive <tmpfile>`, where the archive is a `youtube <media_id>` list of recent-but-not-newest items (skip the 20 newest, take the next 30) so yt-dlp halts once it reaches known media. The indexing output template captures the fields needed to build a `MediaItem`:

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

| Setting                                         | Default | Description                                                                                        |
| ----------------------------------------------- | ------- | -------------------------------------------------------------------------------------------------- |
| `fast_index`                                    | `false` | Enable fast indexing (RSS/API polling every 10 min)                                                |
| `index_frequency_minutes`                       | `1440`  | Slow indexing interval; `0` = index once and stop; forced to 43,200 (30 d) when `fast_index: true` |
| `download_media`                                | `true`  | Whether indexed items are added to the download queue                                              |
| `download_cutoff_date`                          | —       | Skip media uploaded before this date                                                               |
| `title_filter_regex`                            | —       | Only download media whose title matches this pattern                                               |
| `min_duration_seconds` / `max_duration_seconds` | —       | Filter by duration                                                                                 |
| `enabled`                                       | `true`  | When false, indexing tasks are deleted and no downloads run                                        |

### Global Indexing Settings

| Setting                            | Description                                                                                                                       |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `youtube_api_key`                  | Comma-separated YouTube Data API v3 keys; fast indexing uses these in round-robin. Without this, fast indexing falls back to RSS. |
| `extractor_sleep_interval_seconds` | Delay between yt-dlp requests (rate limiting, default 0)                                                                          |
| `ignore_unavailable_media`         | Mark members-only/private/removed videos as permanently unavailable instead of retrying                                           |

## Misc

### Channels with shorts uploaded mulitple times a day

- <https://www.youtube.com/@lyndseydotw>

### yt-dlp known issues/faq

- <https://github.com/yt-dlp/yt-dlp/issues/3766>
