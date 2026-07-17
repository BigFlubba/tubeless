# Tubeless — Codebase & Tooling Overview

## Project Source Directories

| Directory               | Purpose                                                                                                |
| ----------------------- | ------------------------------------------------------------------------------------------------------ |
| `lib/pinchflat/`        | Core Elixir business logic — downloading, indexing, media, sources, yt-dlp integration, settings, etc. |
| `lib/pinchflat_web/`    | Phoenix web layer — controllers, LiveView components, helpers                                          |
| `test/`                 | Mirror of `lib/` with test files, plus fixtures, support helpers, and test scripts                     |
| `priv/repo/migrations/` | 84 Ecto database migration files (2024-01 through 2026-07)                                             |
| `priv/gettext/`         | i18n translation templates and English error strings                                                   |
| `priv/static/`          | Static web assets: favicon, Satoshi fonts (40 files), images, robots.txt                               |
| `priv/grafana/`         | 6 Grafana dashboard JSON definitions (BEAM, Ecto, Oban, Phoenix, LiveView, Application)                |
| `assets/js/`            | Frontend JS — Alpine.js app entry, helpers, tabs, topbar vendor lib                                    |
| `assets/css/`           | App CSS + Satoshi font CSS                                                                             |

---

## Technology Stack

### Language & Runtime

| Technology | Version  | Role                                                         |
| ---------- | -------- | ------------------------------------------------------------ |
| Elixir     | 1.20.2   | Primary application language                                 |
| Erlang/OTP | 28.5.0.3 | Runtime VM                                                   |
| Node.js    | 24.x     | Asset pipeline only (esbuild, Tailwind, Yarn) — not a server |

### Web Framework

| Technology           | Role                                                           |
| -------------------- | -------------------------------------------------------------- |
| Phoenix 1.7          | HTTP router, controllers, endpoint                             |
| Phoenix LiveView 1.0 | Real-time server-rendered UI — no custom WebSocket code needed |
| Plug/Cowboy          | HTTP server adapter                                            |

### Database

| Technology                  | Role                                                                                                  |
| --------------------------- | ----------------------------------------------------------------------------------------------------- |
| SQLite (via `ecto_sqlite3`) | Embedded database — no external DB process                                                            |
| Ecto 3.12                   | ORM and query layer                                                                                   |
| SQLean                      | SQLite extension library loaded at runtime per architecture (`sqlean-linux-x86` / `sqlean-linux-arm`) |

### Background Jobs

| Technology | Role                                                                                                  |
| ---------- | ----------------------------------------------------------------------------------------------------- |
| Oban 2.17  | Job queue backed by SQLite — handles all async work (indexing, downloading, retention, notifications) |

### External Tools (runtime dependencies)

