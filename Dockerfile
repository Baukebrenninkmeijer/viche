# ============================================================
# Stage 1 — Builder
# ============================================================
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4.9
ARG UBUNTU_VERSION=noble-20260217

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-${UBUNTU_VERSION}"
ARG RUNNER_IMAGE="ubuntu:${UBUNTU_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

# Install Hex + Rebar
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# SSL configuration (compile-time; evaluated during mix release)
# Set DISABLE_FORCE_SSL=true when deploying behind a TLS-terminating reverse proxy
ARG DISABLE_FORCE_SSL=false
ENV DISABLE_FORCE_SSL=${DISABLE_FORCE_SSL}
# Optionally exempt specific hostnames from force_ssl (comma-separated)
ARG FORCE_SSL_EXCLUDE_HOSTS=""
ENV FORCE_SSL_EXCLUDE_HOSTS=${FORCE_SSL_EXCLUDE_HOSTS}

# Copy dependency manifests first for better layer caching
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files before we compile deps
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy priv, lib, and assets
COPY priv priv
COPY lib lib
COPY assets assets

# Compile application (generates colocated JS hooks)
RUN mix compile

# Deploy assets (esbuild can now resolve phoenix-colocated imports)
RUN mix assets.deploy

# Copy runtime config last (it is evaluated at startup, not compile time)
COPY config/runtime.exs config/

# Copy release overlay scripts
COPY rel rel

# Build the release
RUN mix release

# ============================================================
# Stage 2 — Runner
# ============================================================
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && apt-get install -y \
      libstdc++6 \
      openssl \
      libncurses6 \
      locales \
      ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"

WORKDIR /app

RUN chown nobody /app

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/viche ./

USER nobody

CMD ["/app/bin/server"]

# IPv6 networking (set ECTO_IPV6=true and ERL_AFLAGS="-proto_dist inet6_tcp" if needed)
ENV ECTO_IPV6="false"
ENV ERL_AFLAGS=""
