#!/bin/bash
# proofs.sh: the two day-one proofs, over docassemble's HTTP API.
#   BASE=http://127.0.0.1:8100 KEY=<32-char admin API key> test/proofs.sh [1|2|all]
# Proof 1: background PDF (celery queue) and OCR of it (single queue). Proof 2: install an add-on
# package from PyPI through the API, then start one of its interviews with no manual restart.
set -uo pipefail
BASE="${BASE:-http://127.0.0.1:8100}"; KEY="${KEY:?set KEY to the admin API key}"
which="${1:-all}"; here="$(dirname "$0")"; fail=0
api() { curl -fsS -H "X-API-Key: ${KEY}" "$@"; }

if [ "$which" = 1 ] || [ "$which" = all ]; then
    echo "== proof 1: background PDF + OCR"
    api -X POST -F folder=questions -F project=default -F restart=false \
        -F "file=@${here}/proof-interview.yml;filename=proof.yml" "${BASE}/api/playground" >/dev/null \
        || { echo "FAIL upload"; exit 1; }
    I=docassemble.playground1:proof.yml
    s=$(api "${BASE}/api/session/new?i=${I}") || { echo "FAIL session/new"; exit 1; }
    sess=$(echo "$s" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["session"])')
    sec=$(echo "$s" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["secret"])')
    for n in $(seq 1 90); do
        q=$(api "${BASE}/api/session/question?i=${I}&session=${sess}&secret=${sec}")
        # Read the rendered text only; the API also echoes the interview source, which contains the marker.
        line=$(echo "$q" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("subquestionText") or "")
except Exception: print("")' | grep -o 'PDFBYTES=[0-9].*' | head -1)
        if [ -n "$line" ]; then break; fi
        sleep 4
    done
    echo "   $line"
    if echo "$line" | grep -qE 'PDFBYTES=[1-9][0-9]+ ' && echo "$line" | grep -qi 'quick brown fox'; then
        echo "PASS proof 1"
    else
        echo "FAIL proof 1 (last screen: $(echo "$q" | head -c 300))"; fail=1
    fi
fi

if [ "$which" = 2 ] || [ "$which" = all ]; then
    echo "== proof 2: an add-on installed through the API, imported from /app/data, no manual restart"
    # The fixture exists nowhere in the image, so a pass cannot be vacuous (field guide #332).
    zipf="$(mktemp -d)/docassemble-cloudronproof.zip"
    (cd "${here}/fixtures/addon" && python3 -c "import zipfile,os,sys
z=zipfile.ZipFile(sys.argv[1],'w')
for r,_,fs in os.walk('.'):
    for f in fs:
        if '__pycache__' not in r: z.write(os.path.join(r,f))" "$zipf")
    t=$(api -X POST -F "zip=@${zipf}" -F restart=true "${BASE}/api/package") || { echo "FAIL install request"; exit 1; }
    task=$(echo "$t" | python3 -c 'import json,sys;print(json.load(sys.stdin)["task_id"])')
    for n in $(seq 1 120); do
        st=$(api "${BASE}/api/package_update_status?task_id=${task}" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("status"))')
        [ "$st" = completed ] && break; sleep 5
    done
    echo "   install status: $st"
    for n in $(seq 1 60); do curl -fsS -o /dev/null "${BASE}/healthz" && break; sleep 3; done
    I=docassemble.cloudronproof:data/questions/proof.yml
    s=$(api "${BASE}/api/session/new?i=${I}") || { echo "FAIL proof 2 (interview did not start)"; exit 1; }
    sess=$(echo "$s" | python3 -c 'import json,sys;print(json.load(sys.stdin)["session"])')
    sec=$(echo "$s" | python3 -c 'import json,sys;print(json.load(sys.stdin)["secret"])')
    line=$(api "${BASE}/api/session/question?i=${I}&session=${sess}&secret=${sec}" | python3 -c 'import json,sys
print(json.load(sys.stdin).get("subquestionText") or "")' | grep -o 'ADDON-IMPORTED-FROM=[^<"]*')
    echo "   ${line}"
    if echo "$line" | grep -q 'ADDON-IMPORTED-FROM=/app/data/packages/'; then
        echo "PASS proof 2"
    else
        echo "FAIL proof 2"; fail=1
    fi
fi
exit $fail
