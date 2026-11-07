"""ADR 0003: make docassemble's websocket server authenticate to Redis.

Upstream's socketserver.py opens three pub/sub connections with host, port and db only. Rewrite them
to pass the password, username and TLS options that daredis.py already parses, and import those
names. Exit non-zero unless exactly the expected lines are found, so a changed upstream file stops
the build instead of being patched blindly. Remove this file once upstream carries the fix.
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

OLD_CALL = "redis.StrictRedis(host=redis_host, port=redis_port, db=redis_offset)"
NEW_CALL = ("redis.StrictRedis(host=redis_host, port=redis_port, db=redis_offset, "
            "password=redis_password, username=redis_username, **ssl_opts)")
OLD_IMPORT = "from docassemble.webapp.daredis import r as rr, redis_host, redis_port, redis_offset, r_store"
NEW_IMPORT = OLD_IMPORT + ", redis_password, redis_username, ssl_opts"

calls = src.count(OLD_CALL)
imports = src.count(OLD_IMPORT)
if calls != 3 or imports != 1:
    sys.exit(f"patch-socketserver: expected 3 calls and 1 import, found {calls} and {imports}; "
             "upstream changed, revisit ADR 0003")
src = src.replace(OLD_CALL, NEW_CALL).replace(OLD_IMPORT, NEW_IMPORT)
open(path, "w", encoding="utf-8").write(src)
print("patch-socketserver: 3 connections now authenticate")
