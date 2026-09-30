# dev-environments

Spin up an isolated **devcontainer per project** from reusable templates, and connect to it
over SSH from VS Code or IntelliJ IDEA. Manage everything from a small CLI (`devenv`) or an
optional web **factory UI** — both driven by the same templates.

- One container per project, fully isolated toolchains.
- Your code lives on the host (bind-mounted), so it survives container rebuilds.
- Connect with `ssh <project>` — no port numbers to remember.

---

## Prerequisites

- **macOS** with **Docker Desktop** (running)
- **Node.js** (for `@devcontainers/cli`)
- **git**

## Install

```bash
git clone https://github.com/tsuyargulov/dev-environments.git ~/.devenv
cd ~/.devenv
./install.sh
```

`install.sh` checks prerequisites, installs `@devcontainers/cli`, adds `devenv` to your `PATH`,
and scaffolds the host environment variables you need to fill in:

```bash
export GIT_TOKEN=…            # GitHub token (repo scope) — used to clone private repos
export GIT_USER_EMAIL=…
export GIT_USER_NAME=…
```

Open a new shell (or `source ~/.bash_profile`) and verify:

```bash
devenv templates
```

---

## Repository structure

```
dev-environments/
├── bin/devenv                 # the CLI
├── templates/                 # devcontainer templates (copy-on-use)
│   ├── python/
│   ├── python314-aws/
│   ├── django-bff/
│   ├── terraform-aws/
│   ├── java21-gradle/
│   └── react-springboot-localstack/
├── factory-ui/                # optional web UI over the same templates
├── install.sh                 # bootstrap script
├── CLAUDE.md                  # project context / conventions
└── LICENSE
```

**Runtime directories** (created as you use it, never committed):

| Path | What |
|------|------|
| `~/.devenv/projects/<p>/config.env` | per-project config (port, repo, workspace) |
| `~/.devenv/projects/<p>/secrets.env` | tokens (never committed) |
| `~/dev/<p>/` | generated devcontainer config |
| `~/projects/<p>/` | the bind-mounted workspace (your cloned repo) |

---

## Commands

| Command | Does |
|---------|------|
| `devenv new <project> --template <t>` | scaffold a project from a template (prompts for repo URL + branch) |
| `devenv start <project>` | build + start the container, add a `~/.ssh/config` entry |
| `devenv stop <project>` | stop + remove the container, clean the SSH entry |
| `devenv ssh <project>` | open an SSH session (lands in `/workspace`) |
| `devenv list` | list projects and running status |
| `devenv templates` | list available templates |

---

## Quick start — create a devcontainer from a template

```bash
devenv new myapi --template python
#   Git repo URL: https://github.com/you/myapi.git
#   Branch (leave empty for default): main

devenv start myapi          # builds the image, clones your repo into /workspace
ssh myapi                   # you're now inside the container, in /workspace
```

`devenv new` auto-assigns a free SSH port and writes a `~/.ssh/config` alias, so you connect by
**name** (`ssh myapi`) — never a port number.

### More examples

**A Terraform sandbox (with a LocalStack sibling on the host):**
```bash
devenv new tf-lab --template terraform-aws
devenv start tf-lab && ssh tf-lab
# inside: terraform / tflint / aws-cli are ready
```

**A React + Spring Boot full-stack project (Azul Zulu 21 + Node):**
```bash
devenv new shop --template react-springboot-localstack
devenv start shop
```

---

## Available templates

| Template | For |
|----------|-----|
| `python` | Python (prebuilt image; fast builds) |
| `python314-aws` | Python 3.14 + aws-cli |
| `django-bff` | Django + Node, `uv`-managed deps reconciled on each start |
| `terraform-aws` | Terraform + tflint + terragrunt + aws-cli (LocalStack-friendly) |
| `java21-gradle` | Azul Zulu 21 + Gradle |
| `react-springboot-localstack` | Node + Azul Zulu 21 + Gradle + aws-cli, wired to LocalStack |

Add a new template by copying the closest one under `templates/`, adjusting its `features` and
extensions, and keeping the `{{PLACEHOLDER}}` tokens intact.

---

## Accessing app ports from your browser

Templates publish only the SSH port; app servers (Vite/Next.js on 3000, Spring Boot on 8080)
stay internal. Reach them with an SSH tunnel — `<project>` is the alias from `~/.ssh/config`:

```bash
ssh -fNL 3000:localhost:3000 <project>   # then open http://localhost:3000
#   -f background  -N no shell
```

Keep the same port on both sides (`3000:localhost:3000`) so dev-server HMR websockets work. In a
full-stack project, have the frontend proxy `/api` → `localhost:8080` internally so you only
forward one port and avoid CORS.

---

## Factory UI (optional)

`factory-ui/` is a small Flask web app that does everything the CLI does — list templates,
create / start / stop / delete projects, and stream build logs live — from the browser. It also
demonstrates an auth flow: sign in via a local **Keycloak** (an IdP stand-in), then mint
temporary **AWS STS** credentials against **LocalStack** via `assume-role-with-web-identity`.

It runs on the host (it needs Docker and the `~/.devenv` tree) alongside Keycloak and LocalStack
as sibling containers. See **[factory-ui/README.md](factory-ui/README.md)** to run it.

---

## Uninstall

```bash
./uninstall.sh            # reverses install: shell-profile block + ~/.ssh/config entries
./uninstall.sh --purge    # also offers to stop containers and remove runtime project configs
```

Every step shows a **FINDINGS** block (what's there now + the exact change) and asks before
applying — defaulting to *No*. It **never deletes your code**. Left for you to remove manually:

- workspaces `~/dev/<project>` and `~/projects/<project>` (your cloned repos)
- this repo clone (`rm -rf`)
- the devcontainer CLI (`npm uninstall -g @devcontainers/cli`)
- built images (`docker images | grep vsc-` → `docker rmi`)

## License

MIT — see [LICENSE](LICENSE).
