# Security policy

Snippet Studio edits files that often hold private text, so security reports are taken seriously.

## Reporting a vulnerability

Please **don't open a public issue.** Report it privately through GitHub's
[private vulnerability reporting](https://github.com/bbenjyesq/snippet-studio/security/advisories/new)
(Security tab → "Report a vulnerability").

Include what an attacker could do, the steps or file needed to reproduce it, and the version (commit) you tested.
Use invented data only.

## Scope

In scope are crashes or data loss caused by crafted match files, any path where the app could change files other than the
snippet being edited or write outside Espanso's match folder and its own Snippet Studio folder, and anything that could
expose snippet text.

Snippet Studio has no network access, so reports about servers or accounts don't apply.
