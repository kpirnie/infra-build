# ─────────────────────────────────────────────────────────────────────────────
# Stage 1 – Builder
# Compiles nginx mainline from source against quictls, with all required
# third-party modules.  Nothing from this stage lands in the final image.
# ─────────────────────────────────────────────────────────────────────────────
FROM docker.io/library/alpine:latest AS builder

# ── Version pins (overridable via --build-arg in GH Actions) ─────────────────
ARG NGINX_VERSION=1.31.1
ARG OPENSSL_VERSION=4.0.0
ARG HEADERS_MORE_VERSION=0.39
ARG GEOIP2_VERSION=3.4
ARG NJS_VERSION=0.9.5

# ── Build toolchain + compile-time dependencies ───────────────────────────────
RUN apk add --no-cache \
    build-base       \
    ca-certificates  \
    cmake            \
    curl             \
    gd-dev           \
    git              \
    libmaxminddb-dev \
    libxslt-dev      \
    zstd-dev         \
    linux-headers    \
    pcre2-dev        \
    perl             \
    zlib-dev

# ── quictls ── OpenSSL fork that adds QUIC transport support ──────────────────
# Passed to nginx configure via --with-openssl; built statically into nginx.
RUN curl -fsSL \
    "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" | \
    tar xz -C /tmp

# ── ngx_brotli ── dynamic Brotli compression ──────────────────────────────────
RUN git clone --depth 1 \
    https://github.com/google/ngx_brotli.git /tmp/ngx_brotli && \
    cd /tmp/ngx_brotli && \
    git submodule update --init

# ── zstd-nginx-module ── Zstandard compression ───────────────────────────────
RUN git clone --depth 1 \
    https://github.com/tokers/zstd-nginx-module.git /tmp/zstd-nginx-module

# ── ngx_http_geoip2_module ── MaxMind GeoIP2 (db must be volume-mounted) ──────
RUN curl -fsSL \
    "https://github.com/leev/ngx_http_geoip2_module/archive/refs/tags/${GEOIP2_VERSION}.tar.gz" | \
    tar xz -C /tmp

# ── headers-more-nginx-module ── fine-grained request/response header control ─
RUN curl -fsSL \
    "https://github.com/openresty/headers-more-nginx-module/archive/refs/tags/v${HEADERS_MORE_VERSION}.tar.gz" | \
    tar xz -C /tmp

# ── njs ── nginx JavaScript module ───────────────────────────────────────────
RUN curl -fsSL \
    "https://github.com/nginx/njs/archive/refs/tags/${NJS_VERSION}.tar.gz" | \
    tar xz -C /tmp

# ── nginx mainline source ─────────────────────────────────────────────────────
RUN curl -fsSL \
    "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" | \
    tar xz -C /tmp

# ── Configure + compile ───────────────────────────────────────────────────────
RUN cd /tmp/nginx-${NGINX_VERSION} && ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_image_filter_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-stream \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --without-http_ssi_module \
    --without-http_empty_gif_module \
    --with-openssl=/tmp/openssl-${OPENSSL_VERSION} \
    --with-openssl-opt="no-shared no-tests" \
    --add-module=/tmp/ngx_brotli \
    --add-module=/tmp/zstd-nginx-module \
    --add-module=/tmp/ngx_http_geoip2_module-${GEOIP2_VERSION} \
    --add-module=/tmp/headers-more-nginx-module-${HEADERS_MORE_VERSION} \
    --add-module=/tmp/njs-${NJS_VERSION}/nginx \
    --with-cc-opt="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security" \
    --with-ld-opt="-Wl,-z,relro -Wl,-z,now -Wl,--as-needed" && \
    make -j"$(nproc)" && \
    make install && \
    strip /usr/sbin/nginx

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2 – Runtime
# Minimal Alpine image; only runtime shared libraries, no build toolchain.
# nginx master runs as root (required to bind :80/:443), workers drop to
# the unprivileged `nginx` user via the `user` directive in nginx.conf.
# ─────────────────────────────────────────────────────────────────────────────
FROM docker.io/library/alpine:latest

# ── OCI labels (injected by GH Actions at build time) ────────────────────────
ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.created="${BUILD_DATE}"                  \
    org.opencontainers.image.revision="${VCS_REF}"                    \
    org.opencontainers.image.source="https://github.com/kpirnie/infra-build" \
    org.opencontainers.image.description="nginx mainline · QUIC/HTTP3 · Brotli · Zstd · GeoIP2 · HeadersMore · NJS · LuaJIT · ImageFilter · Stream"

# ── Fixed UIDs ────────────────────────────────────────────────────────────────
ARG NGINX_UID=101
ARG NGINX_GID=101

RUN addgroup -g "${NGINX_GID}" -S nginx && \
    adduser  -u "${NGINX_UID}" -S -G nginx -H -s /sbin/nologin nginx

# ── Runtime-only packages (no -dev, no build tools) ──────────────────────────
RUN apk add --no-cache \
    ca-certificates  \
    libgcc           \
    libgd            \
    libmaxminddb     \
    zstd-libs        \
    pcre2            \
    tzdata           \
    libxml2          \
    zlib

# ── Artifacts from builder ────────────────────────────────────────────────────
COPY --from=builder /usr/sbin/nginx           /usr/sbin/nginx
COPY --from=builder /etc/nginx                /etc/nginx

# ── Overlay minimal config (mime.types retained from builder's make install) ──
COPY conf/nginx.conf /etc/nginx/nginx.conf

# ── Runtime directories, permissions, and hardening ──────────────────────────
RUN mkdir -p \
    /var/cache/nginx/client_temp  \
    /var/cache/nginx/fastcgi_temp \
    /var/cache/nginx/proxy_temp   \
    /var/cache/nginx/scgi_temp    \
    /var/cache/nginx/uwsgi_temp   \
    /var/log/nginx                \
    /etc/nginx/conf.d             \
    /etc/nginx/stream.d           \
    /etc/nginx/sites-enabled   && \
    chown -R nginx:nginx              \
    /var/cache/nginx              \
    /var/log/nginx                \
    /etc/nginx/conf.d             \
    /etc/nginx/stream.d           \
    /etc/nginx/sites-enabled   && \
    chmod 750 /etc/nginx           && \
    chmod 640 /etc/nginx/nginx.conf && \
    # Strip setuid/setgid bits from all binaries in the final image
    find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | \
    xargs chmod a-s 2>/dev/null || true

# ── Expose HTTP and HTTPS ports; master listens on 80/443, workers drop to nginx
EXPOSE 80 443 443/udp

# ── Config validity check + PID 1 liveness
STOPSIGNAL SIGQUIT

# run nginx -g "daemon off;" to stay in the foreground; nginx will reload config on SIGHUP
CMD ["/usr/sbin/nginx", "-g", "daemon off;"]
