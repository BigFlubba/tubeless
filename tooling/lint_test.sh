#!/usr/bin/env bash
# Run the equivalent of .github/workflows/ci.yml's `test` job locally, before
# pushing. It executes the exact same steps inside the exact same pinned
# ci-base image CI uses, so a green run here means a green `test` job in CI.
#
# Why Docker: the repo has no committed SQLean extensions and assumes a Linux
# toolchain (yt-dlp/ffmpeg/Deno/Apprise + Elixir/OTP/Node) that the ci-base
# image bakes in. Running natively on macOS would drift from CI.
#
# Isolation: your host is likely macOS, so we must NOT let the Linux container
# compile into your host deps/_build (arch mismatch). Those dirs — plus the two
# node_modules — live in named Docker volumes, mirroring docker-compose.ci.yml.
# They persist between runs (fast incremental re-runs) and never touch your host
# tree. Pass --clean to wipe them and start fresh.
#
# Prereqs: Docker running, and a one-time `docker login ghcr.io` (the pinned
# ci-base image is private). Usage:
#   tooling/lint_test.sh            # full run (deps + sqlean + db + mix check)
#   tooling/lint_test.sh --clean    # drop cached volumes first, then full run
#   tooling/lint_test.sh --shell    # drop into a shell in the CI container
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# Single source of truth for the image: read the pinned SHA out of ci.yml so
# this can never drift from what CI runs. Matches the `CI_BASE_IMAGE:` env line.
# awk (not sed \s, which BSD/macOS sed lacks) so this parses portably.
CI_BASE_IMAGE="$(awk '/^[[:space:]]*CI_BASE_IMAGE:/ {print $2; exit}' .github/workflows/ci.yml)"
if [[ -z "${CI_BASE_IMAGE}" ]]; then
  echo "Could not parse CI_BASE_IMAGE from .github/workflows/ci.yml" >&2
  exit 1
fi

# Named volumes keep Linux-built artifacts off the host tree and cached across runs.
# deps/ is intentionally NOT among these — see the bind-mount note below.
VOL_PREFIX="pinchflat-lint_test"
VOLUMES=(_build node_modules assets_node_modules extensions)

if [[ "${1:-}" == "--clean" ]]; then
  echo "Removing cached volumes..."
  for v in "${VOLUMES[@]}"; do docker volume rm -f "${VOL_PREFIX}-${v}" >/dev/null 2>&1 || true; done
  shift
fi

# Bind-mount the source at /app (tests/fixtures hardcode /app; CI symlinks it
# there). Overlay named volumes on the build/dep dirs so the container writes
# Linux artifacts there instead of into your host checkout.
# deps/ is bind-mounted from the host (not a named volume): it's source-only and
# arch-independent, so sharing it is safe. Crucially it reuses deps the host has
# already fetched with your credentials — notably the private faker fork — so the
# container never has to auth to GitHub. This mirrors how CI's actions/cache
# restores deps/ so `mix deps.get` doesn't re-clone.
DOCKER_ARGS=(
  --rm
  -v "${REPO_ROOT}:/app"
  -v "${VOL_PREFIX}-_build:/app/_build"
  -v "${VOL_PREFIX}-node_modules:/app/node_modules"
  -v "${VOL_PREFIX}-assets_node_modules:/app/assets/node_modules"
  # SQLean extensions (regexp_like etc.) live in a named volume, NOT the host
  # tree: they're Linux-arch .so files fetched inside the container, and the host
  # bind-mount may carry a stale .sqlean-version marker (with the .so missing)
  # that makes fetch-sqlean.sh skip the download — which silently breaks every
  # regexp_like query. Isolating them guarantees a real, arch-correct fetch.
  -v "${VOL_PREFIX}-extensions:/app/priv/repo/extensions"
  -w /app
  -e MIX_ENV=test
)

if [[ "${1:-}" == "--shell" ]]; then
  echo "Starting shell in ${CI_BASE_IMAGE}..."
  exec docker run -it "${DOCKER_ARGS[@]}" "${CI_BASE_IMAGE}" bash
fi

echo "Pulling ${CI_BASE_IMAGE} (requires: docker login ghcr.io)..."
docker pull "${CI_BASE_IMAGE}"

# The steps below mirror ci.yml's `test` job 1:1.
exec docker run "${DOCKER_ARGS[@]}" "${CI_BASE_IMAGE}" bash -euo pipefail -c '
  echo "==> Installing Elixir and JS deps"
  mix local.hex --force >/dev/null
  mix local.rebar --force >/dev/null
  mix deps.get
  yarn install
  (cd assets && yarn install)

  echo "==> Fetching SQLean extensions"
  ./tooling/fetch-sqlean.sh

  echo "==> Creating and migrating database"
  mix ecto.create
  mix ecto.migrate

  echo "==> Running code checks (mix check)"
  mix check --no-fix --no-retry
'
