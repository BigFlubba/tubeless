#!/usr/bin/env bash
# Downloads the SQLean SQLite extensions into priv/repo/extensions/ for both
# Linux architectures. These are loaded at runtime by config/runtime.exs (see
# the `load_extensions` config) and back the per-source title filter regex
# (regexp_like). They are NOT committed to git — this script fetches them for
# local dev/test (via `mix setup`) and for the Docker builder stage (before
# `mix release` bundles priv/ into the OTP release).
#
# Version is pinned and tracked by Renovate.
set -euo pipefail

# renovate: datasource=github-releases depName=nalgeon/sqlean
SQLEAN_VERSION="0.22.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="${SCRIPT_DIR}/../priv/repo/extensions"
BASE_URL="https://github.com/nalgeon/sqlean/releases/download/${SQLEAN_VERSION}"

# Pairs of "<target dir>:<release asset>". The target dir name matches
# `sqlean-linux-#{arch}` in config/runtime.exs. (Avoid associative arrays so
# this runs on macOS's default bash 3.2.)
ARCHES="sqlean-linux-x86:sqlean-linux-x86.zip sqlean-linux-arm:sqlean-linux-arm64.zip"

# Skip the download when the pinned version is already present (idempotent —
# safe to call from `mix setup` repeatedly). Pass --force to re-fetch.
#
# "Present" means both the version marker AND the actual `sqlean.so` binary
# exist. The marker alone is not enough: it lives inside a gitignored dir, so a
# `docker COPY priv priv` (or a git clean that leaves the marker behind) can
# carry a stale marker into a build with no `.so` files next to it. Trusting the
# marker by itself made the fetch skip, shipping an image whose extension never
# loads — every SQLean function (gen_random_uuid, regexp_like, …) then silently
# goes missing and migrations that use them crash.
FORCE="${1:-}"
VERSION_MARKER=".sqlean-version"

for entry in ${ARCHES}; do
  dir="${entry%%:*}"
  asset="${entry##*:}"
  target="${EXT_DIR}/${dir}"
  if [[ "${FORCE}" != "--force" && -f "${target}/${VERSION_MARKER}" && -f "${target}/sqlean.so" ]] &&
    [[ "$(cat "${target}/${VERSION_MARKER}")" == "${SQLEAN_VERSION}" ]]; then
    echo "sqlean ${SQLEAN_VERSION} already present in ${dir}, skipping"
    continue
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  echo "Fetching sqlean ${SQLEAN_VERSION} (${asset}) -> ${dir}"
  curl -fsSL "${BASE_URL}/${asset}" -o "${tmp}/sqlean.zip"

  rm -rf "${target}"
  mkdir -p "${target}"
  unzip -qo "${tmp}/sqlean.zip" -d "${target}"
  echo "${SQLEAN_VERSION}" >"${target}/${VERSION_MARKER}"

  rm -rf "${tmp}"
  trap - EXIT
done

echo "sqlean ${SQLEAN_VERSION} ready"
