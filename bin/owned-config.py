"""Refresh the config.yml keys Cloudron owns, leaving everything else exactly as written.

config.yml is the operator's after first boot (ADR 0001, principle 4). Two blocks come from Cloudron
addons and have no environment equivalent in docassemble, and their credentials change on restore:
`mail` (sendmail addon) and `ldap login` (ldap addon). This rewrites only those, plus the safety
settings `debug` and `allow demo`, using a round-trip YAML load so comments and order are kept.
An operator opts out of a block with `cloudron manages mail: False` or `cloudron manages ldap: False`.
"""
import os
import sys

from ruamel.yaml import YAML

path = sys.argv[1]
env = os.environ
yaml = YAML()
yaml.preserve_quotes = True
yaml.width = 4096

with open(path, encoding="utf-8") as f:
    cfg = yaml.load(f)

changed = []


def put(key, value):
    if cfg.get(key) != value:
        cfg[key] = value
        changed.append(key)


put("debug", False)
put("allow demo", False)

if cfg.get("cloudron manages mail", True) is not False and env.get("CLOUDRON_MAIL_SMTP_SERVER"):
    name = env.get("CLOUDRON_MAIL_FROM_DISPLAY_NAME") or "docassemble"
    put("mail", {
        "server": env["CLOUDRON_MAIL_SMTP_SERVER"],
        # 2587 is STARTTLS; 2525 is plain (platform facts, 2026-08-20).
        "port": int(env.get("CLOUDRON_MAIL_STARTTLS_PORT", "2587")),
        "use tls": True,
        "use ssl": False,
        "username": env.get("CLOUDRON_MAIL_SMTP_USERNAME"),
        "password": env.get("CLOUDRON_MAIL_SMTP_PASSWORD"),
        "default sender": f'"{name}" <{env.get("CLOUDRON_MAIL_FROM", "")}>',
    })

if cfg.get("cloudron manages ldap", True) is not False:
    if env.get("CLOUDRON_LDAP_SERVER"):
        put("ldap login", {
            "enable": True,
            "server": f'{env["CLOUDRON_LDAP_SERVER"]}:{env.get("CLOUDRON_LDAP_PORT", "389")}',
            "base dn": env.get("CLOUDRON_LDAP_USERS_BASE_DN", ""),
            "bind dn": env.get("CLOUDRON_LDAP_BIND_DN", ""),
            "bind password": env.get("CLOUDRON_LDAP_BIND_PASSWORD", ""),
            # Find the user's DN by email address, then bind as that DN with their password.
            "login with bind_dn": True,
            "search pattern": "mail=%s",
        })
    else:
        # Installed without Cloudron sign-in: local accounts only.
        put("ldap login", {"enable": False})

if changed:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        yaml.dump(cfg, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
print("owned-config: refreshed " + (", ".join(changed) if changed else "nothing (already current)"),
      file=sys.stderr)
