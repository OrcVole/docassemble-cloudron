# Debugging and gate evidence

## Where to look

- **Logs:** every program logs to the container's stdout (Cloudron's log view). docassemble's own
  `docassemble.log` is in `/run/docassemble/log` (not backed up, reset on restart).
- **Programs:** `supervisorctl status` in the app's Terminal. Seven run (nginx, uwsgi, celery,
  celerysingle, websockets, nltk, unoserver); `ready` exits once the web app answers.
- **Health:** `/healthz` is 503 until the web app has answered once, then proxies docassemble's
  `/health_check`.
- **Configuration:** `/app/data/config/config.yml`. `mail` and `ldap login` are refreshed from Cloudron
  on every start; the start log says which (`owned-config: refreshed ...`).
- **Secrets:** `/app/data/.secrets` (`secretkey` decrypts stored answers; never delete it).

## Gate evidence, 0.1.0 (docassemble 1.10.15), 2026-11-07

Image `ghcr.io/orcvole/docassemble-cloudron@sha256:2a10dc4b0d5b0d9bec720dbaf9d27739a436bb880e46aec059b81fd063fbc5a1`
on a test Cloudron 10.1.6. The gates are scripts in `test/`; run them the same way at every update.

### Gate 0: install and first run (`test/gate0.sh`), fresh install

| Invariant | Proof |
|---|---|
| digest | the box runs the registry digest above |
| install | 40 s to healthy |
| health | `/healthz` 200 from outside; anonymous `/` 302 to sign-in, 200 after redirects |
| robots.txt | `User-agent: *` / `Disallow: /` (upstream default) |
| programs | 7 RUNNING, `ready` EXITED after its job |
| secrets | 3 files, 600 cloudron:cloudron, sha256 unchanged across a restart |
| config.yml | sha256 unchanged across a restart (first-boot write not repeated) |
| logs | clean over 120 s idle |

### Gate 1: sign-in (`test/gate1.py`)

| Invariant | Proof |
|---|---|
| administrator | generated local account signs in; sees admin and Playground menus |
| Cloudron user | signs in through the ldap addon by email; row created with `ldap` social id and role `user` |
| wrong passwords | refused for both kinds of account, including a local account whose email is not in LDAP |
| closed pages | `/playground`, `/config`, `/userlist`, `/updatepackage` redirect anonymous visitors to sign-in |
| registration | refused |

### Gate 2: real work (`test/gate2.sh`)

| Flow | Proof |
|---|---|
| background PDF (celery queue) | 19,240-byte PDF set in Tinos through pandoc and LuaLaTeX |
| OCR (single queue) | the PDF read back: "The quick brown fox jumps over the lazy dog. Docassemble on Cloudron." |
| add-on package | installed through the API into `/app/data/packages`, imported from there, no manual restart |
| DOCX to PDF | 26,825-byte PDF through unoserver (LibreOffice) |
| mail | accepted by the sendmail addon on STARTTLS port 2587 |
| files | 1 MiB upload and download sha256-identical |
| live help | monitor connection over websockets; server answered `updatemonitor`; its Redis pub/sub subscribed over the password-protected addon (ADR 0003) |

### Gate 3: update and restore (`test/state.sh` snapshots compared with diff)

| Invariant | Update (candidate 2→3, 3→4, with data) | In-place restore (candidate 3 and 4) |
|---|---|---|
| secrets | sha256 identical | sha256 identical |
| data | users, sessions, uploads, packages, files unchanged | post-backup writes rolled back (e.g. sessions 1210→1209, uploads 1813→1811) |
| config.yml | only `ldap login` refreshed (Cloudron reissues bind credentials) | same |
| add-on | still imported from `/app/data/packages` | — |
| after | proof 1 passes; LDAP sign-in works with the new credentials | proof 1 passes |

Clone was not run (no free test slot); a clone starts from a backup, which the restore leg covers.

### Gate 4: memory (`test/load.py`, 8 clients for 6 minutes)

| Invariant | Idle (3 min after restart) | Loaded (cap 4.5 GiB) |
|---|---|---|
| memory.current / peak | 1,869 MiB / — | 2,304 MiB / 3,160 MiB (69% of the cap) |
| anon / file | 1,850 / 1 MiB | 2,190 / 76 MiB |
| memory.events max, oom_kill | 0, 0 | 0, 0 |
| swap peak | 0 | 0 |
| sessions | — | 612 completed (306 PDF+OCR, 306 DOCX), 0 failed |
| RSS by program | celery 0.9 GiB, uwsgi 0.86, celerysingle 0.63, nltk 0.32, websockets 0.2, LibreOffice 0.14 GiB | LibreOffice grows to 0.27 GiB |

Verdict: PASS. `memoryLimit` 4.5 GiB = loaded peak / 0.7, rounded. Before ADR 0009 the same load
failed 2 of 602 background tasks (shared database connections); after it, 0 of 1,210.

## Known messages that are not faults

- `curl: (7) Failed to connect` a few times at start: `ready.sh` polling before uWSGI listens.
- `owned-config: refreshed ldap login` after an update or restore: Cloudron reissued credentials.
- `In ... zz-docassemble-addons.pth: ... does not exist; skipping` only during image builds.
