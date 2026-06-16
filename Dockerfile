# Dockerfile
FROM elixir:1.19-alpine AS build

# Install build dependencies
RUN apk add --no-cache build-base git npm

WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy path dependencies and main app mix files
COPY cortex-core/ /app/cortex-core/
COPY cortex_community/mix.exs cortex_community/mix.lock /app/cortex_community/

WORKDIR /app/cortex_community

# Set environment
ENV MIX_ENV=prod

# Install dependencies
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy source code
COPY cortex_community/lib /app/cortex_community/lib
COPY cortex_community/priv /app/cortex_community/priv
COPY cortex_community/config /app/cortex_community/config

# Copy assets and build them
COPY cortex_community/assets /app/cortex_community/assets
RUN mix assets.deploy

# Build release
RUN mix release

# Runtime stage
FROM alpine:3.23

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

# Copy release from build stage
COPY --from=build /app/cortex_community/_build/prod/rel/cortex_community ./

# Create non-root user
RUN addgroup -g 1000 cortex && \
    adduser -D -u 1000 -G cortex cortex && \
    chown -R cortex:cortex /app

USER cortex

# Expose port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:4000/api/health || exit 1

# Start command
CMD ["bin/cortex_community", "start"]