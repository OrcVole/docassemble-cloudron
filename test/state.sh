#!/bin/bash
# state.sh: print a comparable snapshot of an install's state, for gate 3 (update and restore).
#   CLI=<cloudron CLI wrapper> APP=<fqdn> test/state.sh
# One line per invariant: secret sha256 prefixes and modes, row counts in the PostgreSQL addon, and file
# counts in /app/data. Compare two runs with diff; never prints a secret.
set -uo pipefail
CLI="${CLI:?}"; APP="${APP:?}"
$CLI exec --app "$APP" -- bash -c '
cd /app/data/.secrets && for f in *; do echo "secret $f $(stat -c "%a %U:%G" "$f") $(sha256sum < "$f" | cut -c1-16)"; done
echo "config.yml $(sha256sum < /app/data/config/config.yml | cut -c1-16)"
echo "files under /app/data/files: $(find /app/data/files -type f | wc -l)"
echo "add-ons in /app/data/packages: $(ls /app/data/packages/lib/python3.15/site-packages 2>/dev/null | grep -c dist-info)"
/app/code/venv/bin/python - <<PY 2>/dev/null
import os, psycopg2
e = os.environ
c = psycopg2.connect(host=e["CLOUDRON_POSTGRESQL_HOST"], port=e["CLOUDRON_POSTGRESQL_PORT"], dbname=e["CLOUDRON_POSTGRESQL_DATABASE"],
                     user=e["CLOUDRON_POSTGRESQL_USERNAME"], password=e["CLOUDRON_POSTGRESQL_PASSWORD"])
cur = c.cursor()
for t in ("user", "userdict", "uploads", "package", "attachments", "chatlog", "objectstorage"):
    try:
        cur.execute(f"select count(*) from \"{t}\""); print(f"rows {t}: {cur.fetchone()[0]}")
    except Exception as ex:
        c.rollback(); print(f"rows {t}: n/a ({type(ex).__name__})")
cur.execute("select version_num from alembic_version"); print("alembic:", cur.fetchone()[0])
PY
' 2>&1 | grep -v zz-docassemble
