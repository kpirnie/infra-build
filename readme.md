# Infra-Build

[![Build](https://img.shields.io/github/actions/workflow/status/kpirnie/infra-build/nginx.yml?branch=main&label=Build&logoColor=white&logo=github&labelColor=000&style=for-the-badge)](https://github.com/kpirnie/infra-build/actions/workflows/nginx.yml)
[![Issues](https://img.shields.io/github/issues/kpirnie/infra-build?style=for-the-badge&logo=github&color=006400&logoColor=white&labelColor=000)](https://github.com/kpirnie/infra-build/issues)
[![Last Commit](https://img.shields.io/github/last-commit/kpirnie/infra-build?style=for-the-badge&labelColor=000)](https://github.com/kpirnie/infra-build/commits/main)
[![License: MIT](https://img.shields.io/badge/License-MIT-orange.svg?style=for-the-badge&logo=opensourceinitiative&logoColor=white&labelColor=000)](LICENSE)
[![Kevin Pirnie](https://img.shields.io/badge/-KevinPirnie.com-000d2d?style=for-the-badge&labelColor=000&logoColor=white&logo=data:image/svg%2Bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSJ3aGl0ZSIgc3Ryb2tlLXdpZHRoPSIxLjgiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+CiAgPGNpcmNsZSBjeD0iMTIiIGN5PSIxMiIgcj0iMTAiLz4KICA8ZWxsaXBzZSBjeD0iMTIiIGN5PSIxMiIgcng9IjQuNSIgcnk9IjEwIi8+CiAgPGxpbmUgeDE9IjIiIHkxPSIxMiIgeDI9IjIyIiB5Mj0iMTIiLz4KICA8bGluZSB4MT0iNC41IiB5MT0iNi41IiB4Mj0iMTkuNSIgeTI9IjYuNSIvPgogIDxsaW5lIHgxPSI0LjUiIHkxPSIxNy41IiB4Mj0iMTkuNSIgeTI9IjE3LjUiLz4KPC9zdmc+Cg==)](https://kevinpirnie.com/)

Production-grade, security-hardened Docker/Podman images built from source on Alpine Linux. Rebuilt nightly via GitHub Actions and published to GHCR.

---

## Images

### nginx

```
ghcr.io/kpirnie/nginx:latest
ghcr.io/kpirnie/nginx:latest-YYYY-MM-DD
```

**Built with:**

| Feature | Detail |
|---|---|
| Base | `alpine:latest` |
| nginx | Mainline, compiled from source |
| TLS | [OpenSSL 4.x](https://github.com/openssl/openssl) — native QUIC support, statically linked |
| HTTP/3 | QUIC via `--with-http_v3_module` |
| HTTP/2 | `--with-http_v2_module` |
| Compression | Brotli (`ngx_brotli`), Zstd (`zstd-nginx-module`), gzip (built-in) |
| GeoIP | GeoIP2 (`ngx_http_geoip2_module`) — MaxMind databases must be volume-mounted |
| Headers | `headers-more-nginx-module` |
| Scripting | NJS (`njs`), LuaJIT ([OpenResty fork](https://github.com/openresty/luajit2)) |
| Image processing | `--with-http_image_filter_module` |
| Stream proxy | `--with-stream` + SSL + realip + ssl_preread |
| Arch | `linux/amd64`, `linux/arm64` |
| Runs as | root (master) → `nginx` UID 101 (workers) |

---

### PHP-FPM

```
ghcr.io/kpirnie/php:8.2-latest
ghcr.io/kpirnie/php:8.2-latest-YYYY-MM-DD

ghcr.io/kpirnie/php:8.3-latest
ghcr.io/kpirnie/php:8.4-latest
ghcr.io/kpirnie/php:8.5-latest
```

**Built with:**

| Feature | Detail |
|---|---|
| Base | `php:8.x-fpm-alpine` |
| Versions | 8.2 · 8.3 · 8.4 · 8.5 |
| Arch | `linux/amd64`, `linux/arm64` |
| Runs as | root (master) → `www-data` UID 82 (workers) |

**Extensions:**

`apcu` `bcmath` `calendar` `exif` `gd` `gettext` `igbinary` `imagick` `intl` `msgpack` `mysqli` `opcache` `pcntl` `pdo_mysql` `pdo_pgsql` `pgsql` `redis` `sodium` `sockets` `tidy` `uuid` `xsl` `yaml` `zip`

Plus all default extensions bundled in the official PHP Alpine image: `curl` `dom` `fileinfo` `iconv` `mbstring` `openssl` `pdo` `phar` `simplexml` `tokenizer` `xml` `xmlreader` `xmlwriter` `zlib` and others.

`redis` is compiled with `igbinary` and `msgpack` serializer support.

**Tools:** WP-CLI · Composer

---

## Configuration

Both images ship a minimal base config. Everything else is expected to be volume-mounted.

### nginx

| Mount | Purpose |
|---|---|
| `/etc/nginx/conf.d/` | HTTP site configs (`*.conf`) |
| `/etc/nginx/stream.d/` | Stream proxy configs (`*.conf`) |
| `/etc/nginx/sites-enabled/` | Alternative site config location |
| `/var/log/nginx/` | Access and error logs |
| `/path/to/GeoIP2/` | MaxMind `.mmdb` database files — point `geoip2` directives at your mount path |

### PHP-FPM

| Mount | Purpose |
|---|---|
| `/usr/local/etc/php/conf.d/` | `php.ini` override snippets (`*.ini`) |
| `/usr/local/etc/php-fpm.d/` | FPM pool override configs |
| `/var/log/php-fpm/` | FPM logs |

> **`disable_functions`** — empty by default. Add your own restrictions via a volume-mounted snippet in `/usr/local/etc/php/conf.d/`. Note that entries can only be added, not selectively removed — to change the list you must redeclare the entire directive.

---

## Usage

### Podman

```bash
# nginx
podman pull ghcr.io/kpirnie/nginx:latest

# PHP 8.4
podman pull ghcr.io/kpirnie/php:8.4-latest
```

### Example Compose (Podman / Docker)

```yaml
services:
  nginx:
    image: ghcr.io/kpirnie/nginx:latest
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"   # QUIC/HTTP3
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./geoip:/etc/nginx/geoip:ro
      - nginx_logs:/var/log/nginx

  php:
    image: ghcr.io/kpirnie/php:8.4-latest
    volumes:
      - ./app:/var/www/html:ro
      - ./php/conf.d:/usr/local/etc/php/conf.d:ro
      - php_logs:/var/log/php-fpm

volumes:
  nginx_logs:
  php_logs:
```

---

## Building Locally

Requires Podman with Buildah. Builds the native platform only (no emulation).

```bash
chmod +x build-local.sh
./build-local.sh
```

The script builds every image, runs smoke tests on each, and prints a summary. Local images are tagged `:local` and are not pushed anywhere.

**To clean up local images after testing:**
```bash
podman images | grep ':local' | awk '{print $3}' | xargs podman rmi
```

---

## Nightly Builds

Both images are rebuilt automatically at **02:00 UTC daily** via GitHub Actions. Builds are also triggered on any push to `main` that touches the relevant image directory.

The PHP workflow builds all four versions in parallel. If one version fails (e.g. a PECL extension not yet compatible with a new PHP release), the others complete normally.

---

## GeoIP2 Databases

The nginx image includes the GeoIP2 module but **does not bundle MaxMind databases** — MaxMind requires a free license key and the databases must be kept up to date independently.

1. Sign up at [maxmind.com](https://www.maxmind.com)
2. Download `GeoLite2-City.mmdb` and/or `GeoLite2-Country.mmdb`
3. Mount them into the container and reference the path in your nginx config:

```nginx
geoip2 /etc/nginx/geoip/GeoLite2-Country.mmdb {
    $geoip2_country_code country iso_code;
}
```

---

## Security Notes

- Both images use multi-stage builds; no build toolchain is present in the final image.
- nginx is compiled against OpenSSL 4.x (statically linked, native QUIC support) — no OpenSSL runtime dependency.
- All setuid/setgid bits are stripped from the final image filesystem.
- nginx workers and PHP-FPM workers run as unprivileged users (`nginx` UID 101, `www-data` UID 82).
- `server_tokens off` is set globally in nginx.
- `expose_php = Off` is set in `php.ini`.
- SSI and empty_gif modules are disabled in nginx.

---

## License

MIT — see [LICENSE](./LICENSE)
