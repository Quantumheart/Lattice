# ── Build Stage ──────────────────────────────────────────────────────
FROM docker.io/library/debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.41.6

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git unzip xz-utils clang cmake ninja-build \
    pkg-config build-essential libssl-dev ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"
RUN TAR_OPTIONS="--no-same-owner" flutter precache --web

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
  && . "$HOME/.cargo/env" \
  && rustup toolchain install nightly \
  && rustup component add rust-src --toolchain nightly \
  && rustup target add wasm32-unknown-unknown --toolchain nightly \
  && cargo install wasm-pack \
  && cargo install flutter_rust_bridge_codegen

ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app
COPY . .

RUN sh scripts/prepare-web.sh \
  && test -f assets/vodozemac/vodozemac_bindings_dart.js \
  && test -f assets/vodozemac/vodozemac_bindings_dart_bg.wasm
RUN flutter build web --release --base-href /

# ── Serve Stage ──────────────────────────────────────────────────────
FROM docker.io/library/caddy:2-alpine

COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /app/build/web /srv

EXPOSE 80
