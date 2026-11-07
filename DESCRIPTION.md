Docassemble runs guided interviews that ask people questions and assemble letters, forms and PDFs from
their answers. Interviews are written in YAML with optional Python, and authored in the built-in
Playground. It is widely used by legal aid organisations and courts.

This package runs docassemble on Cloudron's own PostgreSQL, Redis, mail and sign-in. Your
configuration, uploaded files and add-on packages live with the app's data and are included in
Cloudron backups.

**Who can run code.** Docassemble interviews can contain Python. Anyone with a developer or
administrator account can write and run that code in the Playground, and it runs with the same access
as the app itself, which includes every stored answer and account in this app's database. People who
only answer interviews cannot run code. Give developer and administrator roles only to people you
would trust with all of this app's data.
