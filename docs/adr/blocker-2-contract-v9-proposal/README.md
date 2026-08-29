# ChannelForge blocker #2 contract erratum — EntryOutputSlice

Status: CONTRACT CANDIDATE; not frozen.

This successor proposal is scoped to candidate construction and the
EntryOutputSlice semantic surface. Candidate-owned Version fields advance
uniformly from v7 to v8 in successor output; the complete ownership and
algorithm-domain mapping is recorded in VERSION-OWNERSHIP-MAP.md. Normative
ownership of decision, accepted-state, generation, pointer, journal,
promotion, and recovery surfaces is retained, but their runtime implementation
is outside Issue #109.

The current frozen authority remains `blocker-2-contract/v8` with
RevisionContentId `d80feb5b24a4c335badb288fe0d82339f84a0d6b417d3a0a5fc3f38f2b07c69d`.

Proposed successor revision: `blocker-2-contract/v9`.
Proposed candidate contract version: `blocker-2-contract/v8`.
Acceptance contract version remains `blocker-2-contract/v8-acceptance`.

Acceptance, promotion, recovery, XMLTV lineage, pointer, journal, and
decision-manifest runtime semantics are unchanged. Issue #102 remains blocked
until this successor is approved and frozen.

See PART-B for the normative candidate-slice rules.

Full CandidateContractVersion v8 registry activation is a prerequisite owned
by Issue #110. Until that migration is complete, production candidate-v8
activation is fail-closed; the bounded private slice producer is the only
successor-shaped implementation surface exercised by this erratum.
