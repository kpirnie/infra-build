#!/usr/bin/env bash
# build-local.sh
# Builds and smoke-tests all images locally against the native platform.
# Does not push to any registry.
# Run from the repo root.

set -uo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${BLUE}[build]${NC} $*"; }
ok()   { echo -e "${GREEN}[  ok ]${NC} $*"; }
fail() { echo -e "${RED}[ FAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[ warn]${NC} $*"; }

# ── Result tracking ───────────────────────────────────────────────────────────
declare -A RESULTS

# ── Build metadata ────────────────────────────────────────────────────────────
BUILD_DATE=$(date -u +%Y-%m-%d)
VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "local")

# ── nginx module version resolution ──────────────────────────────────────────
gh_latest()     { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | grep '"tag_name"' | cut -d'"' -f4; }
gh_latest_tag() { curl -fsSL "https://api.github.com/repos/$1/tags" | grep '"name"' | head -1 | cut -d'"' -f4; }
strip_v()       { echo "${1#v}"; }

resolve_nginx_versions() {
  log "Resolving latest nginx module versions..."

  NGINX_VERSION=$(curl -fsSL https://nginx.org/en/download.html | grep -oP 'nginx-\K1\.[0-9]*[13579]\.[0-9]+(?=\.tar\.gz)' | head -1)
  local openssl_tag;  openssl_tag=$(gh_latest openssl/openssl);  OPENSSL_VERSION="${openssl_tag#openssl-}"
  LUAJIT_BRANCH=$(curl -fsSL "https://api.github.com/repos/openresty/luajit2/tags" | grep '"name"' | grep -oP '"v2\.1-\d+"' | head -1 | tr -d '"')
  NDK_VERSION=$(strip_v "$(gh_latest_tag vision5/ngx_devel_kit)")
  LUA_NGINX_VERSION=$(strip_v "$(gh_latest_tag openresty/lua-nginx-module)")
  HEADERS_MORE_VERSION=$(strip_v "$(gh_latest_tag openresty/headers-more-nginx-module)")
  GEOIP2_VERSION=$(gh_latest leev/ngx_http_geoip2_module)
  NJS_VERSION=$(gh_latest nginx/njs)

  log "  nginx          : ${NGINX_VERSION}"
  log "  openssl        : ${OPENSSL_VERSION}"
  log "  luajit         : ${LUAJIT_BRANCH}"
  log "  ndk            : ${NDK_VERSION}"
  log "  lua-nginx      : ${LUA_NGINX_VERSION}"
  log "  headers-more   : ${HEADERS_MORE_VERSION}"
  log "  geoip2         : ${GEOIP2_VERSION}"
  log "  njs            : ${NJS_VERSION}"
  echo ""
}

# ── Native platform detection ─────────────────────────────────────────────────
case "$(uname -m)" in
  x86_64)  PLATFORM="linux/amd64" ;;
  aarch64) PLATFORM="linux/arm64" ;;
  arm64)   PLATFORM="linux/arm64" ;;
  *)       PLATFORM="linux/amd64" ;;
esac

# ── Preflight checks ──────────────────────────────────────────────────────────
preflight() {
  if ! command -v podman &>/dev/null; then
    fail "podman not found in PATH"; exit 1
  fi

  if ! podman info &>/dev/null; then
    fail "Podman daemon is not running"; exit 1
  fi

  if ! command -v curl &>/dev/null; then
    fail "curl not found in PATH (required for version resolution)"; exit 1
  fi

  for dir in nginx php; do
    if [[ ! -d "$dir" ]]; then
      fail "Expected directory '${dir}' not found — run this script from the repo root"
      exit 1
    fi
  done

  log "Platform : ${PLATFORM}"
  log "Date     : ${BUILD_DATE}"
  log "Ref      : ${VCS_REF}"
  echo ""
}

# ── Build ─────────────────────────────────────────────────────────────────────
# Returns 0 on success, 1 on failure.
do_build() {
  local label="$1"
  local context="$2"
  local tag="$3"
  shift 3
  local extra_args=("$@")

  log "Building ${label} → ${tag}"

  local cmd=(
    podman build
    --platform "${PLATFORM}"
    --tag "${tag}"
    --build-arg "BUILD_DATE=${BUILD_DATE}"
    --build-arg "VCS_REF=${VCS_REF}"
  )

  for arg in "${extra_args[@]}"; do
    cmd+=(--build-arg "${arg}")
  done

  cmd+=("${context}")

  if "${cmd[@]}"; then
    ok "Build succeeded: ${tag}"
    return 0
  else
    fail "Build failed: ${tag}"
    return 1
  fi
}

