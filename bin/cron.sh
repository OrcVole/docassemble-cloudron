#!/bin/bash
# Cloudron scheduler entry point: cron.sh hourly|daily|weekly|monthly. Runs in a fresh container that
# never ran start.sh, so it prepares the runtime directories itself (the web app exits at import if
# its WSGI file is not writable). After upstream's docassemble-cron-*.sh, without the log rsync and
# the files backup (Cloudron backs up /app/data).
set -uo pipefail
period="${1:?usage: cron.sh hourly|daily|weekly|monthly}"
source /app/code/bin/env.sh
prepare_run_dirs
export IN_CRON=true
if [ "${period}" = hourly ]; then
    find /tmp -maxdepth 1 -type d -mmin +60 -name 'SavedFile*' -exec rm -rf {} + 2>/dev/null
    find /tmp -maxdepth 1 -type f -mmin +60 -name 'datemp*' -delete 2>/dev/null
fi
as_app nice -n 19 flask --app docassemble.webapp.server cron run "cron_${period}"
rc=$?
if [ "${period}" = hourly ]; then
    as_app python -m docassemble.webapp.cleanup_sessions "${DA_CONFIG_FILE}" || rc=$?
fi
exit "${rc}"
