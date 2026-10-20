#!/bin/bash
# refreshes signatures, scans $SCAN_PATH with maldet driving clamscan and native
# yara, then prints maldet's json report; everything else goes to stderr so
# stdout carries only the report

set -uo pipefail

SCAN_PATH="${SCAN_PATH:-/scan}"
CLAM_DB=/var/lib/clamav
LMD_SIGS=/usr/local/maldetect/sigs
SEED=/opt/malscan/seed

# seed empty persisted volumes from the signatures baked into the image
if [ -z "$(ls -A "$CLAM_DB" 2>/dev/null)" ]; then
    cp -a "$SEED/clamav/." "$CLAM_DB/"
fi
if [ -z "$(ls -A "$LMD_SIGS" 2>/dev/null)" ]; then
    cp -a "$SEED/maldet/." "$LMD_SIGS/"
fi

# php-malware-finder rides along as a custom yara drop-in so maldet runs it through
# native yara; rewritten every run so it always points at the image's rules
mkdir -p "$LMD_SIGS/custom.yara.d"
printf 'include "/opt/pmf/php.yar"\n' > "$LMD_SIGS/custom.yara.d/pmf.yar"

# refresh signatures; a failed update falls back to what is already on disk
freshclam --stdout >&2 || echo "malscan: freshclam update failed, using existing signatures" >&2
/usr/local/maldetect/maldet -u >&2 || echo "malscan: maldet update failed, using existing signatures" >&2

# maldet exits 0 when clean and 2 on hits; anything else is a failed scan
/usr/local/maldetect/maldet -a "$SCAN_PATH" >&2
rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    echo "malscan: maldet scan failed with exit code $rc" >&2
    exit "$rc"
fi

# the only thing written to stdout
exec /usr/local/maldetect/maldet --json-report newest
