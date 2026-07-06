#!/usr/bin/env bash
# Fast inner-loop test runner. Runs `mix test` inside the exact same pinned
# ci-base image as tooling/lint_test.sh, reusing the SAME named volumes — so a
# warm _build means incremental (not from-scratch) compiles between runs.
#
# Why this exists alongside lint_test.sh: lint_test.sh is the pre-commit GATE —
# it runs the whole `mix check` (compiler + credo + sobelow + prettier + the
# full ExUnit suite) and is slow. This script is the ITERATION loop: recompile
# what changed and run just the tests you point it at. Use this while editing;
# run lint_test.sh once before committing.
#
# Native `mix test` on macOS is not an option: the suite needs the Linux SQLean
# .so extensions (regexp_like) plus the yt-dlp/ffmpeg/Deno/Apprise toolchain the
# ci-base image bakes in.
#
# Everything after the flags is passed straight through to `mix test`:
#   tooling/test.sh                                 # whole suite
#   tooling/test.sh test/pinchflat/foo_test.exs     # one file
#   tooling/test.sh test/pinchflat/foo_test.exs:42  # one test by line number
#   tooling/test.sh --failed                        # re-run last run's failures
#   tooling/test.sh --stale                         # only tests affected by edits
# Leading flags handled here (must come first):
#   --clean   wipe the cached volumes first, then run
#   --shell   drop into a shell in the container instead (same as lint_test.sh --shell)
#
# Prereqs: Docker running + a one-time `docker login ghcr.io` (image is private).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# Single source of truth for the image: read the pinned SHA out of ci.yml so this
# can never drift from CI. Matches lint_test.sh exactly (same image, same parse).
CI_BASE_IMAGE="$(awk '/^[[:space:]]*CI_BASE_IMAGE:/ {print $2; exit}' .github/workflows/ci.yml)"
if [[ -z "${CI_BASE_IMAGE}" ]]; then
  echo "Could not parse CI_BASE_IMAGE from .github/workflows/ci.yml" >&2
  exit 1
fi

# Reuse lint_test.sh's volume prefix so _build/extensions are SHARED between the
# two scripts — running either keeps the other's compile cache warm.
VOL_PREFIX="pinchflat-lint_test"
VOLUMES=(_build node_modules assets_node_modules extensions)

if [[ "${1:-}" == "--clean" ]]; then
  echo "Removing cached volumes..."
  for v in "${VOLUMES[@]}"; do docker volume rm -f "${VOL_PREFIX}-${v}" >/dev/null 2>&1 || true; done
  shift
fi

# Identical mount layout to lint_test.sh: source bind-mounted at /app (fixtures
# hardcode that path), Linux build artifacts kept off the host tree in named
# volumes, deps/ bind-mounted (source-only, arch-independent, reuses host creds).
DOCKER_ARGS=(
  --rm
  -v "${REPO_ROOT}:/app"
  -v "${VOL_PREFIX}-_build:/app/_build"
  -v "${VOL_PREFIX}-node_modules:/app/node_modules"
  -v "${VOL_PREFIX}-assets_node_modules:/app/assets/node_modules"
  -v "${VOL_PREFIX}-extensions:/app/priv/repo/extensions"
  -w /app
  -e MIX_ENV=test
)

if [[ "${1:-}" == "--shell" ]]; then
  echo "Starting shell in ${CI_BASE_IMAGE}..."
  exec docker run -it "${DOCKER_ARGS[@]}" "${CI_BASE_IMAGE}" bash
fi

echo "Pulling ${CI_BASE_IMAGE} (requires: docker login ghcr.io)..."
docker pull "${CI_BASE_IMAGE}" >/dev/null

# Pass the mix-test args through to the container as positional args ($@ after --).
# Unlike lint_test.sh this deliberately skips `yarn install` (ExUnit needs no
# assets) and every non-test check. deps.get and fetch-sqlean are cheap no-ops
# when the volumes are warm; the `mix test` alias itself does ecto.create/migrate.
exec docker run "${DOCKER_ARGS[@]}" "${CI_BASE_IMAGE}" bash -euo pipefail -c '
  mix local.hex --force >/dev/null
  mix local.rebar --force >/dev/null
  mix deps.get >/dev/null
  ./tooling/fetch-sqlean.sh >/dev/null
  echo "==> mix test $*"
  mix test "$@"
' -- "$@"
