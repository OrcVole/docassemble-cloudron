#!/bin/bash
# gate0.sh: gate 0 (install, health, first run) against a Cloudron install, scripted so every update
# re-runs it the same way. Prints one PASS/FAIL line per invariant and exits non-zero on any FAIL.
#
#   CLI=<cloudron CLI wrapper> APP=<app fqdn> DIGEST=sha256:<registry digest> test/gate0.sh
#
# CLI is the maintainer's wrapper for the target box (it must accept `exec --app`, `restart --app`
# and `logs --app`). Host-side digest comparison is optional: set PULLED=<digest seen on the host>.
set -uo pipefail
CLI="${CLI:?set CLI}"; APP="${APP:?set APP}"; DIGEST="${DIGEST:?set DIGEST}"
fail=0
pass() { echo "PASS  $*"; }
bad()  { echo "FAIL  $*"; fail=1; }
ex()   { $CLI exec --app "$APP" -- bash -c "$1"; }

# 1. Test what you ship: the box runs the digest under test.
if [ -n "${PULLED:-}" ]; then
    [ "$PULLED" = "$DIGEST" ] && pass "digest: pulled = registry (${DIGEST:7:12})" || bad "digest: pulled ${PULLED} != ${DIGEST}"
else
    echo "SKIP  digest: set PULLED to compare the host's RepoDigest"
fi

# 2. Health from outside, and robots.txt (field guide #316).
code=$(curl -s -o /dev/null -w '%{http_code}' "https://${APP}/healthz")
[ "$code" = 200 ] && pass "health: /healthz 200 from outside" || bad "health: /healthz ${code}"
root=$(curl -s -o /dev/null -w '%{http_code}' "https://${APP}/")
[[ "$root" =~ ^(200|302)$ ]] && pass "anonymous /: ${root} (not an error page)" || bad "anonymous /: ${root}"
robots=$(curl -s "https://${APP}/robots.txt" | tr -d '\r' | grep -v '^#' | tr '\n' ' ')
echo "$robots" | grep -q 'Disallow: /' && ! echo "$robots" | grep -qE 'Disallow: *$' \
    && pass "robots.txt disallows all: ${robots}" || bad "robots.txt: ${robots}"

# 3. Every supervised program up, not just the web process.
status=$(ex "supervisorctl status" 2>&1)
running=$(echo "$status" | grep -c RUNNING)
notok=$(echo "$status" | grep -v -E 'RUNNING|EXITED|STOPPED' | grep -v '^\s*$' || true)
for p in nginx uwsgi celery celerysingle websockets nltk unoserver; do
    echo "$status" | grep -qE "^${p} +RUNNING" || bad "program ${p} not RUNNING"
done
echo "$status" | grep -qE '^ready +EXITED' && pass "programs: ${running} RUNNING, ready EXITED (did its job)" || bad "ready program: $(echo "$status" | grep '^ready')"
[ -z "$notok" ] || bad "programs in a bad state: ${notok}"

# 4. Secrets: mode 600, cloudron:cloudron, and the same sha256 after a restart.
snap() { ex 'cd /app/data/.secrets && for f in *; do printf "%s %s %s\n" "$f" "$(stat -c "%a %U:%G" "$f")" "$(sha256sum < "$f" | cut -c1-16)"; done'; }
before=$(snap)
echo "$before" | awk '{print $2, $3}' | grep -v '^600 cloudron:cloudron$' >/dev/null \
    && bad "secret modes: $(echo "$before" | awk '{print $1, $2, $3}' | tr '\n' ';')" \
    || pass "secrets: $(echo "$before" | wc -l) files, all 600 cloudron:cloudron"
$CLI restart --app "$APP" >/dev/null 2>&1
for _ in $(seq 1 90); do [ "$(curl -s -o /dev/null -w '%{http_code}' "https://${APP}/healthz")" = 200 ] && break; sleep 5; done
after=$(snap)
[ "$before" = "$after" ] && pass "secrets: sha256 unchanged across restart ($(echo "$after" | awk '{print $1"="$4}' | tr '\n' ' '))" \
    || bad "secrets changed across restart"
cfg_first=$($CLI logs --app "$APP" --lines 400 2>/dev/null | grep -c 'first boot: writing')
[ "$cfg_first" = 0 ] && pass "boot path: existing config found (no first-boot line after restart)" || bad "restart took the first-boot path"

# 5. Logs clean at idle.
sleep "${IDLE_SECONDS:-180}"
noise=$($CLI logs --app "$APP" --lines 600 2>/dev/null | grep -E 'Traceback|EACCES|Permission denied|FATAL|exited: .*not expected|Connection refused' | grep -v 'curl: (7)' | tail -5)
[ -z "$noise" ] && pass "logs: clean over ${IDLE_SECONDS:-180}s idle" || bad "logs: ${noise}"

exit $fail
