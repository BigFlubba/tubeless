# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

Pinchflat is a self-hosted Phoenix/Elixir web app that wraps `yt-dlp` to automatically download YouTube content (channels, playlists) on a schedule. It uses SQLite (via `ecto_sqlite3`), Oban for background jobs, and Phoenix LiveView for the UI. Deployed as a single Docker container with no external dependencies.

## Commands

```bash
# Initial setup
mix setup               # deps.get + DB create/migrate/seed + asset setup/build

# Development server (inside Docker or with deps installed)
iex -S mix phx.server  # starts on port 4008 in dev

# Tests
mix test                          # run all tests (creates/migrates DB automatically)
mix test test/path/to/file_test.exs          # single file
mix test test/path/to/file_test.exs:42       # single test by line number

# Full quality check (what CI runs)
mix check                         # formatter + compiler + sobelow + prettier + ex_unit

# Individual checks
mix credo                         # Elixir code style
mix sobelow --config              # security scan
yarn run lint:check               # Prettier (JS/CSS)
yarn run lint:fix                 # Prettier auto-fix

# Database
mix ecto.migrate                  # run migrations (also regenerates priv/repo/erd.png)
mix ecto.rollback                 # rollback one migration
mix ecto.reset                    # drop + recreate + migrate + seed

# Assets
mix assets.build                  # compile Tailwind + esbuild (dev)
mix assets.deploy                 # minified build + digest for production

# Versioning
mix version.bump                  # runs tooling/version_bump.sh
```

## Architecture

## Codebase

- Project layout is stored in @CODEBASE.md

### Core domain model

Two top-level entities drive everything:

- **`Source`** (`lib/pinchflat/sources/`) — a YouTube channel or playlist the user wants to track. Has a `MediaProfile` that defines download rules.
- **`MediaItem`** (`lib/pinchflat/media/`) — a single video/audio item belonging to a Source. Tracks download state, file paths, metadata.
- **`MediaProfile`** (`lib/pinchflat/profiles/`) — reusable settings for how to download (format, quality, naming, Shorts/livestream rules, SponsorBlock, etc.).

### Background job system

All async work is done through **Oban** jobs. There's a thin wrapper called **`Task`** (`lib/pinchflat/tasks/`) that links an `Oban.Job` to either a `Source` or `MediaItem`. Use `Tasks.create_job_with_task/2` when scheduling work — it handles deduplication and the task record atomically.

Key workers:

