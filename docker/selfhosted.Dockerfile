# Builder stage runs on the shared ci-base image — it already provides Elixir, OTP,
# build-essential, git, curl, node+yarn, hex, rebar, and the pinned ffmpeg binary.
# Runner stage stays on debian:trixie-slim to keep the production image small.
ARG DEBIAN_VERSION=trixie-20260610-slim
ARG CI_BASE_IMAGE="ghcr.io/communitymaintained/tubeless-ci-base:latest"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${CI_BASE_IMAGE} AS builder

ARG TARGETPLATFORM
RUN echo "Building for ${TARGETPLATFORM:?}"

# prepare build dir
WORKDIR /app

# set build ENV
ENV MIX_ENV="prod"
ENV ERL_FLAGS="+JPperf true"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV && mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

# Fetch the SQLean SQLite extensions into priv/ (pinned version, not in git) so
# `mix release` bundles them into the OTP release. ci-base provides curl + unzip.
COPY tooling/fetch-sqlean.sh tooling/fetch-sqlean.sh
RUN ./tooling/fetch-sqlean.sh

# Compile assets
RUN yarn --cwd assets install && mix assets.deploy && mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

## -- Release Stage --

FROM ${RUNNER_IMAGE}

ARG TARGETPLATFORM
ARG PORT=8945
# Deno is pinned to match ci-base so dev/CI and production run the same version.
# Keep this in sync with DENO_VERSION in docker/ci-base.Dockerfile.
# renovate: datasource=github-releases depName=denoland/deno
ARG DENO_VERSION=v2.9.0

# ffmpeg comes from ci-base (pinned there, see issue #347). Bumping it requires
# rebuilding ci-base and bumping the consumer pin — drift is intentional.
COPY --from=builder /usr/bin/ffmpeg /usr/bin/ffmpeg
COPY --from=builder /usr/bin/ffprobe /usr/bin/ffprobe

# Apprise is pinned via the shared requirements file so dev/CI and production
# install the same version (single source of truth with ci-base).
COPY docker/ci-base.requirements.txt /tmp/ci-base.requirements.txt

RUN apt-get update -y && \
    # System packages
    apt-get install -y \
      libstdc++6 \
      openssl \
      libncurses6 \
      locales \
      ca-certificates \
      python3-mutagen \
      curl \
      zip \
      openssh-client \
      nano \
      python3 \
      pipx \
      jq \
      # unzip is needed for Deno
      unzip \
      sqlite3 \
      procps && \
    # Install Deno - required for YouTube downloads (See yt-dlp#14404). Pinned to
    # match ci-base via DENO_VERSION above.
    curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s -- ${DENO_VERSION} -y --no-modify-path && \
    # Apprise (version pinned in docker/ci-base.requirements.txt, managed by Renovate)
    export PIPX_HOME=/opt/pipx && \
    export PIPX_BIN_DIR=/usr/local/bin && \
    pipx install "$(cat /tmp/ci-base.requirements.txt)" && \
    rm /tmp/ci-base.requirements.txt && \
    # yt-dlp
    export YT_DLP_DOWNLOAD=$(case ${TARGETPLATFORM:-linux/amd64} in \
    "linux/amd64")   echo "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"   ;; \
    "linux/arm64")   echo "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_aarch64" ;; \
    *)               echo "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"        ;; esac) && \
    curl -L ${YT_DLP_DOWNLOAD} -o /usr/local/bin/yt-dlp && \
    chmod a+rx /usr/local/bin/yt-dlp && \
    yt-dlp -U && \
    # Set the locale
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen && \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# More locale setup
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"

# Set up data volumes
RUN mkdir -p /config /downloads /etc/elixir_tzdata_data /etc/yt-dlp/plugins && \
  chmod ugo+rw /etc/elixir_tzdata_data /etc/yt-dlp /etc/yt-dlp/plugins /usr/local/bin /usr/local/bin/yt-dlp

# set runner ENV
ENV MIX_ENV="prod"
ENV PORT=${PORT}
ENV RUN_CONTEXT="selfhosted"
ENV UMASK=022
EXPOSE ${PORT}

# Only copy the final release from the build stage
COPY --from=builder /app/_build/${MIX_ENV}/rel/tubeless ./

HEALTHCHECK --interval=30s --start-period=15s \
  CMD curl --fail http://localhost:${PORT}/healthcheck || exit 1

# Start the app
CMD ["/app/bin/docker_start"]
