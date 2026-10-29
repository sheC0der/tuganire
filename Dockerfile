# syntax=docker/dockerfile:1
# check=skip=FromPlatformFlagConstDisallowed,SecretsUsedInArgOrEnv
# Both skips are deliberate: the Flutter archive below is x64-only, so stage 1 is
# pinned to amd64; and SUPABASE_PUBLISHABLE_KEY is public (it ships in the web app),
# it only trips the "secret in ARG" check because its name ends in KEY.

# One image for Railway: the Express backend serves the API under /api and the
# Flutter web build from the same origin.
#
# Build args (Railway passes service variables with these names automatically):
#   SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY   compiled into the web app; both are public.
# Never add ANTHROPIC_API_KEY or any Supabase secret key as a build arg: build args
# are recorded in the image. The server reads its secrets at runtime instead.

# ---- Stage 1: build the Flutter web app ------------------------------------
# Google doesn't publish a Flutter image, so install the official release archive,
# pinned to the version the project uses and checked against its published SHA-256
# (https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json).
# The archive is x64-only; the web output is the same on any platform.
FROM --platform=linux/amd64 debian:trixie-slim AS web

ARG FLUTTER_VERSION=3.47.1
ARG FLUTTER_SHA256=a1d8166c0309267cb7dc99f1424eecf08b86946ad3b50723c6f59945964aea45

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
 && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
 && tar -xJf /tmp/flutter.tar.xz -C /opt \
 && rm /tmp/flutter.tar.xz \
 && git config --global --add safe.directory /opt/flutter

ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics --no-cli-animations \
 && flutter precache --web

WORKDIR /src
# Dependencies first so this layer stays cached until pubspec changes.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY lib lib
COPY web web

ARG SUPABASE_URL
ARG SUPABASE_PUBLISHABLE_KEY
RUN if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_PUBLISHABLE_KEY" ]; then \
      echo "SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must be set as build args (Railway: service variables)." >&2; \
      exit 1; \
    fi \
 && flutter build web --release \
      --dart-define=SUPABASE_URL="$SUPABASE_URL" \
      --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"

# ---- Stage 2: the server ---------------------------------------------------
FROM node:26-trixie-slim

ENV NODE_ENV=production
WORKDIR /app

COPY backend/package.json backend/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY backend/ ./
COPY --from=web /src/build/web ./public

USER node
# Railway sets PORT; 8787 is the local default.
EXPOSE 8787
CMD ["node", "server.js"]
