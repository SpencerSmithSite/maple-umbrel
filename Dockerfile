# syntax=docker/dockerfile:1

# ─── Stage 1: Build ────────────────────────────────────────────────────────────
FROM oven/bun:latest AS builder

ARG MAPLE_VERSION=v2.0.16
ARG BUILD_VITE_OPEN_SECRET_API_URL=https://enclave.trymaple.ai
ARG BUILD_VITE_BILLING_API_URL=

# git is needed to clone; ca-certificates keeps TLS happy
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone --depth=1 --branch ${MAPLE_VERSION} https://github.com/OpenSecretCloud/Maple .

WORKDIR /app/frontend

RUN bun install --frozen-lockfile

# Bake the URLs into the Vite bundle at build time.
# These become import.meta.env.VITE_* constants in the compiled JS.
ENV VITE_OPEN_SECRET_API_URL=$BUILD_VITE_OPEN_SECRET_API_URL
ENV VITE_MAPLE_BILLING_API_URL=$BUILD_VITE_BILLING_API_URL

RUN bun run build

# ─── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM nginx:alpine

COPY --from=builder /app/frontend/dist /usr/share/nginx/html

# Inline the nginx server block so the image is fully self-contained.
COPY <<'EOF' /etc/nginx/conf.d/default.conf
server {
    listen 3000;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Never cache the app shell — browsers must always fetch the latest entry point.
    location = /index.html {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
    }

    # Vite appends a content hash to every asset filename, so these are
    # safe to cache for a year (immutable = browsers skip revalidation).
    location ~* \.(js|css|woff2?|ttf|otf|eot|svg|png|jpg|jpeg|gif|ico|webp)$ {
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable";
        try_files $uri =404;
    }

    # SPA fallback: unknown paths serve index.html so TanStack Router
    # can handle client-side routing (HTML5 history mode).
    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF

EXPOSE 3000
