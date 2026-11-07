# Docassemble for Cloudron

> **Status: in development, not yet published.** Nothing here is ready to install. This README states
> the design; `docs/PACKAGING-NOTES.md` records what has been proven so far.

[Docassemble](https://docassemble.org) (MIT) runs guided interviews written in YAML and Python that
produce letters, forms and PDFs. It is widely used in legal aid. This package runs docassemble
**1.10.15** on Cloudron, built from `cloudron/base` and docassemble's published Python packages.

## How it is built

- **Cloudron supplies the services:** PostgreSQL, Redis (also the background-task broker), outgoing
  mail, sign-in through Cloudron's LDAP, TLS and the scheduled jobs. Nothing in the container keeps a
  database of its own.
- **The program lives in the image; your data lives in `/app/data`:** configuration, the secret key,
  uploaded files and add-on packages. Updates replace the program; backups hold only your data.
- **Your settings stay put.** `config.yml` is written once on first install and is yours to edit
  through docassemble's configuration editor. Values Cloudron controls (database, Redis, mail,
  hostname) are supplied fresh on every start, so they follow credential and domain changes.
- **Python 3.15**, the newest release, installed alongside the base image's own Python.
- The package follows every docassemble release.

The decisions behind this, and how it differs from the earlier v0.1 package, are in
[`docs/decisions/`](docs/decisions/), starting with
[ADR 0001](docs/decisions/0001-rebuild-on-cloudron-base.md).

## Who can run code

Docassemble interviews can contain Python. Anyone with a **developer** or **administrator** account
can write and run that code in the Playground, and it runs with the same access as the app itself,
which includes every stored answer and account in this app's database. People who only answer
interviews cannot run code. Give developer and administrator roles only to people you would trust with
all of this app's data, install add-on packages only from sources you trust, and use a separate
docassemble app if you need authors who should not see each other's users.

Background tasks are passed between processes in Python's `pickle` format, as upstream does. The
channel is this app's own password-protected Redis, which only this app can reach.

## Differences from upstream's Docker image

- **No inbound email.** Receiving mail needs a mail server inside the container, which this package
  does not run. Outgoing mail works through Cloudron.
- **SMS, fax, text-to-speech and machine translation start switched off**, which saves memory. They
  use outside services (for example Twilio) and can be turned on in the configuration.
- **Add-on packages must ship wheels.** The runtime image has no compiler.
- **One small code change:** the websocket server is patched to send the Redis password
  ([ADR 0003](docs/decisions/0003-websocket-redis-auth-patch.md)); the fix is offered upstream.

## Credits

timconsidine's community package showed the way on running docassemble with Cloudron's addons only,
using Redis as the task broker and generating secrets per install. Thank you.

## For maintainers

- [`AGENTS.md`](AGENTS.md): the working contract and settled decisions.
- [`docs/FOR-UPSTREAM.md`](docs/FOR-UPSTREAM.md) and [`docs/FOR-CLOUDRON.md`](docs/FOR-CLOUDRON.md):
  notes for the two projects this package sits between.
- `test/secret-scan.sh`: the release gate for secrets and private detail.
