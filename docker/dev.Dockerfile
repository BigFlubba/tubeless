ARG BASE_IMAGE="ghcr.io/communitymaintained/tubeless-ci-base:latest"

FROM ${BASE_IMAGE}

COPY mix.exs mix.lock ./
# Install Elixir deps
# NOTE: this has to be before the bulk copy to ensure that deps are cached
RUN MIX_ENV=dev mix deps.get && MIX_ENV=dev mix deps.compile
RUN MIX_ENV=test mix deps.get && MIX_ENV=test mix deps.compile

COPY . ./

# Gives us iex shell history
ENV ERL_AFLAGS="-kernel shell_history enabled"

EXPOSE 4008
