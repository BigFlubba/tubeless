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
docker build -f docker/selfhosted.Dockerfile -t pinchflat:local .

# Self-contained (no external base image dependency)
docker build -f selfhosted.og.Dockerfile -t pinchflat:local .
```

## Utility: List Published GHCR Images

Requires `gh` CLI auth.

```bash
bash tooling/list-images.sh                         # CommunityMaintained/pinchflat
bash tooling/list-images.sh MyOrg my-image-name    # custom org/image
```

## Misc

### Channels with shorts uploaded mulitple times a day

- <https://www.youtube.com/@lyndseydotw>

### yt-dlp known issues/faq

- <https://github.com/yt-dlp/yt-dlp/issues/3766>
