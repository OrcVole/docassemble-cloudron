# 0004. Add-on packages and Playground modules in `/app/data/packages`

- **Status:** proposed, 2026-11-07. Decided by proof 2, the first thing the build must pass.

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
