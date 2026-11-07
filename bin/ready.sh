#!/bin/bash
# Supervisor program: wait until the web app answers through nginx, then write the ready file that
# turns /healthz from 503 into 200. Gives up after 15 minutes (Cloudron then reports the app down,
# which is the truth).
for _ in $(seq 1 900); do
    if curl -fsS -o /dev/null --max-time 5 http://127.0.0.1:8000/health_check; then
        touch /run/docassemble/ready
        echo "ready: web app answering; /healthz now 200" >&2
        exit 0
    fi
    sleep 1
done
echo "ready: web app did not answer within 15 minutes" >&2
exit 1
