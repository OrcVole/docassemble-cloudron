#!/bin/bash
# Supervisor program `reset`, started by docassemble after a package install or a configuration
# edit (update.py). After upstream's reset.sh: reload the web app (touch the WSGI file, re-run
# create_tables), then restart live help and both workers so they import the new code. Upstream's
# pip-config step is left out: it writes pip's global config, which is in the read-only image.
source /app/code/bin/env.sh
echo "reset: restarting the web app" >&2
python -m docassemble.webapp.restart
# The unix socket is root-only; this program runs as cloudron, so use the authenticated localhost port.
ctl() { supervisorctl -s http://127.0.0.1:9001 -u "${DASUPERVISORUSERNAME}" -p "${DASUPERVISORPASSWORD}" "$@"; }
ctl restart websockets &
ctl restart celery celerysingle &
wait
echo "reset: finished" >&2
exit 0
