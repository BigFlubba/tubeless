# This image is the shared toolchain used by:
#   - docker/dev.Dockerfile           (local dev + CI test runner)
#   - docker/selfhosted.Dockerfile    (release builder stage; ffmpeg is COPYd into the runner)
#
# Pinning:
#   - ffmpeg:  pinned URL below. selfhosted's runner copies this binary, so the version
#              here is what production ships. See issue #347 (newer ffmpeg builds trigger
#              "illegal instruction" on some users' hardware).
#   - deno:    pinned via install.sh version arg below. Renovate manages via the comment.
#   - apprise: pinned in docker/ci-base.requirements.txt so Renovate's pip_requirements
#              manager can bump it.
#   - yt-dlp:  intentionally floats to latest at base build time. selfhosted's runner
#              re-installs yt-dlp fresh on every release build, and runtime self-updates
#              via PostBootStartupTasks, so the version here doesn't reach production.
#   - oh-my-zsh: floats to master. Affects dev shell ergonomics only; low stakes.
#
# Drift caveat: ci-base ships ffmpeg into selfhosted's runner, so bumping the ffmpeg
# pin here changes the ffmpeg binary users get. Consumers should pin to :sha-<...>, not
# :latest, so any base bump goes through a PR.
# These three combine into the hexpm/elixir tag (see DEV_IMAGE below). hexpm only
# publishes specific combos, so Renovate tracks each against the real hexpm/elixir
# tag list (customManagers in renovate.json) and groups the bumps into one PR — it
# never proposes a value from a combo that isn't published. Debian stays on trixie-slim.
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=28.5.0.3
ARG DEBIAN_VERSION=trixie-20260623-slim
# renovate: datasource=github-releases depName=denoland/deno
ARG DENO_VERSION=v2.9.0
# renovate: datasource=node-version depName=node
ARG NODE_MAJOR=24
# NOT renovate-tracked: ffmpeg is pinned for issue #347 (illegal instruction on some CPUs).
# Newer builds must be smoke-tested manually before bumping. FFMPEG_BUILD is paired with
# FFMPEG_RELEASE — both come from the same yt-dlp/FFmpeg-Builds release page.
ARG FFMPEG_RELEASE=autobuild-2026-07-01-16-32
ARG FFMPEG_BUILD=N-125385-ge2e889d9da

ARG DEV_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"

FROM ${DEV_IMAGE}

# Re-declare ARGs needed inside the build stage. ARGs declared before FROM
# are only in scope for the FROM line itself.
ARG TARGETPLATFORM
ARG DENO_VERSION
ARG NODE_MAJOR
ARG FFMPEG_RELEASE
ARG FFMPEG_BUILD

COPY docker/ci-base.requirements.txt /tmp/ci-base.requirements.txt

RUN echo "Building for ${TARGETPLATFORM:?}" && \
# Install debian packages
  apt-get update -qq && \
  apt-get install -y inotify-tools curl git openssh-client jq \
    python3 python3-setuptools python3-wheel python3-dev pipx \
    python3-mutagen locales procps build-essential graphviz zsh unzip && \
# Install ffmpeg — pinned build, see issue #347. selfhosted's runner copies these binaries
# from this image, so the version here is what production ships.
  export FFMPEG_BASE_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/${FFMPEG_RELEASE}/ffmpeg-${FFMPEG_BUILD}" && \
  export FFMPEG_DOWNLOAD=$(case ${TARGETPLATFORM:-linux/amd64} in \
    "linux/amd64")   echo "${FFMPEG_BASE_URL}-linux64-gpl.tar.xz"   ;; \
    "linux/arm64")   echo "${FFMPEG_BASE_URL}-linuxarm64-gpl.tar.xz" ;; \
    *)               echo ""        ;; esac) && \
    curl -L ${FFMPEG_DOWNLOAD} --output /tmp/ffmpeg.tar.xz && \
    tar -xf /tmp/ffmpeg.tar.xz --strip-components=2 --no-anchored -C /usr/bin/ ffmpeg ffprobe && \
# Install nodejs, Yarn, Deno, yt-dlp, and Apprise
  curl -sL https://deb.nodesource.com/setup_${NODE_MAJOR}.x -o nodesource_setup.sh && \
  bash nodesource_setup.sh && \
  apt-get install -y nodejs && \
  apt-get clean && \
  rm -f /var/lib/apt/lists/*_* && \
  npm install -g yarn && \
  # Install baseline Elixir packages
  mix local.hex --force && \
  mix local.rebar --force && \
  # Install Deno - required for YouTube downloads (See yt-dlp#14404)
  curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s -- ${DENO_VERSION} -y --no-modify-path && \
  # Download yt-dlp (pinned to latest at base image build time)
  export YT_DLP_DOWNLOAD=$(case ${TARGETPLATFORM:-linux/amd64} in \
  "linux/amd64")   echo "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"   ;; \
  "linux/arm64")   echo "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_aarch64" ;; \
  *)               echo "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"        ;; esac) && \
  curl -L ${YT_DLP_DOWNLOAD} -o /usr/local/bin/yt-dlp && \
  chmod a+rx /usr/local/bin/yt-dlp && \
  # Install Apprise (version pinned in docker/ci-base.requirements.txt, managed by Renovate)
  export PIPX_HOME=/opt/pipx && \
  export PIPX_BIN_DIR=/usr/local/bin && \
  pipx install "$(cat /tmp/ci-base.requirements.txt)" && \
  rm /tmp/ci-base.requirements.txt && \
  # Set up ZSH tools
  chsh -s $(which zsh) && \
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
