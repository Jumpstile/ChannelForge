# ChannelForge blocker #2 contract erratum — EntryOutputSlice

Status: FROZEN.

This frozen successor revision is scoped to candidate construction and the
EntryOutputSlice semantic surface. Candidate-owned Version fields advance
uniformly from v7 to v8 in successor output; the complete ownership and
algorithm-domain mapping is recorded in VERSION-OWNERSHIP-MAP.md. Normative
ownership of decision, accepted-state, generation, pointer, journal,
promotion, and recovery surfaces is retained, but their runtime implementation
is outside Issue #109.

The predecessor frozen authority is `blocker-2-contract/v8` with
RevisionContentId `d80feb5b24a4c335badb288fe0d82339f84a0d6b417d3a0a5fc3f38f2b07c69d`.

Frozen successor revision: `blocker-2-contract/v9`.
Candidate contract version: `blocker-2-contract/v8`.
Acceptance contract version remains `blocker-2-contract/v8-acceptance`.

Acceptance, promotion, recovery, XMLTV lineage, pointer, journal, and
decision-manifest runtime semantics are unchanged. Issue #102 remains blocked;
freezing this narrow erratum does not resume #102.

See PART-B for the normative candidate-slice rules.

Normative frozen content is exactly these four files:

- `PART-A-canonical-foundation.md`
- `PART-B-entry-output-slice.md`
- `README.md`
- `VERSION-OWNERSHIP-MAP.md`

`IMPACT-MATRIX.md`, tests, implementation files, and `FREEZE-RECORD.md` are
non-normative and excluded from the RevisionContentId projection. The exact
RevisionContentId is recorded in `FREEZE-RECORD.md` to avoid self-reference.

Full CandidateContractVersion v8 registry activation is a prerequisite owned
by Issue #110. Until that migration is complete, production candidate-v8
activation is fail-closed; the bounded private slice producer is the only
successor-shaped implementation surface exercised by this erratum.
