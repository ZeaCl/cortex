# Dockerfile — Cortex Community (multi-stage Elixir release)
FROM elixir:1.19-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

# Copy path dependency (cortex_core) and main app mix files
COPY core/ /app/core/
COPY mix.exs mix.lock /app/

ENV MIX_ENV=prod

RUN mix deps.get && \
    mix deps.compile

# Copy source code
COPY lib /app/lib
COPY priv /app/priv
COPY config /app/config

# Copy assets
COPY assets /app/assets

# Pre-download esbuild and tailwind, then compile assets
RUN mix assets.setup && mix assets.deploy

RUN mix release

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 openssl libncurses6 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/_build/prod/rel/cortex_community ./

RUN addgroup --gid 1000 cortex && \
    adduser --disabled-password --uid 1000 --gid 1000 cortex && \
    chown -R cortex:cortex /app

USER cortex

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -sf http://localhost:4000/api/health || exit 1

CMD ["bin/cortex_community", "start"]
