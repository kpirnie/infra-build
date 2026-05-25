# latest alpine
FROM docker.io/library/alpine:latest

# add in the proper apps needed for fail2ban to work, and create the necessary directories for configuration and logging
RUN apk add --no-cache fail2ban ip6tables iptables tzdata && \
    mkdir -p /etc/fail2ban/jail.d /etc/fail2ban/filter.d /var/log/fail2ban

# fail2ban writes its socket and pid here
VOLUME ["/var/run/fail2ban"]

# fail2ban requires access to the host log files — mounted read-only at runtime
ENTRYPOINT ["fail2ban-client", "-f", "-x", "start"]
