"""
devenv factory — lightweight web UI over the personal `devenv` devcontainer CLI,
with a Keycloak login gate and an AWS STS (LocalStack) assume-role panel.

Runs on the host (needs access to ~/.devenv, docker, and the ~/dev / ~/projects trees).

Auth: OIDC Authorization Code flow against Keycloak. A separate /login page gates
the factory panel. After sign-in, the STS panel exchanges the Keycloak ID token for
temporary credentials via assume-role-with-web-identity (LocalStack). Stdlib only.
"""
import base64
import json
import os
import re
import secrets
import shutil
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from flask import Flask, Response, jsonify, redirect, request, send_from_directory, session

HOME = Path.home()
DEVENV_HOME = Path(os.environ.get("DEVENV_HOME", HOME / ".devenv"))
TEMPLATES_DIR = DEVENV_HOME / "templates"
PROJECTS_DIR = DEVENV_HOME / "projects"
DEVENV_BIN = str(DEVENV_HOME / "bin" / "devenv")
WORKSPACES_DIR = Path(os.environ.get("DEVENV_WORKSPACES", HOME / "dev"))
CONFIG_PATH = Path(__file__).parent / "auth_config.json"
STS_TTL = int(os.environ.get("STS_TTL", "60"))  # demo: 1-minute STS credentials

DOCKER_BIN = shutil.which("docker") or str(HOME / ".docker" / "bin" / "docker")

CHILD_ENV = os.environ.copy()
CHILD_ENV["PATH"] = os.pathsep.join([
    str(HOME / ".docker" / "bin"),
    str(HOME / ".local" / "bin"),
    str(DEVENV_HOME / "bin"),
    CHILD_ENV.get("PATH", ""),
])

NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")

ACTIONS: dict[str, dict] = {}
ACTIONS_LOCK = threading.Lock()

app = Flask(__name__, static_folder=None)
HERE = Path(__file__).parent


def _stable_secret():
    """Persist the session-signing key so restarts don't invalidate live sessions
    (a changing key silently breaks the OIDC state check across a restart)."""
    env = os.environ.get("FLASK_SECRET")
    if env:
        return env
    f = HERE / ".flask_secret"
    if f.exists():
        return f.read_text().strip()
    s = secrets.token_hex(32)
    try:
        f.write_text(s)
    except Exception:
        pass
    return s


app.secret_key = _stable_secret()
app.config.update(SESSION_COOKIE_SAMESITE="Lax", SESSION_COOKIE_HTTPONLY=True)


# ── auth config / helpers ────────────────────────────────────────────────────

def load_auth():
    try:
        return json.loads(CONFIG_PATH.read_text())
    except Exception:
        return None


def issuer(cfg):
    return f"{cfg['kc_url']}/realms/{cfg['realm']}"


def authed():
    return bool(session.get("id_token"))


