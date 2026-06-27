\# ADR 0002: Secrets stay out of Git



\## Status



Accepted



\## Context



Provider URLs may contain account IDs, tokens, usernames, or passwords. Even private repositories can later be shared, made public accidentally, or accessed by collaborators.



\## Decision



Real provider credentials and tokenized URLs must not be committed to Git.



Tracked files may contain examples or schemas. Local secret files must be ignored.



\## Consequences



\- Use `provider.example.json` for templates.

\- Use `provider.local.json` for real provider data.

\- Keep generated outputs, backups, databases, and logs out of Git.

