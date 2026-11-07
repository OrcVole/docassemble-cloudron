"""gate1.py: gate 1 (sign-in) against a Cloudron install. One PASS/FAIL line per invariant.

    APP=<fqdn> ADMIN_PASSWORD=<from /app/data/.secrets/admin-password>
    LDAP_EMAIL=<a Cloudron user's email> LDAP_PASSWORD=<their password> [INSECURE=1]
    uv run --with requests python -I test/gate1.py

Invariants: the generated administrator signs in with a local password; a Cloudron user signs in
through the ldap addon by email address and lands as an ordinary user; a wrong password is refused;
self-registration is refused; admin and Playground pages are closed to anonymous visitors.
"""
import os
import re
import sys

import requests

APP = os.environ["APP"]
BASE = f"https://{APP}"
VERIFY = not os.environ.get("INSECURE")
fails = 0


def report(ok, text):
    global fails
    print(("PASS  " if ok else "FAIL  ") + text)
    fails += 0 if ok else 1


def sign_in(email, password):
    s = requests.Session()
    s.verify = VERIFY
    page = s.get(f"{BASE}/user/sign-in", timeout=30)
    token = re.search(r'name="csrf_token"[^>]*value="([^"]+)"', page.text)
    if not token:
        return s, None, "no csrf_token on the sign-in page"
    # Flask-WTF's strict CSRF check on HTTPS wants the Referer a browser would send.
    r = s.post(f"{BASE}/user/sign-in", data={"csrf_token": token.group(1), "email": email,
               "password": password, "next": ""}, headers={"Referer": f"{BASE}/user/sign-in"},
               timeout=60, allow_redirects=True)
    prof = s.get(f"{BASE}/user/profile", timeout=30, allow_redirects=False)
    return s, prof.status_code == 200, f"profile {prof.status_code} after sign-in (landed on {r.url.replace(BASE, '')})"


def roles(session):
    """The menu lists admin-only and developer-only entries; read them as the role evidence."""
    html = session.get(f"{BASE}/interviews", timeout=30).text
    return {"admin": "/userlist" in html, "playground": "/playground" in html}


# Anonymous access.
anon = requests.Session()
anon.verify = VERIFY
for path in ("/playground", "/config", "/userlist", "/updatepackage"):
    r = anon.get(f"{BASE}{path}", timeout=30, allow_redirects=False)
    loc = r.headers.get("Location", "")
    report(r.status_code in (302, 303) and "sign-in" in loc or r.status_code in (401, 403, 404),
           f"anonymous {path}: {r.status_code} {loc.replace(BASE, '')[:60]}")
r = anon.get(f"{BASE}/user/register", timeout=30, allow_redirects=True)
report("register" not in r.url or r.status_code >= 400,
       f"self-registration refused (/user/register ends at {r.url.replace(BASE, '')} {r.status_code})")

# The generated administrator, local password.
s, ok, why = sign_in(f"admin@{APP}", os.environ["ADMIN_PASSWORD"])
report(bool(ok), f"administrator signs in locally: {why}")
if ok:
    rl = roles(s)
    report(rl["admin"] and rl["playground"], f"administrator sees admin and Playground menus: {rl}")

# A wrong password is refused.
s, ok, why = sign_in(f"admin@{APP}", "not-the-password")
report(ok is False, f"local account, not in LDAP, wrong password refused (the anonymous-bind case, ADR 0008): {why}")

# A Cloudron user through the ldap addon.
s, ok, why = sign_in(os.environ["LDAP_EMAIL"], os.environ["LDAP_PASSWORD"])
report(bool(ok), f"Cloudron user signs in through LDAP: {why}")
if ok:
    rl = roles(s)
    report(not rl["admin"] and not rl["playground"], f"Cloudron user lands as an ordinary user: {rl}")
s, ok, why = sign_in(os.environ["LDAP_EMAIL"], "not-the-password")
report(ok is False, f"Cloudron user with a wrong password refused: {why}")

sys.exit(1 if fails else 0)
