# Candidate v7 and successor impact matrix

Generated from paired `Build-Candidate.ps1` runs using `tests/fixtures/tiny.m3u` and `tests/fixtures/xmltv/sample.xml`.

| Artifact | v7 SHA-256 | Successor SHA-256 | Classification |
|---|---|---|---|
| `lineup-change-review.json` | `a7d826dfbe9ce9ffe269de5c85cf08a8752ec6d09940422fa23d63d78c583983` | `d6a76a9f2b602b9219aa24ecdf738a8ecd9c73a5d968eb8da88bdd2284261b34` | Changed |
| `lineup-change-review.md` | `6814edfb460c45d7c2ef458166ce2b431cc7ae02829a7d6d3f6edbfd9d6c5b9c` | `f660ad0c7803b094db40a4deec455ca3c7567b4e9e369ddbd7884ac1cacb7a69` | Changed |
| `manifest.json` | `9defbe7d6b03911aa36552150c4f93be9f0ec01f4affe43440b110cebac62fdf` | `476ad881caa9d3b0ada1a281ee0f819ea94da5bb242fa494319c8efb2ce31e6e` | Changed |
| `merged.m3u` | `a9e8f1aa66d6d07035b72c786c2d842a247e284ac0be29cca6d6c41dfa557c5d` | `a9e8f1aa66d6d07035b72c786c2d842a247e284ac0be29cca6d6c41dfa557c5d` | Preserved |
| `merged.xml` | `ec6c020de3642d317977a04dcc5ee4b37ee68d468aeed76599d194416230dd75` | `ec6c020de3642d317977a04dcc5ee4b37ee68d468aeed76599d194416230dd75` | Preserved |
| `BuildIdentity` | `6c2d3e2b0b65c6ac25f60a3731ae9aa3bab5c8154c60c83f6acb2e83dec3e25b` | `13366587bbe2c57fadc5eed32ff175a5d69fb8df2da627c1c9eed5f13a980ffd` | Changed |
| `CandidateManifestHash` | `9defbe7d6b03911aa36552150c4f93be9f0ec01f4affe43440b110cebac62fdf` | `476ad881caa9d3b0ada1a281ee0f819ea94da5bb242fa494319c8efb2ce31e6e` | Changed |

The final two rows are identity/evidence outputs, not additional files; `CandidateManifestHash` is the SHA-256 of the corresponding `manifest.json` bytes. v7 defaults remain unchanged by the successor switch.
