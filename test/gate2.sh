#!/bin/bash
# gate2.sh: gate 2 (real work, end to end) against a Cloudron install.
#   BASE=https://<fqdn> KEY=<admin API key> ADMIN_PASSWORD=<...> [INSECURE=1] test/gate2.sh
# Runs proofs 1 and 2 (background PDF and OCR; an add-on installed from the API), DOCX to PDF through
# unoserver, mail through the sendmail addon, a byte-exact file round trip, and a live-help monitor
# connection over websockets (the Redis pub/sub path ADR 0003 patches).
set -uo pipefail
here="$(dirname "$0")"; fail=0
BASE="${BASE:?}"; KEY="${KEY:?}"
api() { curl -fsS ${INSECURE:+-k} -H "X-API-Key: ${KEY}" "$@"; }
pass() { echo "PASS  $*"; }; bad() { echo "FAIL  $*"; fail=1; }

BASE="$BASE" KEY="$KEY" INSECURE="${INSECURE:-}" "$here/proofs.sh" all | grep -E '^(PASS|FAIL)|PDFBYTES|ADDON' || fail=1

# DOCX to PDF, and mail.
api -X POST -F folder=questions -F project=default -F restart=false \
    -F "file=@${here}/gate2-interview.yml;filename=gate2.yml" "${BASE}/api/playground" >/dev/null || bad "upload gate2 interview"
I=docassemble.playground1:gate2.yml
s=$(api "${BASE}/api/session/new?i=${I}")
sess=$(echo "$s" | python3 -c 'import json,sys;print(json.load(sys.stdin)["session"])')
sec=$(echo "$s" | python3 -c 'import json,sys;print(json.load(sys.stdin)["secret"])')
line=$(api "${BASE}/api/session/question?i=${I}&session=${sess}&secret=${sec}" | python3 -c 'import json,sys
print(json.load(sys.stdin).get("subquestionText") or "")' | grep -o 'GATE2 [^<]*')
echo "      ${line}"
echo "$line" | grep -qE 'DOCXPDF=[1-9][0-9]{3,}' && pass "DOCX to PDF through unoserver" || bad "DOCX to PDF: ${line}"
echo "$line" | grep -q 'MAIL=True' && pass "mail accepted by the sendmail addon (STARTTLS 2587)" || bad "mail: ${line}"

# Byte-exact file round trip through the Playground's file store in /app/data.
tmp=$(mktemp -d); head -c 1048576 /dev/urandom > "$tmp/blob.bin"; want=$(sha256sum < "$tmp/blob.bin" | cut -c1-64)
api -X POST -F folder=static -F project=default -F restart=false -F "file=@$tmp/blob.bin;filename=gate2-blob.bin" "${BASE}/api/playground" >/dev/null
api -o "$tmp/back.bin" "${BASE}/api/playground?folder=static&project=default&filename=gate2-blob.bin"
got=$(sha256sum < "$tmp/back.bin" | cut -c1-64)
[ "$want" = "$got" ] && pass "1 MiB upload and download sha256-identical (${got:0:16})" || bad "round trip: ${want:0:16} != ${got:0:16}"

# Live help: the administrator's monitor connection, through nginx and the patched Redis pub/sub.
BASE="$BASE" INSECURE="${INSECURE:-}" ADMIN_PASSWORD="${ADMIN_PASSWORD:?}" \
    uv run -q --no-project --with requests --with 'python-socketio[client]' python -I "$here/gate2-monitor.py" || fail=1
exit $fail