| Technology       | Role                                                                |
| ---------------- | ------------------------------------------------------------------- |
| yt-dlp           | Core downloader — wraps YouTube and other platform downloads        |
| ffmpeg / ffprobe | Media processing and probing                                        |
| Deno             | Required by yt-dlp for certain YouTube downloads (see yt-dlp#14404) |
| Apprise          | Multi-platform notification dispatch                                |

Download quality preferences are translated into yt-dlp options by `lib/pinchflat/downloading/quality_option_builder.ex`. MediaProfiles can opt out of YouTube Super Resolution formats; the default-off preference adds `[format_note!*=?AI-upscaled]` to all format selector branches when enabled.

### Frontend

| Technology   | Role                                                                |
| ------------ | ------------------------------------------------------------------- |
| Alpine.js 3  | Lightweight client-side reactivity (tabs, dropdowns, etc.)          |
| Tailwind CSS | Utility-first CSS framework with dark mode and custom design tokens |
| esbuild      | JavaScript bundler                                                  |
| Heroicons    | Icon set (SVG, via Tailwind plugin)                                 |
| Simple Icons | Brand/logo icons (SVG, via Tailwind plugin)                         |
| Satoshi      | Custom typeface (self-hosted in `priv/static/`)                     |

### Observability

| Technology                                     | Role                                                                                         |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------- |
| PromEx                                         | Prometheus metrics exporter for the BEAM, Ecto, Oban, Phoenix, and LiveView                  |
| Telemetry / TelemetryMetrics / TelemetryPoller | Instrumentation and metric aggregation                                                       |
| Phoenix LiveDashboard                          | Built-in runtime dashboard (process info, memory, etc.)                                      |
| Grafana                                        | 6 pre-built dashboards in `priv/grafana/` (BEAM, Ecto, Oban, Phoenix, LiveView, Application) |

### Elixir Libraries (notable)

| Library      | Role                                                     |
| ------------ | -------------------------------------------------------- |
| NimbleParsec | Parser combinators — used to parse yt-dlp output formats |
| Timex        | Date/time utilities                                      |
| Jason        | JSON encoding/decoding                                   |
| Gettext      | i18n — English error strings in `priv/gettext/`          |
| Finch        | HTTP client (used by Swoosh and internal HTTP calls)     |
| Swoosh       | Email library (wired up but not a primary feature)       |

### Code Quality & Testing

| Technology           | Used in   | Role                                                           |
| -------------------- | --------- | -------------------------------------------------------------- |
| Credo + credo_naming | dev/test  | Elixir static analysis and naming conventions                  |
| Sobelow              | dev/test  | Security vulnerability scanner                                 |
| ex_check             | dev/test  | Unified check runner (`mix check`) — orchestrates all tools    |
| Mox                  | test      | Mock library for behaviour-based test doubles                  |
| LazyHTML             | test      | HTML parser for controller/LiveView test assertions            |
| Faker                | test      | Fake data generation in test fixtures                          |
| Prettier             | dev/CI    | Formatter for JS, CSS, JSON, YAML, Markdown                    |
| sqleton              | local dev | ERD generation from the live SQLite DB (`yarn run create-erd`) |

### CI/CD & Tooling

| Technology              | Role                                                                             |
| ----------------------- | -------------------------------------------------------------------------------- |
| GitHub Actions          | CI/CD platform — PR checks, releases, Docker image builds                        |
| Docker / Docker Compose | Containerization for both dev and production                                     |
| Docker Buildx + QEMU    | Multi-architecture builds (`linux/amd64` + `linux/arm64`)                        |
| GHCR                    | GitHub Container Registry — hosts PR, RC, and CI base images                     |
| Docker Hub              | Public release image hosting (`communitymaintained/pinchflat`)                   |
| release-please          | Automated semantic versioning and changelog generation from Conventional Commits |
| Renovate                | Automated dependency update PRs                                                  |

---

## Build & Asset Pipeline

Used in both local dev and CI/CD.

| File                        | Used in    | Purpose                                                                                                                         |
| --------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `mix.exs`                   | both       | Elixir project definition — deps, Mix aliases (`setup`, `test`, `assets.build`, `assets.deploy`, `check`, `version.bump`, etc.) |
| `mix.lock`                  | both       | Locked Elixir dependency versions                                                                                               |
| `assets/tailwind.config.js` | both       | Tailwind config — dark mode, custom font/color/spacing tokens, Heroicons + Simple Icons SVG plugins, Phoenix/LiveView variants  |
| `assets/package.json`       | both       | Frontend JS deps (Alpine.js)                                                                                                    |
| `assets/yarn.lock`          | both       | Locked frontend JS deps                                                                                                         |
| `package.json`              | local only | Root JS tooling — Prettier, sqleton (ERD generation via `yarn run create-erd`)                                                  |
| `yarn.lock`                 | local only | Locked root tooling deps                                                                                                        |

esbuild and Tailwind are driven through Mix aliases defined in `mix.exs`, not standalone config files.

---

## Docker

| File                              | Used in    | Purpose                                                                                                                                                                                                               |
| --------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docker/ci-base.Dockerfile`       | CI/release | Shared base image (`ghcr.io/communitymaintained/pinchflat-ci-base`) — provides Elixir, OTP, Node, FFmpeg, yt-dlp, Deno, Apprise. Both dev and selfhosted images build FROM it so toolchain versions live in one place |
| `docker/ci-base.requirements.txt` | CI/release | Pinned pip requirements (e.g. Apprise) installed into the ci-base image, managed by Renovate                                                                                                                          |
| `docker/dev.Dockerfile`           | local only | Dev image — builds FROM `pinchflat-ci-base`, then installs dev extras (oh-my-zsh, dev deps)                                                                                                                           |
| `docker/selfhosted.Dockerfile`    | CI/release | Production multi-stage build — builder stage runs on `pinchflat-ci-base` and compiles the OTP release; minimal runtime image with only production deps (ffmpeg/yt-dlp copied from the builder)                        |
| `docker/docker-run.dev.sh`        | local only | Dev container startup script — installs deps, migrates DB, starts IEX Phoenix server                                                                                                                                  |
| `docker-compose.yml`              | local only | Local dev environment (builds `dev.Dockerfile`, mounts working dir, exposes port 4008)                                                                                                                                |

---

## Release & Versioning

| File                                      | Used in    | Purpose                                                                                                                                 |
| ----------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `version.txt`                             | CI/release | Single source of truth for current version, semver (read by CI for Docker image tags)                                                   |
| `release-please-config.json`              | CI/release | Release-Please config — "simple" release type managing root package                                                                     |
| `.release-please-manifest.json`           | CI/release | Release-Please version tracking manifest                                                                                                |
| `CHANGELOG.md`                            | CI/release | Auto-generated release notes                                                                                                            |
| `tooling/version_bump.sh`                 | local only | Legacy bash script to bump version (YYYY.M.D date format) in `mix.exs` — predates release-please semver; prefer the release-please flow |
| `rel/overlays/bin/docker_start`           | CI/release | OTP release entrypoint — runs `check_file_permissions`, sets umask, runs `migrate`, starts server                                       |
| `rel/overlays/bin/migrate`                | CI/release | Runs `Pinchflat.Release.migrate` in OTP release context                                                                                 |
| `rel/overlays/bin/check_file_permissions` | CI/release | Runs `Pinchflat.Release.check_file_permissions` in OTP release context                                                                  |

---

## CI/CD (`.github/workflows/`)

Both files are CI/release only — they are never run locally.

| File                 | Purpose                                                                                                                                |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `ci.yml`             | PR pipeline — linting, Docker build/cache, pushes PR/RC image to GHCR                                                                  |
| `release-please.yml` | Release pipeline — runs tests, invokes Release-Please, bumps versions, builds and pushes multi-arch Docker images to Docker Hub + GHCR |

---

## Code Quality & Linting

All linting config files are used in both local dev and CI (CI runs `mix check` which invokes them all).

| File                 | Used in | Purpose                                                                                                           |
| -------------------- | ------- | ----------------------------------------------------------------------------------------------------------------- |
| `.formatter.exs`     | both    | Elixir formatter config (120-char line length, LiveView HTML formatter)                                           |
| `tooling/.credo.exs` | both    | Credo static analysis config                                                                                      |
| `tooling/.check.exs` | both    | `ex_check` runner config — orchestrates compiler, formatter, Sobelow, Prettier, ExUnit (warnings-as-errors in CI) |
| `.sobelow-conf`      | both    | Sobelow security scanner config (suppresses single-user/self-hosted warnings)                                     |
| `.prettierrc.js`     | both    | Prettier config (100-char width, single quotes, LF line endings, trailing comma off)                              |
| `.prettierignore`    | both    | Prettier ignore patterns                                                                                          |

Run everything with `mix check`. Individual tools: `mix credo`, `mix sobelow`, `yarn run lint:check`.

---

## Dev Experience

| File                              | Used in    | Purpose                                                                                                                               |
| --------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `.iex.exs`                        | local only | IEx shell startup — imports common aliases for interactive development                                                                |
| `.devcontainer/devcontainer.json` | local only | VS Code Dev Container config — uses `docker-compose.yml`, recommends ElixirLS + Prettier extensions                                   |
| `config/config.exs`               | both       | Base app config (Repo, Endpoint, Oban, Gettext, Telemetry)                                                                            |
| `config/dev.exs`                  | local only | Dev env config — local tmp dirs, SQLite at `priv/repo/pinchflat_dev.db`, port 4008, esbuild/Tailwind file watchers                    |
| `config/test.exs`                 | both       | Test env config — mocked yt-dlp/apprise executables, SQLite at `priv/repo/pinchflat_test.db`, Oban in manual mode                     |
| `config/prod.exs`                 | CI/release | Production config (asset digest manifest, Swoosh via Finch, info-level logging)                                                       |
| `config/runtime.exs`              | CI/release | Runtime config — reads env vars (PHX_SERVER, auth, YT_DLP_WORKER_CONCURRENCY), loads SQLean extensions per arch, configures Oban cron |

---

## Test Infrastructure

All test infrastructure is used in both local dev and CI.

| File/Dir                     | Purpose                                                                                                        |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `test/support/`              | `conn_case.ex`, `data_case.ex`, `testing_helper_methods.ex` — Phoenix + Ecto test helpers                      |
| `test/support/fixtures/`     | Factory modules for jobs, media, profiles, sources, tasks                                                      |
| `test/files/`                | Static test data — channel/media photos, metadata JSON, info.json, test video (media.mkv), subtitle, thumbnail |
| `test/scripts/yt-dlp-mocks/` | Mock executables — `repeater.sh` (echo mock for yt-dlp/apprise), `101_exit_code.sh` (error code mock)          |

---

## Misc

| File/Dir                                 | Used in    | Purpose                                                                                                                                                               |
| ---------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `priv/repo/extensions/sqlean-linux-arm/` | CI/release | SQLean SQLite extensions (ARM64) — fetched by `tooling/fetch-sqlean.sh`, not committed (gitignored)                                                                   |
| `priv/repo/extensions/sqlean-linux-x86/` | CI/release | SQLean SQLite extensions (x86-64) — fetched by `tooling/fetch-sqlean.sh`, not committed (gitignored)                                                                  |
| `tooling/fetch-sqlean.sh`                | both       | Downloads the pinned SQLean release (`SQLEAN_VERSION`, Renovate-tracked) into `priv/repo/extensions/`; run by `mix setup` and the Docker builder before `mix release` |
| `priv/repo/seeds.exs`                    | local only | Database seed script                                                                                                                                                  |
| `priv/repo/erd.png`                      | local only | Entity-Relationship Diagram (generated via `yarn run create-erd`)                                                                                                     |
| `priv/cmd_wrapper.sh`                    | CI/release | Shell wrapper used around external commands (yt-dlp, apprise) at runtime                                                                                              |
| `.dockerignore`                          | CI/release | Docker build ignore list                                                                                                                                              |
| `.gitignore`                             | local only | Git ignore list                                                                                                                                                       |
| `CONTRIBUTING.md`                        | —          | Contribution guidelines                                                                                                                                               |
| `LICENSE`                                | —          | Project license                                                                                                                                                       |
| `.github/ISSUE_TEMPLATE/`                | —          | Bug report, feature request, and other issue templates                                                                                                                |
| `.github/pull_request_template.md`       | —          | PR description template with license acknowledgment                                                                                                                   |