- `FastIndexingWorker` (`lib/pinchflat/fast_indexing/`) — polls YouTube RSS feeds to detect new videos quickly without hitting the API
- `MediaCollectionIndexingWorker` (`lib/pinchflat/slow_indexing/`) — full yt-dlp metadata fetch for a Source (slow indexing)
- `MediaDownloadWorker` (`lib/pinchflat/downloading/`) — downloads a single MediaItem via yt-dlp
- `MediaQualityUpgradeWorker` (`lib/pinchflat/downloading/`) — re-downloads media after a configured delay to get better quality
- `MediaRetentionWorker` (`lib/pinchflat/downloading/`) — deletes old media per retention settings
- `SourceMetadataStorageWorker` (`lib/pinchflat/metadata/`) — fetches and stores source-level metadata (images, NFO, etc.)
- `FileSyncingWorker` (`lib/pinchflat/media/`) — reconciles MediaItem records with files on disk
- `SourceDeletionWorker` (`lib/pinchflat/sources/`) — cascades deletion of a Source and all its media
- `MediaProfileDeletionWorker` (`lib/pinchflat/profiles/`) — cascades deletion of a MediaProfile
- `UpdateWorker` (`lib/pinchflat/yt_dlp/`) — keeps the yt-dlp executable up to date according to the configured update policy. The policy logic lives in `UpdateManager` (`lib/pinchflat/yt_dlp/update_manager.ex`): `stable`/`nightly` track a channel, `nightly_frozen`/`pinned` hold one version, and `nightly_until_stable` rides nightly then auto-reverts to stable once a stable release catches up (using `ReleaseLookup` against the GitHub API + `Utils.VersionUtils` for date-version comparison). The `stable` policy resolves the exact latest stable version via `ReleaseLookup` and targets `yt-dlp/yt-dlp@<version>` (not the `stable` channel) so yt-dlp will _downgrade_ when the installed binary is a newer nightly — a plain `--update` refuses to move backwards and would strand you on the nightly. If the GitHub lookup fails it falls back to the channel update. The one-shot jump on a settings change runs via `UpdateWorker.kickoff_apply/0` (`%{"apply_policy" => true}`), distinct from the recurring cron/boot run. The recurring run re-asserts the held version for `pinned` (`yt_dlp_pinned_version`), `nightly_frozen` (the captured `yt_dlp_nightly_baseline`, re-installed via the `nightly@<version>` target), and `nightly_until_stable` while it's still holding (re-installs the same `yt_dlp_nightly_baseline` nightly until stable actually catches up) rather than no-op'ing — yt-dlp lives on the container's ephemeral filesystem, so an image swap reverts it to the baked-in build and the policy must true it back up on boot. `CommandRunner.update/1` builds the actual yt-dlp target: an exact nightly pins via the `nightly@<version>` _channel alias_ (yt-dlp resolves `nightly` to the `yt-dlp/yt-dlp-nightly-builds` repo — naming a `yt-dlp/yt-dlp_nightly@<tag>` repo path fails), while stable/`pinned` versions pin via `yt-dlp/yt-dlp@<version>`. Note yt-dlp's exit codes here are counterintuitive: a no-URL update exits `0` for both a successful update and "already up to date", and exits `100` from its _error_ handler (bad/missing tag, network failure, unwritable binary) — so `update/1` treats only `0` as success. The policy is a DB setting (`yt_dlp_update_policy` / `yt_dlp_pinned_version`), edited in the Settings UI.

### yt-dlp integration

`lib/pinchflat/yt_dlp/` contains the yt-dlp abstraction. The executable path and runner module are injected via application config (`config :pinchflat, yt_dlp_runner: ...`), making it easy to mock in tests. In test, `config/test.exs` points both `yt_dlp_executable` and `apprise_executable` to scripts in `test/scripts/yt-dlp-mocks/`.

`UnavailableMedia` (`lib/pinchflat/yt_dlp/unavailable_media.ex`) classifies yt-dlp error output for media that can never be downloaded (members-only, private, removed). It's shared by the download path and the source-metadata/indexing path, and is kept distinct from the cookie-recoverable errors in `Downloading.MediaDownloader` so the cookie-retry path always runs first. When the `ignore_unavailable_media` setting is enabled, both paths treat these as permanently unavailable rather than failing/retrying.

### Other domain areas

- `lib/pinchflat/metadata/` — parses and persists yt-dlp metadata: source/media metadata, NFO files (for Jellyfin/Kodi), source images.
- `lib/pinchflat/podcasts/` — builds podcast RSS and OPML feeds so Sources can be consumed by podcast apps.
- `lib/pinchflat/lifecycle/` — side effects around media lifecycle: Apprise `notifications` and user-defined `user_scripts` run via command runners.
- `lib/pinchflat/http/` — small HTTP client behaviour (`http_behaviour.ex` / `http_client.ex`) for RSS fetches and similar, mockable in tests.
- `lib/pinchflat/diagnostics/` — `QueueDiagnostics` powers the Oban queue diagnostics page in the UI. Each queue card on the page can be expanded to list the jobs currently in that queue (capped at 50, via `get_jobs_for_queue/2`). Discarded jobs can be reset or permanently deleted (`delete_discarded_job/1`), and a "Details" column resolves each job's args to the Source/MediaItem/MediaProfile it targets (`describe_job/2`).

### Indexing: fast vs slow

Pinchflat uses two indexing strategies:

1. **Fast indexing** (`lib/pinchflat/fast_indexing/`) — parses YouTube's RSS feed to detect new video IDs cheaply and frequently, then schedules individual downloads.
2. **Slow indexing** (`lib/pinchflat/slow_indexing/`) — runs full yt-dlp collection fetches on a longer schedule to catch anything RSS misses and update metadata.

