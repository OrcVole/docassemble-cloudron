# Sourced by start.sh, cron.sh and reset.sh. Everything docassemble needs from Cloudron, translated
# into the environment variables docassemble reads (ENVIRONMENT_TAKES_PRECEDENCE makes them win over
# config.yml). Kept in one place because the scheduler runs cron.sh in a fresh container that never
# runs start.sh. See AGENTS.md, "Configuration mapping".

SECRETS=/app/data/.secrets
RUNDIR=/run/docassemble

export DA_PYTHON=/app/code/venv
export DA_CONFIG_FILE=/app/data/config/config.yml
export NLTK_DATA=/app/code/nltk_data
export PATH=/app/code/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export HOME="${RUNDIR}/home"
export TEXMFVAR="${RUNDIR}/texmf-var"
export CONTAINERROLE=all
# The NLTK daemon reads only this variable; the web side reads it over the config key.
export NLTKSOCKET="${RUNDIR}/nltk.sock"
export ENVIRONMENT_TAKES_PRECEDENCE=true

# PostgreSQL addon.
export DBPREFIX='postgresql+psycopg2://'
export DBHOST="${CLOUDRON_POSTGRESQL_HOST}" DBPORT="${CLOUDRON_POSTGRESQL_PORT}"
export DBNAME="${CLOUDRON_POSTGRESQL_DATABASE}"
export DBUSER="${CLOUDRON_POSTGRESQL_USERNAME}" DBPASSWORD="${CLOUDRON_POSTGRESQL_PASSWORD}"

# Redis addon: docassemble's cache and Celery results on databases 0 to 2, the broker on 3 (ADR 0005).
export REDIS="redis://default:${CLOUDRON_REDIS_PASSWORD}@${CLOUDRON_REDIS_HOST}:${CLOUDRON_REDIS_PORT}"
export RABBITMQ="redis://default:${CLOUDRON_REDIS_PASSWORD}@${CLOUDRON_REDIS_HOST}:${CLOUDRON_REDIS_PORT}/3"

# Location. Cloudron terminates TLS; the config template sets 'behind https load balancer'.
export DAHOSTNAME="${CLOUDRON_APP_DOMAIN}"
export URLROOT="${CLOUDRON_APP_ORIGIN}"

# Secrets generated once by start.sh. Read-only here: never regenerated (the secret key decrypts
# every stored answer).
if [ -r "${SECRETS}/secretkey" ]; then
    DASECRETKEY="$(cat "${SECRETS}/secretkey")"; export DASECRETKEY
fi
if [ -r "${SECRETS}/supervisor" ]; then
    export DASUPERVISORUSERNAME=docassemble
    DASUPERVISORPASSWORD="$(cat "${SECRETS}/supervisor")"; export DASUPERVISORPASSWORD
fi

# The runtime directories every docassemble process expects. Idempotent; also needed in the
# scheduler's container, because the web app exits at import if the WSGI file is not writable.
prepare_run_dirs() {
    mkdir -p "${RUNDIR}/log" "${RUNDIR}/certs" "${RUNDIR}/home" "${RUNDIR}/nginx" \
             /app/data/config /app/data/files /app/data/home \
             /app/data/packages/lib/python3.15/site-packages
    touch "${RUNDIR}/docassemble.wsgi"
    if [ ! -d "${TEXMFVAR}" ]; then cp -a /app/code/texmf-var "${TEXMFVAR}"; fi
    chown -R cloudron:cloudron "${RUNDIR}"
}

# Run a command as the app user. gosu resets HOME to the passwd entry (field guide #319), so pass the
# environment's HOME explicitly.
as_app() {
    gosu cloudron:cloudron env HOME="${HOME}" "$@"
}
