# 0002. CPython 3.15 from a pinned `uv`, in a venv seeded with pip

- **Status:** accepted, 2026-11-07 (probe passed; runtime still to prove at the gates)

## Context

`cloudron/base:6.0.1` carries Python 3.14 but no `venv`, `ensurepip` or `pip`. Docassemble 1.10.15
requires Python 3.12 or newer, and upstream's own image runs 3.14. The maintainer's standing choice is
the newest versions. Docassemble also runs `pip install` itself, at runtime, whenever an
administrator installs an add-on package (`update.py`), so the environment must contain pip.

## Decision

- A pinned `uv` binary installs **CPython 3.15.2** into `/app/code/python` and creates
  `/app/code/venv` with `uv venv --seed`, so pip is present. `UV_PYTHON_DOWNLOADS=never` at runtime.
- `docassemble.base`, `docassemble.webapp` (both exact versions, which pin 259 dependencies
  between them) and `uWSGI==2.0.31` are installed in a builder stage that has compilers. Only the
  finished `/app/code` is copied into the runtime stage.
- `unoserver` stays on the base image's **system** Python, because it needs LibreOffice's `uno`
  binding, which belongs to the distribution's Python. It talks to docassemble over a socket, so
  the two interpreters never share a process. Upstream does the same.
- **Fallback:** if a future pinned dependency cannot build or import on 3.15, move to the newest 3.14
  and record it here. Do not patch around it.

## Evidence (probe, 2026-11-07)

On `cloudron/base:6.0.1` with uv 0.13.7:

- The full pinned set installed.
- Four packages compiled locally (PyYAML, ruamel.yaml.clib, netifaces, python-ldap), plus uWSGI;
  every other compiled dependency has a published 3.15 wheel.
- No shared object asks for an executable stack (485 scanned; glibc 2.43 refuses those).
- All libraries import. The web app and worker get through start-up and stop only when connecting
  to Redis, so the build's import gate runs against live Redis and PostgreSQL.
- Environment 1.1 GB, interpreter 123 MB.

## Consequences

- Base image updates no longer move the interpreter. Changing Python is a deliberate edit here.
- Add-ons without wheels need a compiler at runtime, which the runtime image does not carry. Those
  add-ons must ship wheels, or be built elsewhere. Documented in the README.