# ── nginx smoke test ──────────────────────────────────────────────────────────
smoke_nginx() {
  local tag="$1"
  log "Smoke testing nginx: ${tag}"
  local passed=0

  # Config validity
  if podman run --rm "${tag}" nginx -t 2>&1 | grep -q "test is successful"; then
    ok "nginx -t: config valid"
  else
    fail "nginx -t: config invalid"
    (( passed++ )) || true
  fi

  # Version string
  local ver
  ver=$(podman run --rm "${tag}" nginx -v 2>&1)
  ok "Version: ${ver}"

  return "${passed}"
}

# ── PHP smoke test ────────────────────────────────────────────────────────────
smoke_php() {
  local tag="$1"
  log "Smoke testing PHP: ${tag}"
  local passed=0

  # PHP version
  local ver
  ver=$(podman run --rm "${tag}" php -v | head -1)
  ok "PHP: ${ver}"

  # Extension check — sodium is built-in so won't appear in php -m; skip it
  local required_exts=(
    apcu bcmath calendar exif
    gd igbinary imagick intl
    msgpack mysqli pcntl
    pdo_mysql pdo_pgsql pgsql redis
    sockets tidy uuid xsl yaml zip
  )

  local loaded
  loaded=$(podman run --rm "${tag}" php -m 2>/dev/null)

  local missing=()
  for ext in "${required_exts[@]}"; do
    if ! echo "${loaded}" | grep -qi "${ext}"; then
      missing+=("${ext}")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "All required extensions loaded"
  else
    fail "Missing extensions: ${missing[*]}"
    (( passed++ )) || true
  fi

  # WP-CLI
  if podman run --rm "${tag}" wp --info --allow-root &>/dev/null; then
    ok "WP-CLI: OK"
  else
    fail "WP-CLI: check failed"
    (( passed++ )) || true
  fi

  # Composer
  local cver
  if cver=$(podman run --rm "${tag}" composer --version 2>/dev/null); then
    ok "Composer: ${cver}"
  else
    fail "Composer: check failed"
    (( passed++ )) || true
  fi

  return "${passed}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
preflight

# nginx — resolve versions first, then pass them all as build args
NGINX_TAG="ghcr.io/kpirnie/nginx:local"
resolve_nginx_versions

if do_build "nginx" "nginx" "${NGINX_TAG}"          \
    "NGINX_VERSION=${NGINX_VERSION}"                \
    "OPENSSL_VERSION=${OPENSSL_VERSION}"            \
    "LUAJIT_BRANCH=${LUAJIT_BRANCH}"                \
    "NDK_VERSION=${NDK_VERSION}"                    \
    "LUA_NGINX_VERSION=${LUA_NGINX_VERSION}"        \
    "HEADERS_MORE_VERSION=${HEADERS_MORE_VERSION}"  \
    "GEOIP2_VERSION=${GEOIP2_VERSION}"              \
    "NJS_VERSION=${NJS_VERSION}"; then
  if smoke_nginx "${NGINX_TAG}"; then
    RESULTS[nginx]="PASS"
  else
    RESULTS[nginx]="SMOKE_FAIL"
  fi
else
  RESULTS[nginx]="BUILD_FAIL"
fi

echo ""

# PHP versions — PECL resolves extension versions at build time automatically
PHP_VERSIONS=("8.2" "8.3" "8.4" "8.5")

for ver in "${PHP_VERSIONS[@]}"; do
  PHP_TAG="ghcr.io/kpirnie/php:${ver}-local"

  if do_build "php ${ver}" "php" "${PHP_TAG}" "PHP_VERSION=${ver}"; then
    if smoke_php "${PHP_TAG}"; then
      RESULTS["php-${ver}"]="PASS"
    else
      RESULTS["php-${ver}"]="SMOKE_FAIL"
    fi
  else
    RESULTS["php-${ver}"]="BUILD_FAIL"
  fi

  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}──────────────────────────────────────────${NC}"
echo -e "${BOLD}  Build Summary${NC}"
echo -e "${BOLD}──────────────────────────────────────────${NC}"

OVERALL=0
for key in nginx php-8.2 php-8.3 php-8.4 php-8.5; do
  result="${RESULTS[$key]:-SKIPPED}"
  if [[ "${result}" == "PASS" ]]; then
    echo -e "  ${GREEN}✔${NC}  ${key}"
  else
    echo -e "  ${RED}✘${NC}  ${key}  (${result})"
    OVERALL=1
  fi
done

echo -e "${BOLD}──────────────────────────────────────────${NC}"
echo ""

if [[ "${OVERALL}" -eq 0 ]]; then
  ok "All images built and verified"
else
  fail "One or more images failed — review output above"
fi

echo ""
warn "Local images are tagged with ':local' and have not been pushed."
warn "To clean up: podman images | grep ':local' | awk '{print \$3}' | xargs podman rmi"

exit "${OVERALL}"