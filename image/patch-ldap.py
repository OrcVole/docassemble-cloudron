"""ADR 0008: make LDAP sign-in work with Cloudron's ldap addon, without weakening it.

Cloudron's LDAP server does not implement the WhoAmI extended operation, so docassemble's check after
a successful bind raises, and every Cloudron user falls back to (missing) local passwords. Removing
the check alone is not enough: an anonymous bind (empty DN or password) must never count as a
sign-in, so the patch refuses those first. Exit non-zero unless the exact upstream lines are found.
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
OLD = """            try:
                connect.simple_bind_s(username, password)
                if connect.whoami_s() is not None:
"""
NEW = """            try:
                # Cloudron package, ADR 0008: never treat an anonymous bind as a sign-in, and do not
                # rely on WhoAmI, which Cloudron's LDAP server does not implement.
                if not (username and password):
                    raise ldap.INVALID_CREDENTIALS({'desc': 'empty bind DN or password'})
                connect.simple_bind_s(username, password)
                if True:
"""
if src.count(OLD) != 1:
    sys.exit(f"patch-ldap: expected the bind-then-whoami block exactly once, found {src.count(OLD)}; "
             "upstream changed, revisit ADR 0008")
open(path, "w", encoding="utf-8").write(src.replace(OLD, NEW))
print("patch-ldap: anonymous binds refused; WhoAmI no longer required")
