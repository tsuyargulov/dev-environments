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

> **Brand-new Mac?** If Homebrew / Node / Docker aren't installed yet, run the one-time
> `./bootstrap.sh` *before* `install.sh` — see [New machine](#new-machine-from-a-factory-fresh-mac).

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

### GitHub authentication

`GIT_TOKEN` is used **when a devcontainer is created**. On first start, the container fetches your
project repo into `/workspace` — cloned over HTTPS, authenticated with `GIT_TOKEN` supplied by a
git credential helper, so the token is **never written to disk** (not in the clone URL, not in
`.git/config`).

Create the token at GitHub → **Settings → Developer settings → Personal access tokens**, then set
it as `GIT_TOKEN`:

- **Fine-grained** (recommended): limit repository access to the repos you'll clone;
  **Contents: Read-only** (or Read/write if you'll also push from inside containers).
- or a **classic** token with the `repo` scope.

`GIT_USER_NAME` / `GIT_USER_EMAIL` set the identity for commits made *inside* containers. For the
email, prefer your GitHub **noreply address** (`<id>+<username>@users.noreply.github.com`, shown
under Settings → Emails when *"Keep my email addresses private"* is enabled) so those commits
don't expose your real address.

> **Different from publishing your own code.** Pushing commits to a Git host — e.g. committing a
> project to your own repo — is *host-side* git auth (a PAT over HTTPS or an SSH key, plus your
> host `git config` identity). That does **not** use `GIT_TOKEN`; `GIT_TOKEN` only governs
> fetching project repos into containers at creation time.

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
as sibling containers.

Quick start (the factory panel on its own — no auth):

```bash
cd factory-ui
uv venv && uv pip install flask     # Flask is the only dependency
.venv/bin/python app.py             # → http://localhost:5001
```

For the optional Keycloak sign-in + AWS STS demo (and full details), see
**[factory-ui/README.md](factory-ui/README.md)**.

---

## New machine (from a factory-fresh Mac)

The uncommon path — a Mac with no Homebrew / Node / Docker yet. `bootstrap.sh` installs the
OS-level prerequisites; day-to-day you only need `install.sh`.

```bash
# 1. Command Line Tools (gives you git) — accept the dialog it opens
xcode-select --install

# 2. Clone (public repo — no auth needed)
git clone https://github.com/tsuyargulov/dev-environments.git ~/.devenv
cd ~/.devenv

# 3. Prerequisites: Homebrew, Node, Docker Desktop, an SSH key
./bootstrap.sh
#    then in Docker Desktop: accept terms + set Settings → Resources → Memory

# 4. Install the tool
./install.sh

# 5. Create a GitHub PAT and set GIT_TOKEN / GIT_USER_* in your shell profile
#    (the install output shows the exact lines)

# 6. New shell, then verify + first project
devenv templates
devenv new demo --template python && devenv start demo && ssh demo
```

A fresh Mac defaults to **zsh**, so the scripts write `~/.zshrc`; this is auto-detected. To match
a bash setup instead, run `chsh -s /bin/bash` before step 3.

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
