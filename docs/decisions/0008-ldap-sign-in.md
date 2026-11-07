# 0008. LDAP sign-in with Cloudron's ldap addon

- **Status:** accepted, 2026-11-07. Fourth recorded exception to "never patch the application".

## Context

docassemble's LDAP sign-in (`users/forms.py`, `MySignInForm.validate`) binds as the user and then
calls `whoami_s()` (the LDAP WhoAmI extended operation, RFC 4532) to confirm the session. Cloudron's
LDAP server does not implement WhoAmI; measured on the lab box (Cloudron 10.1.6):

    PROTOCOL_ERROR ... '1.3.6.1.4.1.4203.1.11.3 not supported'

docassemble catches that error and falls back to local passwords, so every Cloudron user was refused
(gate 1, candidate 2: "Cloudron user signs in through LDAP: FAIL").

Removing the call is not enough on its own. The same server accepts an anonymous bind (an empty DN
with an empty password), and a sign-in decision must never rest on one.

## Decision

`image/patch-ldap.py` changes one block: before binding, refuse an empty bind DN or empty password
(raising `INVALID_CREDENTIALS`, which docassemble already handles by trying a local password), then
bind, and no longer call WhoAmI. The build stops unless the exact upstream block is found once.

The connection settings are refreshed on every start by `bin/owned-config.py` from the addon's
variables, in docassemble's `login with bind_dn` mode: search `mail=<email>` under the users base DN as
the app, then bind as the DN found with the user's password.

## Evidence (gate 1, candidate 3)

| Case | Result |
|---|---|
| Cloudron user, correct password | signed in; account row created with `ldap` social id and the `user` role |
| Cloudron user, wrong password | refused |
| local administrator (email not in LDAP), correct password | signed in through the local fallback |
| local administrator, wrong password | refused |

## Consequences

- Cloudron users become docassemble `user`s on first sign-in; an administrator grants `developer` or
  `admin`. Local accounts keep working (`optionalSso`).
- Any other LDAP server with the same properties is handled the same way. The general point was
  reported to upstream privately on 2026-11-07, as its security policy asks.
