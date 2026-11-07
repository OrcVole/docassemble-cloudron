#!/bin/bash
# Docassemble for Cloudron: start-up. Replaces upstream's initialize.sh for a single all-in-one server
# whose services come from Cloudron addons. Order follows upstream: secrets and config, start hook,
# tables and migrations, package reinstall, then the long-running programs under supervisord.
set -euo pipefail
source /app/code/bin/env.sh

log() { echo "start: $*" >&2; }

# --- 1. Secrets: generated once, never regenerated -----------------------------------------------
mkdir -p "${SECRETS}" && chmod 700 "${SECRETS}"
first_boot=false
if [ ! -f "${DA_CONFIG_FILE}" ]; then first_boot=true; fi

if [ ! -s "${SECRETS}/secretkey" ]; then
    if [ "${first_boot}" = false ]; then
        log "FATAL: config.yml exists but ${SECRETS}/secretkey is missing. Stored answers are encrypted"
        log "with that key; generating a new one would make them unreadable. Restore it from a backup."
        exit 1
    fi
    openssl rand -hex 32 > "${SECRETS}/secretkey"
fi
[ -s "${SECRETS}/supervisor" ] || openssl rand -hex 24 > "${SECRETS}/supervisor"
if [ "${first_boot}" = true ] && [ ! -s "${SECRETS}/admin-password" ]; then
    openssl rand -base64 18 | tr -d '/+=' > "${SECRETS}/admin-password"
fi
chmod 600 "${SECRETS}"/*
source /app/code/bin/env.sh   # re-read, now that the secrets exist

# --- 2. Directories and the config file -----------------------------------------------------------
prepare_run_dirs
if [ "${first_boot}" = true ]; then
    log "first boot: writing ${DA_CONFIG_FILE} from the template (it is never rewritten after this)"
    sed -e "s|@TIMEZONE@|${TZ:-Etc/UTC}|" /app/code/image/config.yml > "${DA_CONFIG_FILE}"
fi
# Refresh only the keys Cloudron owns and that have no environment override (mail, ldap login),
# and the two safety settings; every other line and comment is left as the operator wrote it.
/app/code/venv/bin/python /app/code/bin/owned-config.py "${DA_CONFIG_FILE}"
mkdir -p /app/data/fonts
chown -R cloudron:cloudron /app/data
# Operator fonts in /app/data/fonts: refresh fontconfig and LuaLaTeX's font database so PDFs can use them.
if [ -n "$(find /app/data/fonts -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit)" ]; then
    log "operator fonts found in /app/data/fonts; refreshing font caches"
    as_app fc-cache /app/data/fonts >/dev/null 2>&1 || true
    as_app env TEXMFVAR="${TEXMFVAR}" luaotfload-tool --update >/dev/null 2>&1 || log "WARNING: luaotfload-tool --update failed"
fi

# --- 3. Upstream's one-off steps, as the app user ------------------------------------------------
if [ "${first_boot}" = true ]; then
    export DA_ADMIN_EMAIL="admin@${CLOUDRON_APP_DOMAIN}"
    DA_ADMIN_PASSWORD="$(cat "${SECRETS}/admin-password")"; export DA_ADMIN_PASSWORD
fi
log "start hook";     as_app python -m docassemble.webapp.starthook "${DA_CONFIG_FILE}"
log "create tables";  as_app python -m docassemble.webapp.create_tables "${DA_CONFIG_FILE}"
unset DA_ADMIN_EMAIL DA_ADMIN_PASSWORD
# Reinstall add-on packages recorded in docassemble's own database (ADR 0004). A package index that
# cannot be reached must not keep the app down, so a failure is reported loudly and start continues.
log "update packages"
if ! as_app python -m docassemble.webapp.update "${DA_CONFIG_FILE}" initialize; then
    log "WARNING: docassemble.webapp.update failed; add-on packages may be missing until the next start"
fi
as_app python -m docassemble.webapp.register "${DA_CONFIG_FILE}" || log "WARNING: register failed"

# --- 4. The long-running programs ----------------------------------------------------------------
rm -f "${RUNDIR}/ready"
log "starting supervisord"
exec /usr/bin/supervisord --configuration /app/code/image/supervisord.conf --nodaemon
