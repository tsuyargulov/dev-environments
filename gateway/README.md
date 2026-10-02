# gateway — single-port SSH reverse proxy (sshpiper)

Every devcontainer is reached through **one** SSH gateway on `localhost:2200` instead of a
published port per container. sshpiper routes by the **username** of the connection:
`ssh <project>` → the container labelled `sshpiper.username=<project>`.

Managed by the CLI:

```bash
devenv gateway up        # start sshpiper + docker-socket-proxy (+ create the devenv-net network)
devenv gateway status
devenv gateway down
```

`devenv start <project>` brings the gateway up automatically and writes a `~/.ssh/config` entry
(`Host <project>` → `localhost:2200`, `User <project>`), so you just `ssh <project>`.

## Routing + auth (two legs)

```
you ──(your key, downstream)──▶ sshpiper :2200 ──(gateway key, upstream)──▶ container sshd
     verified via sshpiper.authorized_keys label   routed by sshpiper.username=<project>
```

- **Downstream** (you → sshpiper): your public key, carried in the container's
  `sshpiper.authorized_keys` label, authenticates you.
- **Upstream** (sshpiper → container): sshpiper logs in as `vscode` using the **gateway keypair**;
  the container's `authorized_keys` trusts the gateway's public key.
- devenv stamps each project's container with the `sshpiper.*` labels and joins it to `devenv-net`.

## Security

sshpiper never touches the raw Docker socket or runs as root. A **docker-socket-proxy** holds the
socket and exposes only read-only container listing (`CONTAINERS=1`) over an internal TCP API, so
even a compromised sshpiper can't create or exec containers. The raw-socket power is concentrated
in that tiny, non-exposed proxy. (Production hardening beyond this — rootless Docker/Podman, or
Kubernetes RBAC — would remove the "socket = host root" exposure entirely.)

> **Not for internet exposure as-is.** This posture is for a local, single-user machine.

## Files

- `compose.yml` — `sshpiper` + `docker-socket-proxy` (plus a `validation`-profile throwaway target)
- `setup.sh`, `.env`, `keys/` — the local gateway keypair (generated; gitignored)

## Standalone routing check (optional)

Re-validate routing without any devcontainer, using the throwaway target behind the `validation`
profile:

```bash
./setup.sh && docker compose --profile validation up -d
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null test@localhost -p 2200 'echo OK; hostname'
docker compose --profile validation down
```
