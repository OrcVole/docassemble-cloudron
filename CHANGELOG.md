[0.1.0]
* New package for docassemble 1.10.15, built from cloudron/base 6.0.1 with Python 3.15. It replaces the earlier v0.1 package and is a fresh install, not an update to it.
* Services come from Cloudron addons: PostgreSQL, Redis (also the background-task broker), LDAP sign-in, outgoing mail and scheduled jobs.
* config.yml is written once and kept; settings changed in docassemble's editor survive restarts.
* Live help: the websocket server now sends the Redis password.
* Sign-in with Cloudron accounts through LDAP (docassemble's WhoAmI check replaced; anonymous binds refused).
* PDFs use Tinos, metric-compatible with Times New Roman; STIX Two Text and Source Serif 4 included. Your own fonts go in /app/data/fonts.
* Background OCR returns text again (two upstream bugs fixed); background tasks no longer share database connections under load.
* Memory limit 4.5 GiB, measured.
* Thanks to timconsidine, whose community package first ran docassemble on Cloudron addons with Redis as the task broker.
