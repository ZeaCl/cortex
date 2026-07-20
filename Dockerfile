# Dockerfile — Cortex Community (multi-stage Elixir release)
FROM elixir:1.19-alpine AS build

RUN apk add --no-cache build-base git npm

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

# Copy path dependency (cortex_core) and main app mix files
COPY core/ /app/core/
COPY mix.exs mix.lock /app/

ENV MIX_ENV=prod

RUN mix deps.get --only prod && \
    mix deps.compile

# Copy source code
COPY lib /app/lib
COPY priv /app/priv
COPY config /app/config

# Copy assets and build them
COPY assets /app/assets
RUN mix assets.deploy

RUN mix release

# Runtime stage
FROM alpine:3.23

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

COPY --from=build /app/_build/prod/rel/cortex_community ./

RUN addgroup -g 1000 cortex && \
    adduser -D -u 1000 -G cortex cortex && \
    chown -R cortex:cortex /app

USER cortex

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:4000/api/health || exit 1

CMD ["bin/cortex_community", "start"]