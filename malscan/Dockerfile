# latest alpine
FROM docker.io/library/alpine:latest

# clamav is maldet's scan engine, and maldet's scripts expect the gnu userland over busybox
RUN apk add --no-cache bash clamav clamav-libunrar coreutils curl file findutils gawk grep perl sed tar tzdata util-linux wget

# freshclam runs as root against a bind-mounted database directory
RUN printf 'DatabaseDirectory /var/lib/clamav\nDatabaseOwner root\nDatabaseMirror database.clamav.net\n' > /etc/clamav/freshclam.conf

# install maldet; its installer drops cron files, so the directories must exist,
# and its trailing signature update may fail without failing the install
RUN mkdir -p /tmp/lmd /etc/cron.d /etc/cron.daily /etc/cron.weekly && \
    wget -qO- https://github.com/rfxn/linux-malware-detect/archive/refs/heads/master.tar.gz | tar -xz -C /tmp/lmd --strip-components=1 && \
    cd /tmp/lmd && (./install.sh || true) && \
    test -x /usr/local/maldetect/maldet && \
    rm -rf /tmp/lmd /etc/cron.d/maldet* /etc/cron.daily/maldet /etc/cron.weekly/maldet-watchdog

# report only: never quarantine, never self-update (the nightly rebuild does that),
# scan root-owned files (rootless podman maps the site owner to root), and let
# clamscan evaluate maldet's yara rules
RUN sed -i \
    -e 's/^email_alert=.*/email_alert="0"/' \
    -e 's/^autoupdate_version=.*/autoupdate_version="0"/' \
    -e 's/^sigup_interval=.*/sigup_interval="0"/' \
    -e 's/^cron_daily_scan=.*/cron_daily_scan="0"/' \
    -e 's/^scan_clamscan=.*/scan_clamscan="1"/' \
    -e 's/^scan_yara=.*/scan_yara="0"/' \
    -e 's/^scan_ignore_root=.*/scan_ignore_root="0"/' \
    -e 's/^scan_max_depth=.*/scan_max_depth="30"/' \
    -e 's/^quarantine_hits=.*/quarantine_hits="0"/' \
    -e 's/^quarantine_clean=.*/quarantine_clean="0"/' \
    -e 's/^quarantine_on_error=.*/quarantine_on_error="0"/' \
    /usr/local/maldetect/conf.maldet

# bake current signatures as the seed for empty persisted volumes; a rate-limited
# freshclam here is not fatal since every run updates before scanning
RUN (freshclam --stdout || echo "freshclam failed at build, runtime update will fill the database") && \
    (/usr/local/maldetect/maldet -u || true) && \
    mkdir -p /opt/malscan/seed/clamav /opt/malscan/seed/maldet && \
    mv /var/lib/clamav/* /opt/malscan/seed/clamav/ 2>/dev/null; \
    cp -a /usr/local/maldetect/sigs/. /opt/malscan/seed/maldet/

# copy the entrypoint script to the container
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# persisted signature stores; the site's html directory is mounted read-only at /scan
VOLUME ["/var/lib/clamav", "/usr/local/maldetect/sigs"]

# set the entrypoint to the script that updates, scans, and reports
ENTRYPOINT ["/entrypoint.sh"]
