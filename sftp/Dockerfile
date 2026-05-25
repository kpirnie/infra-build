# latest alpine
FROM docker.io/library/alpine:latest

# Install OpenSSH server and shadow for user management
RUN apk add --no-cache openssh shadow && \
    ssh-keygen -A && \
    addgroup -S sftpusers && \
    mkdir -p /var/run/sshd

# copy the entrypoint script to the container
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# setup the default port for SSH
EXPOSE 22

# set the entrypoint to the script that will start the SSH server
ENTRYPOINT ["/entrypoint.sh"]
