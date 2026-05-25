#!/usr/bin/env bash
# build-local.sh
# Builds and smoke-tests all images locally against the native platform.
# By default tags images as ':local' and does not push.
# Pass --push to tag as ':latest' and push to GHCR.
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

# ── Flags ─────────────────────────────────────────────────────────────────────
PUSH=false
for arg in "$@"; do
  case "${arg}" in
    --push) PUSH=true ;;
    *) warn "Unknown argument: ${arg}"; exit 1 ;;
  esac
done

if [[ "${PUSH}" == true ]]; then
  TAG_SUFFIX="latest"
else
  TAG_SUFFIX="local"
fi

# ── Result tracking ───────────────────────────────────────────────────────────
declare -A RESULTS

# ── Build metadata ────────────────────────────────────────────────────────────
BUILD_DATE=$(date -u +%Y-%m-%d)
VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "local")

# ── nginx module version resolution ───────────────────────────────────────────
gh_latest()     { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | grep '"tag_name"' | cut -d'"' -f4; }
gh_latest_tag() { curl -fsSL "https://api.github.com/repos/$1/tags" | grep '"name"' | head -1 | cut -d'"' -f4; }
strip_v()       { echo "${1#v}"; }

resolve_nginx_versions() {
  log "Resolving latest nginx module versions..."

  NGINX_VERSION=$(curl -fsSL https://nginx.org/en/download.html | grep -oP 'nginx-\K1\.[0-9]*[13579]\.[0-9]+(?=\.tar\.gz)' | head -1)
  local openssl_tag;  openssl_tag=$(gh_latest openssl/openssl);  OPENSSL_VERSION="${openssl_tag#openssl-}"
  HEADERS_MORE_VERSION=$(strip_v "$(gh_latest_tag openresty/headers-more-nginx-module)")
  GEOIP2_VERSION=$(gh_latest leev/ngx_http_geoip2_module)
  NJS_VERSION=$(gh_latest nginx/njs)

  log "  nginx          : ${NGINX_VERSION}"
  log "  openssl        : ${OPENSSL_VERSION}"
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

  # --push requires an active GHCR login
  if [[ "${PUSH}" == true ]]; then
    if ! podman login ghcr.io --get-login &>/dev/null; then
      fail "--push specified but not logged in to ghcr.io — run: podman login ghcr.io"
      exit 1
    fi
  fi

  for dir in nginx php sftp fail2ban; do
    if [[ ! -d "$dir" ]]; then
      fail "Expected directory '${dir}' not found — run this script from the repo root"
      exit 1
    fi
  done

  log "Platform : ${PLATFORM}"
  log "Date     : ${BUILD_DATE}"
  log "Ref      : ${VCS_REF}"
  log "Mode     : ${TAG_SUFFIX}$( [[ "${PUSH}" == true ]] && echo ' (push enabled)' )"
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

# ── Push ──────────────────────────────────────────────────────────────────────
do_push() {
  local tag="$1"
  local dated_tag="$2"

  log "Pushing ${tag}"
  if ! podman push "${tag}"; then
    fail "Push failed: ${tag}"
    return 1
  fi

  podman tag "${tag}" "${dated_tag}"
  log "Pushing ${dated_tag}"
  if ! podman push "${dated_tag}"; then
    fail "Push failed: ${dated_tag}"
    return 1
  fi

  ok "Pushed: ${tag} and ${dated_tag}"
}

# ── nginx smoke test ──────────────────────────────────────────────────────────
smoke_nginx() {
  local tag="$1"
  log "Smoke testing nginx: ${tag}"
  local passed=0

  if podman run --rm "${tag}" nginx -t 2>&1 | grep -q "test is successful"; then
    ok "nginx -t: config valid"
  else
    fail "nginx -t: config invalid"
    (( passed++ )) || true
  fi

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

  local ver
  ver=$(podman run --rm "${tag}" php -v | head -1)
  ok "PHP: ${ver}"

  # sodium is built-in so won't appear in php -m; skip it
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

  if podman run --rm "${tag}" wp --info --allow-root &>/dev/null; then
    ok "WP-CLI: OK"
  else
    fail "WP-CLI: check failed"
    (( passed++ )) || true
  fi

  local cver
  if cver=$(podman run --rm "${tag}" composer --version 2>/dev/null); then
    ok "Composer: ${cver}"
  else
    fail "Composer: check failed"
    (( passed++ )) || true
  fi

  return "${passed}"
}

# ── SFTP smoke test ───────────────────────────────────────────────────────────
smoke_sftp() {
  local tag="$1"
  log "Smoke testing sftp: ${tag}"
  local passed=0

  if podman run --rm --entrypoint sshd "${tag}" -V 2>&1 | grep -qi "openssh"; then
    ok "sshd: OK"
  else
    fail "sshd: check failed"
    (( passed++ )) || true
  fi

  return "${passed}"
}

# ── fail2ban smoke test ───────────────────────────────────────────────────────
smoke_fail2ban() {
  local tag="$1"
  log "Smoke testing fail2ban: ${tag}"
  local passed=0

  local ver
  if ver=$(podman run --rm --entrypoint fail2ban-client "${tag}" --version 2>&1); then
    ok "fail2ban: ${ver}"
  else
    fail "fail2ban: check failed"
    (( passed++ )) || true
  fi

  return "${passed}"
}

# ── Build + smoke + optional push for a single image ─────────────────────────
# Usage: run_image <key> <label> <context> <smoke_fn> <full_tag> <dated_tag> [extra build args...]
run_image() {
  local key="$1"
  local label="$2"
  local context="$3"
  local smoke_fn="$4"
  local tag="$5"
  local dated_tag="$6"
  shift 6
  local extra_args=("$@")

  if do_build "${label}" "${context}" "${tag}" "${extra_args[@]}"; then
    if "${smoke_fn}" "${tag}"; then
      if [[ "${PUSH}" == true ]]; then
        if do_push "${tag}" "${dated_tag}"; then
          RESULTS["${key}"]="PASS"
        else
          RESULTS["${key}"]="PUSH_FAIL"
        fi
      else
        RESULTS["${key}"]="PASS"
      fi
    else
      RESULTS["${key}"]="SMOKE_FAIL"
    fi
  else
    RESULTS["${key}"]="BUILD_FAIL"
  fi

  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
preflight

# nginx — resolve versions first, then pass them all as build args
resolve_nginx_versions

run_image "nginx" "nginx" "nginx" \
    smoke_nginx \
    "ghcr.io/kpirnie/nginx:${TAG_SUFFIX}" \
    "ghcr.io/kpirnie/nginx:${TAG_SUFFIX}-${BUILD_DATE}" \
    "NGINX_VERSION=${NGINX_VERSION}"               \
    "OPENSSL_VERSION=${OPENSSL_VERSION}"           \
    "HEADERS_MORE_VERSION=${HEADERS_MORE_VERSION}" \
    "GEOIP2_VERSION=${GEOIP2_VERSION}"             \
    "NJS_VERSION=${NJS_VERSION}"

# PHP versions — PECL resolves extension versions at build time automatically
PHP_VERSIONS=("8.2" "8.3" "8.4" "8.5")

for ver in "${PHP_VERSIONS[@]}"; do
  run_image "php-${ver}" "php ${ver}" "php" \
      smoke_php \
      "ghcr.io/kpirnie/php:${ver}-${TAG_SUFFIX}" \
      "ghcr.io/kpirnie/php:${ver}-${TAG_SUFFIX}-${BUILD_DATE}" \
      "PHP_VERSION=${ver}"
done

run_image "sftp" "sftp" "sftp" \
    smoke_sftp \
    "ghcr.io/kpirnie/sftp:${TAG_SUFFIX}" \
    "ghcr.io/kpirnie/sftp:${TAG_SUFFIX}-${BUILD_DATE}"

run_image "fail2ban" "fail2ban" "fail2ban" \
    smoke_fail2ban \
    "ghcr.io/kpirnie/fail2ban:${TAG_SUFFIX}" \
    "ghcr.io/kpirnie/fail2ban:${TAG_SUFFIX}-${BUILD_DATE}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}──────────────────────────────────────────${NC}"
echo -e "${BOLD}  Build Summary${NC}"
echo -e "${BOLD}──────────────────────────────────────────${NC}"

OVERALL=0
for key in nginx php-8.2 php-8.3 php-8.4 php-8.5 sftp fail2ban; do
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

if [[ "${PUSH}" == true ]]; then
  warn "Images tagged ':latest' and ':latest-${BUILD_DATE}' have been pushed to GHCR."
else
  warn "Local images are tagged with ':local' and have not been pushed."
  warn "To push: ./build.sh --push"
  warn "To clean up: podman images | grep ':local' | awk '{print \$3}' | xargs podman rmi"
fi

exit "${OVERALL}"
