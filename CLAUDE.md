# dev-environments

Personal dev-environment manager for macOS. Creates an isolated devcontainer per
project from reusable templates, with SSH access from VS Code and IntelliJ IDEA.
Two front-ends share the same templates: the `devenv` CLI and an optional web
**factory UI**.

## Repository layout

- `bin/devenv` — CLI managing container lifecycle (new/start/stop/ssh/list/templates)
- `templates/` — devcontainer templates, copy-on-use per project
- `factory-ui/` — optional Flask web app over the same templates (+ Keycloak/STS auth mock)
- `install.sh` — bootstrap: prerequisites, PATH, host env vars

## Runtime directories (created at use time, never committed)

- `~/.devenv/projects/<project>/config.env` — per-project config (repo URL, branch, workspace)
- `~/dev/<project>/` — scaffolded devcontainer config (generated from a template)
- `~/projects/<project>/` — bind-mounted workspace (the cloned repo lives here)

`DEVENV_HOME` (default `~/.devenv`) locates templates + projects; `DEVENV_WORKSPACES`
(default `~/dev`) locates scaffolded configs. Both are honored by the CLI and the factory UI.

## Stack

- Docker Desktop — container runtime
- `@devcontainers/cli` — builds/runs devcontainer specs
- `mcr.microsoft.com/devcontainers/*` base images (provide the `vscode` user)
- devcontainer features — tool installation (python, java, node, aws-cli, terraform, …)

## Key design decisions

- **Copy-on-use templates** — `devenv new` copies a template; each project diverges independently.
- **Bind mount** — `~/projects/<project>` maps to `/workspace`; survives rebuilds.
- **SSH access via a single-port gateway (sshpiper)** — all containers are reached through a
  reverse proxy on `localhost:2200` that routes by username (`ssh <project>`); containers run
  `sshd` (started in `postStartCommand`) but publish no port. Their `authorized_keys` trusts the
  **gateway's** upstream key (baked via `ARG SSH_PUBKEY`); your key + the gateway private key ride
  as `sshpiper.*` container labels. Managed via `devenv gateway up/down/status`; a
  docker-socket-proxy gives sshpiper read-only container discovery (no raw socket / no root).
- **`postStartCommand` handles init** — sshd, git credentials, initial clone — because the
  devcontainer runtime overrides the image ENTRYPOINT.
  - **Exception — `django-bff`** splits the lifecycle as the spec intends: `postCreateCommand`
    provisions code + deps (clone → `uv sync`), `postStartCommand` only boots sshd. Since
    `devenv stop` does `docker rm`, each `start` recreates the container and reconciles deps to
    the lockfile.
- **Tooling via features**, not hand-rolled in the Dockerfile.
- **Git over HTTPS + token** — a credential helper injects `GIT_TOKEN` at runtime; the token is
  **never** embedded in the clone URL (it would persist in `.git/config` on the bind mount).
- **Host env vars** injected via `${localEnv:VAR}` — `GIT_TOKEN`, `GIT_USER_EMAIL`, `GIT_USER_NAME`
  must be set on the host.

## Templates

`python`, `python314-aws`, `django-bff`, `terraform-aws`, `java21-gradle`,
`react-springboot-localstack`. Each is `.devcontainer/{Dockerfile,devcontainer.json}` with
`{{PLACEHOLDER}}` tokens substituted at scaffold time.

## Conventions & gotchas (for contributors)

- Templates use these tokens: `{{PROJECT_NAME}}`, `{{GIT_REPO}}`, `{{GIT_BRANCH}}`,
  `{{PROJECT_DIR}}`, `{{GATEWAY_PUBKEY}}` (→ container authorized_keys), and
  `{{USER_PUBKEY_B64}}` / `{{GATEWAY_PRIVKEY_B64}}` (→ sshpiper labels). Never hardcode real values.
- Prefer a **prebuilt language image** over a feature that compiles from source (e.g. the python
  feature builds CPython from source on arm64 — slow; the `python` template uses a prebuilt image).
- Prebuilt Debian devcontainer images ship an expired **yarn apt repo** that breaks
  `apt-get update`; `rm -f /etc/apt/sources.list.d/yarn*` before it, or use the Ubuntu base.
- **No docker-in-docker.** If a container needs Docker-hosted services (LocalStack, Keycloak,
  Kafka), run them as **host sibling containers** reached via `host.docker.internal`.
- Copy-on-use means editing a template does **not** change already-scaffolded projects.

## Commands

```bash
devenv new <project> --template <t>   # scaffold project from template
devenv start <project>                # build + start container, update ~/.ssh/config
devenv stop <project>                 # stop container, clean ~/.ssh/config
devenv ssh <project>                  # open SSH session
devenv list                           # show projects + running status
devenv templates                      # list available templates
devenv gateway up|down|status         # manage the single-port SSH gateway
```
