# ─────────────────────────────────────────────────────────────────────────────
# Stage 1 – Builder
# Compiles the latest stable Valkey release from source with TLS support
# compiled in (disabled at runtime).  Nothing from this stage lands in the
# final image.
# ─────────────────────────────────────────────────────────────────────────────
FROM docker.io/library/alpine:latest AS builder

# ── Version pins (overridable via --build-arg in GH Actions) ─────────────────
ARG VALKEY_VERSION=9.1.3

# ── Build toolchain + compile-time dependencies ───────────────────────────────
RUN apk add --no-cache \
    build-base       \
    ca-certificates  \
    curl             \
    linux-headers    \
    openssl-dev      \
    pkgconf

# ── Valkey source ─────────────────────────────────────────────────────────────
RUN curl -fsSL \
    "https://github.com/valkey-io/valkey/archive/refs/tags/${VALKEY_VERSION}.tar.gz" | \
    tar xz -C /tmp

# ── Compile + install ─────────────────────────────────────────────────────────
RUN cd /tmp/valkey-${VALKEY_VERSION} && \
    make -j"$(nproc)" BUILD_TLS=yes PREFIX=/usr/local install && \
    find /usr/local/bin -type f -exec strip {} +

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2 – Runtime
# Minimal Alpine image; only runtime shared libraries, no build toolchain.
# Runs as the unprivileged `valkey` user from the start; nothing is chowned at
# runtime, so it works with all capabilities dropped.
# ─────────────────────────────────────────────────────────────────────────────
FROM docker.io/library/alpine:latest

# ── OCI labels (injected by GH Actions at build time) ────────────────────────
ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.created="${BUILD_DATE}"                  \
    org.opencontainers.image.revision="${VCS_REF}"                    \
    org.opencontainers.image.source="https://github.com/kpirnie/infra-build" \
    org.opencontainers.image.description="Valkey · built from source · TLS compiled in (disabled at runtime) · non-root"

# ── Fixed UIDs ────────────────────────────────────────────────────────────────
ARG VALKEY_UID=999
ARG VALKEY_GID=1000

RUN addgroup -g "${VALKEY_GID}" -S valkey && \
    adduser  -u "${VALKEY_UID}" -S -G valkey -H -s /sbin/nologin valkey

# ── Runtime-only packages (no -dev, no build tools) ──────────────────────────
RUN apk add --no-cache \
    ca-certificates  \
    libgcc           \
    libssl3          \
    tzdata

# ── Artifacts from builder ────────────────────────────────────────────────────
COPY --from=builder /usr/local/bin/ /usr/local/bin/

# ── Runtime directories, permissions, and hardening ──────────────────────────
RUN mkdir -p /data /usr/local/etc/valkey && \
    chown valkey:valkey /data             && \
    chmod 750 /data                       && \
    # Strip setuid/setgid bits from all binaries in the final image
    find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | \
    xargs chmod a-s 2>/dev/null || true

WORKDIR /data

EXPOSE 6379

USER valkey

# PodNest passes the config path as the command
CMD ["valkey-server"]