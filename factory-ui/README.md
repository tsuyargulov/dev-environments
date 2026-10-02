# factory-ui

A small Flask web app over the `devenv` templates: create / start / stop / delete devcontainers
and stream build logs from the browser, instead of the CLI. It also demonstrates a local auth
flow — sign in via **Keycloak** (an IdP stand-in), then mint temporary **AWS STS** credentials
against **LocalStack** using `assume-role-with-web-identity`.

Runs on the **host** (it shells out to `devenv`/`docker` and reads the `~/.devenv` tree), with
Keycloak and LocalStack as sibling containers.

## Run it

```bash
cd factory-ui

# 1. Python env (Flask is the only dependency)
uv venv && uv pip install flask

# 2. (optional) auth demo — start Keycloak and configure the realm/client/user
docker compose up -d                 # Keycloak on :8080
./setup_keycloak.sh                  # creates realm + client + user dev1/dev1, writes auth_config.json

# 3. start the app
.venv/bin/python app.py              # http://localhost:5001
```

If `auth_config.json` is absent, the login gate is disabled and the factory panel works on its
own. LocalStack (for the STS panel) is expected as a separate host sibling on `:4566`.

## Files

| File | Purpose |
|------|---------|
| `app.py` | Flask backend (factory actions, SSE log stream, OIDC login, STS) |
| `index.html` / `login.html` / `logs.html` | UI pages |
| `docker-compose.yml` | Keycloak (IdP mock) |
| `setup_keycloak.sh` | idempotent realm/client/user bootstrap |
| `themes/devenv/` | branded Keycloak login theme |

## Not committed (secrets)

`auth_config.json` (client secret), `.flask_secret`, and `.venv/` are gitignored — regenerated
locally by `setup_keycloak.sh` and the app.

## Caveats

- Single-user demo: sessions are client-side signed cookies; a server-side (Redis) store would
  be the multi-user enhancement.
- LocalStack's free tier does **not** cryptographically verify the Keycloak token, so the
  login → token → STS dependency is demonstrated structurally, not enforced.
