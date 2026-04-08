# syntax=docker/dockerfile:1

# ── Build Stage ──────────────────────────────────────────────────────
FROM docker.io/library/debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.41.6
ARG VODOZEMAC_VERSION=0.5.0
ARG GIPHY_API_KEY

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

# ── Vodozemac WASM (version-pinned, source-independent) ─────────────
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    git clone --depth 1 --branch ${VODOZEMAC_VERSION} \
      https://github.com/famedly/dart-vodozemac.git /tmp/vodozemac \
  && cd /tmp/vodozemac \
  && flutter_rust_bridge_codegen build-web \
      --dart-root dart --rust-root "$(readlink -f rust)" --release \
  && mkdir -p /vodozemac-artifacts \
  && cp dart/web/pkg/vodozemac_bindings_dart* /vodozemac-artifacts/ \
  && rm -rf /tmp/vodozemac

# ── Dart Dependencies ────────────────────────────────────────────────
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# ── Source + Build ───────────────────────────────────────────────────
COPY . .
RUN cp /vodozemac-artifacts/vodozemac_bindings_dart* ./assets/vodozemac/ \
  && test -f assets/vodozemac/vodozemac_bindings_dart.js \
  && test -f assets/vodozemac/vodozemac_bindings_dart_bg.wasm
RUN dart compile js ./web/native_executor.dart -o ./web/native_executor.js -m
RUN flutter build web --release --base-href / \
      ${GIPHY_API_KEY:+--dart-define=GIPHY_API_KEY=$GIPHY_API_KEY}

# ── Serve Stage ──────────────────────────────────────────────────────
FROM docker.io/library/caddy:2-alpine

COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /app/build/web /srv

EXPOSE 80
