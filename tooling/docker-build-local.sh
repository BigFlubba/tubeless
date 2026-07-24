#!/usr/bin/env bash
# Build the production selfhosted image locally, exactly like ci.yml's
# docker-pr job does — same Dockerfile, same pinned CI_BASE_IMAGE build-arg —
# but entirely on your machine: nothing is pushed anywhere, so a staged/local
# commit never needs to go through GitHub to get built and smoke-tested.
#
# This is NOT the same as tooling/lint_test.sh: that mirrors ci.yml's `test`
# job (mix check inside ci-base). This mirrors `docker-pr`: an actual
# `docker build` of docker/selfhosted.Dockerfile, producing the real release
# image you'd otherwise only see after pushing a PR.
#
# Usage:
#   tooling/docker-build-local.sh                # build only, tag tubeless:local
#   tooling/docker-build-local.sh --run           # build, then run it in the foreground
#   tooling/docker-build-local.sh --shell         # build, run it detached, then attach a shell
#   tooling/docker-build-local.sh --no-cache      # ignore Docker layer cache
#   tooling/docker-build-local.sh --tag foo:bar   # build under a different tag
#
# Both --run and --shell start the image with a local
# ./tmp/docker-local/{config,downloads,podcasts} bind mount (so state survives
# between runs) and publish the container's PORT (8945 by default) to the same
# port on localhost.
#
# --run and --shell both start the app detached under a fixed container name
# (tubeless-local): --run then follows its logs (Ctrl-C to exit), --shell waits
# for it to become healthy and `docker exec`s a bash shell into it instead — so
# you get a live shell alongside the running app. Either way, the container is
# stopped and removed automatically once you exit.
#
# Prereqs: Docker running + a one-time `docker login ghcr.io` (the pinned
# ci-base image the Dockerfile builds FROM is private).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# Single source of truth for the base image: parse it out of ci.yml so this can
# never drift from what CI's docker-pr job builds against.
CI_BASE_IMAGE="$(awk '/^[[:space:]]*CI_BASE_IMAGE:/ {print $2; exit}' .github/workflows/ci.yml)"
if [[ -z "${CI_BASE_IMAGE}" ]]; then
  echo "Could not parse CI_BASE_IMAGE from .github/workflows/ci.yml" >&2
  exit 1
fi

TAG="tubeless:local"
NO_CACHE=()
RUN_AFTER=0
SHELL_AFTER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run) RUN_AFTER=1; shift ;;
    --shell) RUN_AFTER=1; SHELL_AFTER=1; shift ;;
    --no-cache) NO_CACHE=(--no-cache); shift ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

echo "Pulling ${CI_BASE_IMAGE} (requires: docker login ghcr.io)..."
docker pull "${CI_BASE_IMAGE}" >/dev/null

echo "==> Building ${TAG} from docker/selfhosted.Dockerfile"
docker build \
  ${NO_CACHE[@]+"${NO_CACHE[@]}"} \
  -f docker/selfhosted.Dockerfile \
  --build-arg "CI_BASE_IMAGE=${CI_BASE_IMAGE}" \
  -t "${TAG}" \
  .

if [[ "${RUN_AFTER}" -ne 1 ]]; then
  echo "Built ${TAG}. Re-run with --run to start it."
  exit 0
fi

# Local, persistent state dirs so config/downloads/podcasts survive between
# --run invocations instead of vanishing with the container. Podcasts get their
# own volume (PODCAST_PATH) rather than relying on the <downloads>/podcasts
# default, so the static podcast export path can be poked at directly.
STATE_DIR="${REPO_ROOT}/tmp/docker-local"
mkdir -p "${STATE_DIR}/config" "${STATE_DIR}/downloads" "${STATE_DIR}/podcasts"

PORT="${PORT:-8945}"
CONTAINER_NAME="tubeless-local"

DOCKER_RUN_ARGS=(
  -p "${PORT}:${PORT}"
  -v "${STATE_DIR}/config:/config"
  -v "${STATE_DIR}/downloads:/downloads"
  -v "${STATE_DIR}/podcasts:/podcasts"
  -e "PORT=${PORT}"
  -e "PODCAST_PATH=/podcasts"
)

# Run the app detached under a stable name (so a stray leftover from a prior
# run doesn't collide), and always tear it down on exit — whether that's
# Ctrl-C out of --run's log follow or exiting --shell's shell.
docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
trap 'echo "==> Stopping and removing ${CONTAINER_NAME}..."; docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true' EXIT

echo "==> Starting ${TAG} detached as ${CONTAINER_NAME} on http://localhost:${PORT} (state in ${STATE_DIR})"
docker run -d --name "${CONTAINER_NAME}" "${DOCKER_RUN_ARGS[@]}" "${TAG}" >/dev/null

if [[ "${SHELL_AFTER}" -ne 1 ]]; then
  echo "==> Following ${CONTAINER_NAME} logs — Ctrl-C to exit and tear down the container"
  docker logs -f "${CONTAINER_NAME}" || true
  exit 0
fi

echo "==> Waiting for the app to become healthy..."
for _ in $(seq 1 60); do
  status="$(docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "unknown")"
  if [[ "${status}" == "healthy" ]]; then
    break
  fi
  if [[ "$(docker inspect --format='{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null)" != "true" ]]; then
    echo "Container exited before becoming healthy. Logs:" >&2
    docker logs "${CONTAINER_NAME}" >&2 || true
    exit 1
  fi
  sleep 1
done

echo "==> Attaching shell to ${CONTAINER_NAME} (container is torn down when you exit)"
docker exec -it "${CONTAINER_NAME}" bash || true