def post_form(url, data):
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(
        url, data=body, method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:  # noqa: BLE001
        return 0, str(e)


def jwt_payload(token):
    try:
        p = token.split(".")[1]
        p += "=" * (-len(p) % 4)
        return json.loads(base64.urlsafe_b64decode(p))
    except Exception:
        return {}


def xml_tag(name, s):
    m = re.search(rf"<{name}>(.*?)</{name}>", s, re.S)
    return m.group(1) if m else None


def mint_sts():
    """Assume role via web identity using the Keycloak ID token, into session['sts'].
    Returns (ok, payload_or_error). Credentials are demo-scoped to STS_TTL seconds so
    expiry can be shown live. The raw access key is intentionally NOT surfaced."""
    cfg = load_auth()
    if not cfg or not session.get("id_token"):
        return False, "not signed in"
    status, xml = post_form(cfg["sts_endpoint"] + "/", {
        "Action": "AssumeRoleWithWebIdentity",
        "RoleArn": cfg["role_arn"],
        "RoleSessionName": session.get("user", "dev"),
        "WebIdentityToken": session["id_token"],
        "DurationSeconds": str(STS_TTL),
        "Version": "2011-06-15",
    })
    if not xml_tag("AccessKeyId", xml):
        return False, xml_tag("Message", xml) or f"STS error (HTTP {status})"
    now = time.time()
    session["sts"] = {
        "arn": xml_tag("Arn", xml),
        "minted_at": now,
        "expires_at": now + STS_TTL,
        "ttl": STS_TTL,
    }
    return True, session["sts"]


# ── factory data gathering ───────────────────────────────────────────────────

def list_templates():
    if not TEMPLATES_DIR.is_dir():
        return []
    return sorted(p.name for p in TEMPLATES_DIR.iterdir()
                  if p.is_dir() and (p / ".devcontainer").is_dir())


def parse_config(cfg):
    data = {}
    for line in cfg.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        data[key.strip()] = val.strip().strip('"').strip("'")
    return data


def docker_running(workspace):
    if not workspace:
        return False
    try:
        out = subprocess.run(
            [DOCKER_BIN, "ps", "-q", "--filter",
             f"label=devcontainer.local_folder={workspace}"],
            capture_output=True, text=True, env=CHILD_ENV, timeout=10,
        )
        return bool(out.stdout.strip())
    except Exception:
        return False


def list_projects():
    projects = []
    if not PROJECTS_DIR.is_dir():
        return projects
    for d in sorted(PROJECTS_DIR.iterdir()):
        cfg = d / "config.env"
        if not cfg.is_file():
            continue
        c = parse_config(cfg)
        name = c.get("PROJECT_NAME", d.name)
        workspace = c.get("WORKSPACE", str(WORKSPACES_DIR / name))
        with ACTIONS_LOCK:
            a = ACTIONS.get(name)
            action = {"action": a["action"], "state": a["state"]} if a else None
        projects.append({
            "name": name,
            "template": c.get("TEMPLATE", "?"),
            "branch": c.get("GIT_BRANCH", ""),
            "repo": c.get("GIT_REPO", ""),
            "workspace": workspace,
            "running": docker_running(workspace),
            "action": action,
        })
    return projects


def get_state():
    return {"templates": list_templates(), "projects": list_projects()}


def run_devenv_bg(name, action, args):
    """Run a devenv command in the background, streaming its combined output
    line-by-line into ACTIONS[name]['log'] so the UI can live-tail it."""
    with ACTIONS_LOCK:
        ACTIONS[name] = {"action": action, "state": "running", "log": ""}

    def append(text):
        with ACTIONS_LOCK:
            e = ACTIONS.get(name)
            if e is not None:
                e["log"] = (e["log"] + text)[-200000:]  # cap buffer

    def worker():
        try:
            p = subprocess.Popen(
                [DEVENV_BIN, *args], stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True, bufsize=1, env=CHILD_ENV,
            )
            for line in p.stdout:
                append(line)
            p.wait()
            state = "done" if p.returncode == 0 else "error"
        except Exception as exc:  # noqa: BLE001
            append(f"\n[error] {exc}\n")
            state = "error"
        with ACTIONS_LOCK:
            e = ACTIONS.get(name)
            if e is not None:
                e["state"] = state

    threading.Thread(target=worker, daemon=True).start()


# ── page routes + login gate ─────────────────────────────────────────────────

@app.get("/")
def index():
    if load_auth() and not authed():
        return redirect("/login")
    return send_from_directory(HERE, "index.html")


@app.get("/login")
def login_page():
    if authed():
        return redirect("/")
    return send_from_directory(HERE, "login.html")


@app.get("/auth/login")
def auth_login():
    cfg = load_auth()
    if not cfg:
        return redirect("/login?error=Keycloak+not+configured+-+run+setup_keycloak.sh")
    state = secrets.token_urlsafe(24)
    session["oauth_state"] = state
    params = urllib.parse.urlencode({
        "client_id": cfg["client_id"],
        "response_type": "code",
        "scope": "openid profile email",
        "redirect_uri": cfg["redirect_uri"],
        "state": state,
        # Force Keycloak to show its login form even if an SSO session exists,
        # so logout → sign-in reliably re-prompts (good for the demo).
        "prompt": "login",
    })
    return redirect(f"{issuer(cfg)}/protocol/openid-connect/auth?{params}")


@app.get("/callback")
def callback():
    cfg = load_auth()
    if not cfg:
        return redirect("/login?error=not+configured")
    saved = session.pop("oauth_state", None)
    if saved is None:
        return redirect("/login?error=" + urllib.parse.quote(
            "session cookie not returned — try again (or use a normal, non-incognito window)"))
    if request.args.get("state") != saved:
        return redirect("/login?error=state+mismatch")
    code = request.args.get("code")
    if not code:
        err = request.args.get("error_description", "no code returned")
        return redirect(f"/login?error={urllib.parse.quote(err)}")
    status, body = post_form(f"{issuer(cfg)}/protocol/openid-connect/token", {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": cfg["redirect_uri"],
        "client_id": cfg["client_id"],
        "client_secret": cfg["client_secret"],
    })
    if status != 200:
        return redirect(f"/login?error={urllib.parse.quote('token exchange failed')}")
    tok = json.loads(body)
    session["id_token"] = tok["id_token"]
    claims = jwt_payload(tok["id_token"])
    session["user"] = claims.get("preferred_username") or claims.get("email") or "user"
    session.pop("sts", None)
    mint_sts()  # auto-issue STS credentials immediately on sign-in (best-effort)
    return redirect("/")


@app.get("/logout")
def logout():
    session.clear()
    return redirect("/login")


# ── api ──────────────────────────────────────────────────────────────────────

@app.get("/api/session")
def api_session():
    return jsonify({
        "auth_configured": bool(load_auth()),
        "authenticated": authed(),
        "user": session.get("user"),
        "sts": session.get("sts"),
    })


@app.post("/api/sts")
def api_sts():
    """Issue/refresh temporary credentials via assume-role-with-web-identity."""
    if not load_auth():
        return jsonify(error="Auth not configured"), 400
    if not authed():
        return jsonify(error="Not signed in — the token comes from your Keycloak session"), 401
    ok, res = mint_sts()
    if not ok:
        return jsonify(error=res), 502
    return jsonify(ok=True, sts=res)


@app.get("/api/state")
def api_state():
    if load_auth() and not authed():
        return jsonify(error="Not signed in"), 401
    return jsonify(get_state())


@app.post("/api/projects")
def api_create():
    if load_auth() and not authed():
        return jsonify(error="Not signed in"), 401
    body = request.get_json(force=True, silent=True) or {}
    name = (body.get("name") or "").strip()
    template = (body.get("template") or "").strip()
    repo = (body.get("repo") or "").strip()
    branch = (body.get("branch") or "").strip()

    if not NAME_RE.match(name):
        return jsonify(error="Name may only contain letters, digits, . _ -"), 400
    if template not in list_templates():
        return jsonify(error=f"Unknown template '{template}'"), 400
    if not repo:
        return jsonify(error="Git repo URL is required"), 400
    if (WORKSPACES_DIR / name).exists():
        return jsonify(error=f"~/dev/{name} already exists — pick another name"), 409

    try:
        p = subprocess.run(
            [DEVENV_BIN, "new", name, "--template", template],
            input=f"{repo}\n{branch}\n", capture_output=True, text=True,
            env=CHILD_ENV, timeout=120,
        )
    except Exception as exc:  # noqa: BLE001
        return jsonify(error=str(exc)), 500
    if p.returncode != 0:
        return jsonify(error=(p.stdout + p.stderr).strip()), 500
    return jsonify(ok=True, output=(p.stdout + p.stderr).strip())


@app.post("/api/projects/<name>/start")
def api_start(name):
    if load_auth() and not authed():
        return jsonify(error="Not signed in"), 401
    if not NAME_RE.match(name) or not (PROJECTS_DIR / name / "config.env").is_file():
        return jsonify(error="Unknown project"), 404
    run_devenv_bg(name, "start", ["start", name])
    return jsonify(ok=True, state="starting"), 202


@app.post("/api/projects/<name>/stop")
def api_stop(name):
    if load_auth() and not authed():
        return jsonify(error="Not signed in"), 401
    if not NAME_RE.match(name) or not (PROJECTS_DIR / name / "config.env").is_file():
        return jsonify(error="Unknown project"), 404
    run_devenv_bg(name, "stop", ["stop", name])
    return jsonify(ok=True, state="stopping"), 202


@app.post("/api/projects/<name>/delete")
def api_delete(name):
    """Delete a stopped project: its devenv registry entry, its checkout, and its
    generated .devcontainer. Refuses while the container is still running."""
    if load_auth() and not authed():
        return jsonify(error="Not signed in"), 401
    if name in (".", "..") or not NAME_RE.match(name):
        return jsonify(error="bad name"), 400
    cfg_dir = PROJECTS_DIR / name
    cfg_file = cfg_dir / "config.env"
    if not cfg_file.is_file():
        return jsonify(error="Unknown project"), 404

    c = parse_config(cfg_file)
    workspace = c.get("WORKSPACE", str(WORKSPACES_DIR / name))
    project_dir = c.get("PROJECT_DIR", str(HOME / "projects" / name))

    if docker_running(workspace):
        return jsonify(error="Stop the container before deleting"), 409

    # Remove each footprint dir, but only if it resolves strictly under its expected root.
    removed = []
    targets = [
        (cfg_dir, PROJECTS_DIR),
        (Path(project_dir), HOME / "projects"),
        (Path(workspace), WORKSPACES_DIR),
    ]
    for path, root in targets:
        try:
            rp = path.resolve()
            if str(rp).startswith(str(root.resolve()) + os.sep) and rp.exists():
                shutil.rmtree(rp)
                removed.append(str(rp))
        except Exception:  # noqa: BLE001
            pass

    with ACTIONS_LOCK:
        ACTIONS.pop(name, None)
    return jsonify(ok=True, removed=removed)


@app.get("/logs/<name>")
def logs_page(name):
    if load_auth() and not authed():
        return redirect("/login")
    return send_from_directory(HERE, "logs.html")


@app.get("/api/projects/<name>/logs")
def api_logs(name):
    """Server-Sent Events stream of a project's live action log."""
    if load_auth() and not authed():
        return jsonify(error="Not signed in"), 401
    if not NAME_RE.match(name):
        return jsonify(error="bad name"), 400

    def gen():
        idx = 0
        while True:
            with ACTIONS_LOCK:
                e = ACTIONS.get(name)
                log = e["log"] if e else ""
                state = e["state"] if e else None
            # emit whole lines as they arrive
            nl = log.find("\n", idx)
            while nl >= 0:
                yield f"data: {log[idx:nl]}\n\n"
                idx = nl + 1
                nl = log.find("\n", idx)
            if state in ("done", "error", None):
                if idx < len(log):                 # flush trailing partial line
                    yield f"data: {log[idx:]}\n\n"
                yield f"event: end\ndata: {state or 'none'}\n\n"
                return
            time.sleep(0.4)

    return Response(gen(), mimetype="text/event-stream",
                    headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "5001"))
    print(f"devenv factory → http://localhost:{port}")
    app.run(host="127.0.0.1", port=port, threaded=True)
