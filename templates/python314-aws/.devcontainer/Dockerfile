# Base image: all Microsoft devcontainer images (base, python, node, golang, etc.) provide
# a default non-root user 'vscode'. If you switch to a non-Microsoft base (e.g. python:3.12-slim,
# ubuntu:24.04) you must create the user manually and update all 'vscode' references below.
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# SSH server
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# SSH host keys directory
RUN mkdir -p /var/run/sshd

# dev user SSH access
RUN mkdir -p /home/vscode/.ssh

ARG SSH_PUBKEY
RUN echo "$SSH_PUBKEY" > /home/vscode/.ssh/authorized_keys \
    && chown -R vscode:vscode /home/vscode/.ssh \
    && chmod 700 /home/vscode/.ssh \
    && chmod 600 /home/vscode/.ssh/authorized_keys

# passwordless sudo for sshd
RUN echo "vscode ALL=(root) NOPASSWD: /usr/sbin/sshd, /usr/bin/ssh-keygen" >> /etc/sudoers

EXPOSE 22