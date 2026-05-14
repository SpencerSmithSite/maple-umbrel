# syntax=docker/dockerfile:1

# ─── Stage 1: Build ────────────────────────────────────────────────────────────
FROM oven/bun:latest AS builder

ARG MAPLE_VERSION=master
ARG BUILD_VITE_OPEN_SECRET_API_URL=https://enclave.trymaple.ai
ARG BUILD_VITE_BILLING_API_URL=https://billing.opensecret.cloud
ARG BUILD_VITE_CLIENT_ID=ba5a14b5-d915-47b1-b7b1-afda52bc5fc6

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
ENV VITE_CLIENT_ID=$BUILD_VITE_CLIENT_ID

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

    # Use Docker's embedded DNS so nginx resolves container hostnames at
    # request time rather than startup. Required when proxy_pass uses a
    # variable (set $var below), which defers resolution to per-request.
    resolver 127.0.0.11 valid=30s;

    # sub_filter rewrites HTML responses; gzip must be off for it to work.
    gzip off;

    # Proxy billing API requests to billing.opensecret.cloud.
    # Must appear before the /v1/ block; nginx longest-prefix matching
    # selects /v1/maple/ over /v1/ for these paths.
    location /v1/maple/ {
        proxy_pass https://billing.opensecret.cloud/v1/maple/;
        proxy_http_version 1.1;
        proxy_set_header Host billing.opensecret.cloud;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_ssl_server_name on;
    }

    # Proxy all OpenAI-compatible API requests to the maple-proxy container.
    # proxy_buffering off is critical — maple-proxy uses SSE streaming.
    location /v1/ {
        set $maple_proxy maple-proxy:8080;
        proxy_pass http://$maple_proxy/v1/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 300s;
    }

    # Proxy health check to maple-proxy as well.
    location /health {
        set $maple_proxy maple-proxy:8080;
        proxy_pass http://$maple_proxy/health;
        proxy_http_version 1.1;
    }

    # Never cache the app shell.
    location = /index.html {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
        sub_filter '</head>' '<script>if(!window.crypto.randomUUID){window.crypto.randomUUID=function(){return"10000000-1000-4000-8000-100000000000".replace(/[018]/g,function(c){return(+c^crypto.getRandomValues(new Uint8Array(1))[0]&15>>+c/4).toString(16)})}}</script></head>';
        sub_filter_once on;
    }

    # Cache hashed assets forever.
    location ~* \.(js|css|woff2?|ttf|otf|eot|svg|png|jpg|jpeg|gif|ico|webp)$ {
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable";
        try_files $uri =404;
    }

    # SPA fallback for TanStack Router.
    location / {
        try_files $uri $uri/ /index.html;
        sub_filter '</head>' '<script>if(!window.crypto.randomUUID){window.crypto.randomUUID=function(){return"10000000-1000-4000-8000-100000000000".replace(/[018]/g,function(c){return(+c^crypto.getRandomValues(new Uint8Array(1))[0]&15>>+c/4).toString(16)})}}</script></head>';
        sub_filter_once on;
    }
}
EOF

EXPOSE 3000
