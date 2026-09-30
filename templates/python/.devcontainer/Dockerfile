# Prebuilt Python devcontainer image — ships Python 3.12 already compiled, so builds do
# NOT pay the slow from-source CPython compile the python feature does (esp. on arm64).
# Like all Microsoft devcontainer images it provides the non-root 'vscode' user; a
# non-Microsoft base would need the user created manually and every 'vscode' ref updated.
FROM mcr.microsoft.com/devcontainers/python:1-3.12-bookworm

# SSH server. Drop the pre-baked yarn apt repo first: this image ships
# /etc/apt/sources.list.d/yarn* whose signing key is expired, which otherwise
# fails `apt-get update` (NO_PUBKEY). We don't need yarn in a Python container.
RUN rm -f /etc/apt/sources.list.d/yarn* \
    && apt-get update && apt-get install -y --no-install-recommends \
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