This app has its own administrator account, separate from your Cloudron account. Its email address
and password are generated for this install and shown in the checklist. Sign in with them first, then
change the password.

Cloudron users can sign in with their Cloudron email address and password. They start as ordinary users;
an administrator decides who becomes a developer.

### Developer accounts can see everything this app holds

Docassemble interviews are written in YAML and Python, and the Playground is where authors write and
test them. That Python runs inside this app with the same access as docassemble itself. In practice,
an interview author can read:

- every user's stored interview answers and account details, because the code can use the app's own
  database connection;
- uploaded files; and
- the app's mail settings.

It cannot reach other apps' databases, because Cloudron gives each app its own. Like any code on the
server, it can make network requests.

None of this applies to the people who answer your interviews: they only ever run what an author has
published. It applies to accounts with the **developer** or **administrator** role, and to any add-on
package an administrator installs.

So: give developer and administrator roles only to people you would trust with all of this app's
data, install add-on packages only from sources you trust, and use a separate docassemble app if you
need authors who should not see each other's users.
