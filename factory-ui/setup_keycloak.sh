#!/usr/bin/env bash
# Idempotent Keycloak bootstrap for the devenv factory auth demo.
# Creates a realm, a confidential OIDC client (auth-code flow), and a test user,
# then writes auth_config.json (with the client secret) for the Flask app.
#
# Requires: Keycloak up at :8080 (docker compose up -d), admin/admin, python3.
# Re-runnable: existing realm/client/user are left in place.
set -euo pipefail

KC="${KC_URL:-http://localhost:8080}"
REALM="${REALM:-devenv}"
CLIENT="${CLIENT:-devenv-factory}"
APP="${APP_URL:-http://localhost:5001}"
TEST_USER="${TEST_USER:-dev1}"
TEST_PASS="${TEST_PASS:-dev1}"
STS_ENDPOINT="${STS_ENDPOINT:-http://localhost:4566}"
ROLE_ARN="${ROLE_ARN:-arn:aws:iam::000000000000:role/dev-access}"
OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/auth_config.json"

jqpy() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }
info() { echo "▸ $*"; }

# 0. wait for Keycloak to be ready (it may still be booting after `compose up -d`)
info "waiting for Keycloak at $KC…"
for i in $(seq 1 30); do
  curl -sf "$KC/realms/master/.well-known/openid-configuration" >/dev/null 2>&1 && break
  [ "$i" = 30 ] && { echo "error: Keycloak not responding at $KC after ~60s (still booting?)"; exit 1; }
  sleep 2
done

# 1. admin token (master realm)
info "getting admin token…"
RESP=$(curl -s -X POST "$KC/realms/master/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=admin-cli -d username=admin -d password=admin)
TOKEN=$(printf '%s' "$RESP" | python3 -c "import sys,json
try: print(json.load(sys.stdin).get('access_token',''))
except Exception: print('')")
[ -n "$TOKEN" ] || { echo "error: admin token fetch failed — is admin/admin valid & Keycloak ready?"; echo "response: $RESP"; exit 1; }
AUTH=(-H "Authorization: Bearer $TOKEN")

# 2. realm
if curl -s -o /dev/null -w "%{http_code}" "${AUTH[@]}" "$KC/admin/realms/$REALM" | grep -q 200; then
  info "realm '$REALM' already exists"
else
  info "creating realm '$REALM'"
  curl -s "${AUTH[@]}" -X POST "$KC/admin/realms" -H "Content-Type: application/json" \
    -d "{\"realm\":\"$REALM\",\"enabled\":true}" >/dev/null
fi

# 2b. realm branding: display name (shown on the login form) + custom login theme
info "applying branding (displayName=Qbank, loginTheme=qbank)"
curl -s "${AUTH[@]}" -X PUT "$KC/admin/realms/$REALM" -H "Content-Type: application/json" \
  -d "{\"realm\":\"$REALM\",\"displayName\":\"Qbank\",\"displayNameHtml\":\"<b>Qbank</b>\",\"loginTheme\":\"qbank\"}" >/dev/null

# 3. client (confidential, standard/auth-code flow)
CLIENT_UUID=$(curl -s "${AUTH[@]}" "$KC/admin/realms/$REALM/clients?clientId=$CLIENT" \
  | jqpy "d[0]['id'] if d else ''")
if [ -z "$CLIENT_UUID" ]; then
  info "creating client '$CLIENT'"
  curl -s "${AUTH[@]}" -X POST "$KC/admin/realms/$REALM/clients" -H "Content-Type: application/json" -d "{
    \"clientId\":\"$CLIENT\",
    \"enabled\":true,
    \"protocol\":\"openid-connect\",
    \"publicClient\":false,
    \"standardFlowEnabled\":true,
    \"directAccessGrantsEnabled\":false,
    \"redirectUris\":[\"$APP/*\"],
    \"webOrigins\":[\"$APP\"]
  }" >/dev/null
  CLIENT_UUID=$(curl -s "${AUTH[@]}" "$KC/admin/realms/$REALM/clients?clientId=$CLIENT" | jqpy "d[0]['id']")
else
  info "client '$CLIENT' already exists"
fi

# 4. client secret
SECRET=$(curl -s "${AUTH[@]}" "$KC/admin/realms/$REALM/clients/$CLIENT_UUID/client-secret" \
  | jqpy "d.get('value','')")

# 5. test user
USER_ID=$(curl -s "${AUTH[@]}" "$KC/admin/realms/$REALM/users?username=$TEST_USER&exact=true" \
  | jqpy "d[0]['id'] if d else ''")
if [ -z "$USER_ID" ]; then
  info "creating user '$TEST_USER'"
  curl -s "${AUTH[@]}" -X POST "$KC/admin/realms/$REALM/users" -H "Content-Type: application/json" -d "{
    \"username\":\"$TEST_USER\",\"enabled\":true,\"emailVerified\":true,
    \"email\":\"$TEST_USER@example.com\",\"firstName\":\"Dev\",\"lastName\":\"One\",
    \"credentials\":[{\"type\":\"password\",\"value\":\"$TEST_PASS\",\"temporary\":false}]
  }" >/dev/null
else
  info "user '$TEST_USER' already exists"
fi

# 6. write app config (client secret lives here — gitignored)
cat > "$OUT" <<JSON
{
  "kc_url": "$KC",
  "realm": "$REALM",
  "client_id": "$CLIENT",
  "client_secret": "$SECRET",
  "redirect_uri": "$APP/callback",
  "sts_endpoint": "$STS_ENDPOINT",
  "role_arn": "$ROLE_ARN"
}
JSON

info "wrote $OUT"
echo
echo "  realm:   $REALM"
echo "  client:  $CLIENT (confidential, auth-code)"
echo "  user:    $TEST_USER / $TEST_PASS"
echo
echo "Restart the Flask app if it was already running, then open $APP"