### Boot sequence

`lib/pinchflat/boot/` has three GenServers run at startup:

- `PreJobStartupTasks` — runs before Oban starts (DB cleanup, etc.)
- `PostJobStartupTasks` — runs after Oban starts (reschedules stalled jobs)
- `PostBootStartupTasks` — runs once everything is ready (triggers yt-dlp self-update)

All three use `restart: :temporary` so they run once and exit cleanly.

### Web layer

Standard Phoenix with LiveView. Routes are defined in `lib/pinchflat_web/router.ex`. The web layer is organized by resource under `lib/pinchflat_web/controllers/` (sources, media_items, media_profiles, settings, podcasts, searches, pages) with shared UI in `lib/pinchflat_web/components/`. LiveViews are colocated with their controllers as `*_live.ex` files (e.g. `sources/source_live/`, `settings/setting_html/cookie_file_live.ex`) rather than living in a separate `live/` directory. Notable routing details:

- Podcast RSS/OPML endpoints bypass basic auth intentionally (to work with podcast apps)
- `/healthcheck` bypasses auth and CSRF
- `strip_trailing_extension` plug in `endpoint.ex` allows media streaming URLs with extensions

### Configuration injection pattern

Executables and pluggable backends are stored in application config and read at runtime, not hardcoded. This means tests override them cleanly via `config/test.exs`. When adding new external tools or swappable backends, follow this pattern rather than calling executables directly.

## Commits and releases

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `fix:` → patch release
- `feat:` → minor release
- `chore:` / `docs:` / `perf:` / `revert:` / `style:` / `refactor:` / `test:` / `ci:` → no release bump

Only `fix:`, `feat:`, and a `!` / `BREAKING CHANGE:` (major) bump the version. Every type above is recognized by release-please (see the `changelog-sections` in `release-please-config.json`) and is sorted into the changelog accordingly — `test:` and `ci:` are hidden. Prefer `chore(deps):` for dependency bumps; the legacy `deps:` type is also mapped to the Chores section but is being phased out, so don't use it for new commits.

Prefer `chore(ci):` for CI/build-pipeline changes (rather than a bare `ci:`) so they surface in the Chores changelog section instead of being hidden.

Before staging and committing, always run these two checks in order:

1. `prettier . --check --config=.prettierrc.js --ignore-path=.prettierignore --ignore-path=.gitignore --write` — auto-fixes formatting so CI's prettier check doesn't fail.
2. `tooling/lint_test.sh` — reproduces `.github/workflows/ci.yml`'s `test` job (compiler, credo, sobelow, ExUnit, prettier check) inside the same pinned ci-base Docker image, so a green run here means a green CI `test` job. Requires Docker. Run this after prettier and before every commit.
3. If on master branch, create new branch for your commits.

Releases are automated via release-please using semantic versioning (current version tracked in `version.txt`, e.g. `1.2.0`). Merging the release PR cuts a release and publishes Docker images to GHCR and Docker Hub. (`mix version.bump` / `tooling/version_bump.sh` still produce a legacy date-based `YYYY.M.D` version and predate the move to release-please — prefer the release-please flow.)

Never push commits unless explicitly asked to do. I prefer commits amended if the work is related to a new feature or a new fix.

## Local Development Guide

- @DEVELOPMENT.md contains instructions for local dev practices

## Maintaining This Documentation

**IMPORTANT**: Keep CLAUDE.md, DEVELOPMENT.md and CODEBASE.md files up to date whenever making changes to the codebase:

- **New features**: Document new configuration options, CLI flags, endpoints, or capabilities
- **Behavior changes**: Update relevant sections when modifying how episodes are processed, stored, or cleaned up
- **New platform support**: Add platform-specific documentation under "Platform-Specific Behaviors"
- **API changes**: Update configuration examples and available options
- **Bug fixes that affect documented behavior**: Correct any documentation that no longer reflects reality
- **New limitations or removed limitations**: Update the "Limitations and Known Issues" section
