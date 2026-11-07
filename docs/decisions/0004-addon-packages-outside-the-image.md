# 0004. Add-on packages and Playground modules in `/app/data/packages`

- **Status:** accepted, 2026-11-07 (proof 2 passed on the local stack; see "Evidence")

## Context

Docassemble installs add-on packages with `pip install --prefix=<packages>`, and `packages` defaults
to the Python environment itself. No code puts a separate prefix on `sys.path`; upstream works only
because the two are the same directory. The Playground also writes each author's modules under
`<packages>/lib/python3.X/site-packages/docassemble/playground<id>`, and the app exits at start if
that directory is not writable while the Playground or updates are enabled. Our environment is in the
read-only image (ADR 0001, principle 3).

## Decision

- `packages: /app/data/packages`.
- One static `.pth` file in the image environment's `site-packages` names
  `/app/data/packages/lib/python3.15/site-packages`, so the web server, both Celery workers, the
  websocket server and the NLTK daemon all see add-ons the same way. No symlink, no `PYTHONPATH`.
- `docassemble` is a native namespace package (no `__init__.py`), so `docassemble.base` in the image
  and `docassemble.<addon>` in `/app/data` combine.
- After each install, docassemble restarts itself through supervisord's HTTP interface on
  `127.0.0.1:9001` and by touching the WSGI file. Both are wired for this purpose (`start.sh`).

## Proof 2: pass criteria

1. A package installed from Package Management is usable by an interview with no manual restart.
2. After an image update, the add-ons are still importable, or are reinstalled from docassemble's own
   record.
3. An add-on that needs a **newer** version of a dependency the image already has: record what pip
   does (installs a second copy that the image's copy shadows, or fails trying to remove the image's
   copy) and which version the app loads. This decides whether the README warns about it or the
   package intervenes.

## Fallback

The prefix stays writable either way, because the Playground needs it. If installing from the UI
cannot be made safe, turn off Package Management only (`allow updates: False`) and install a list of
packages kept in `/app/data` at start. Say so plainly in DESCRIPTION.

## Evidence (2026-11-07, local stack, read-only root filesystem)

1. A fixture add-on (`test/fixtures/addon`, present nowhere in the image) uploaded through
   `POST /api/package` was installed by docassemble's own pip call into `/app/data/packages`, the
   `reset` program restarted the web app and workers through supervisord's localhost port, and its
   interview then reported `proofmod.py` imported from `/app/data/packages/lib/python3.15/site-packages`.
   No manual restart. (A first attempt with `docassemble.demo` passed vacuously: it is a dependency of
   docassemble.webapp and already in the image. The fixture exists so the proof can fail.)
2. After an app restart the interview still starts and docassemble's package record is intact.
3. Shadowing: pip, asked for a different version of a library the image already has, tries to remove
   the image's copy, fails on the read-only filesystem and stops. Nothing changes. **Rule:** add-ons must
   work with the library versions docassemble pins; the README says so.

Caveat for later: the prefix path names the Python minor version (`python3.15`). A future move to 3.16
must reinstall add-ons from docassemble's package table, which `update initialize` does at start;
prove it in that update's gate 3.
