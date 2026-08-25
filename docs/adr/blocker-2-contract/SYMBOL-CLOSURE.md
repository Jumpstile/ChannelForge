# Symbol closure

This document adds only the nine known closure items identified after architectural acceptance. Each symbol below has exactly one normative definition in this directory. These definitions do not rewrite the moved contract.

## 1. StructuralEvidenceHash

Domain: structural-evidence/v2.

StructuralEvidenceInput property order is:

Version, LogicalSourceId, ElementKind, StructuralOrdinal, RawOccurrenceDigest, DuplicateCount

ElementKind is M3U or XMLTVChannel or XMLTVProgramme. StructuralOrdinal is zero-based. For M3U it is SourceLocalOrdinal; for XMLTVChannel and XMLTVProgramme it is StructuralOccurrenceOrdinal. RawOccurrenceDigest is the complete raw occurrence digest for that element. DuplicateCount is the exact multiplicity of byte-identical raw occurrences represented by the retained occurrence.

StructuralEvidenceHash is:

H(structural-evidence/v2, canonical StructuralEvidenceInput)

The hash projection contains all six properties and no filesystem path, parser/input ordinal, transaction identifier, timestamp, cache value, or SafeDisplayFingerprint. StructuralEvidenceHash is evidence only; it is not guide-binding equality and is not an EntryId.

## 2. CollisionIdentity and CollisionEvidenceDigest

CollisionIdentity property order is:

Version, LogicalSourceId, HistoryKeyPresence, HistoryKey, CollisionKind

HistoryKeyPresence is Present or Missing. HistoryKey is required when Present and null when Missing. CollisionKind is MissingOnly, PresentCollision, MixedMissingAndPresent, or None.

CollisionEvidenceInput property order is:

Version, CollisionIdentity, RawIdentityDigests, EntryIds, MissingIdentityCount, IdentityPopulation

RawIdentityDigests and EntryIds are unique lowercase 64-hex strings, sorted by ascending ordinal byte/string order. Duplicate array members are invalid. RawIdentityDigests contains the retained raw-occurrence digests participating in the group; EntryIds contains the corresponding unique EntryIds. MissingIdentityCount counts only Missing raw IDs. IdentityPopulation counts every raw occurrence in the group, including Missing and Present. The invariant is:

IdentityPopulation = MissingIdentityCount + count of Present raw occurrences

CollisionEvidenceDigest is:

H(collision-evidence/v2, canonical CollisionEvidenceInput)

CollisionIdentity is the grouping identity and is not inferred from EntryId order. A MixedMissingAndPresent group contains the missing population and every present occurrence that maps to the same LineupHistory-v1 key. Collision evidence is ReviewNeeded evidence and can never authorize ExactBound.

## 3. ReviewEvidenceType ranks

ReviewEvidenceType is a closed enum. Unknown values fail closed.

- GuideCandidate -> 10
- CandidateEntry -> 20
- AcceptedEntry -> 30
- Collision -> 40
- Source -> 50
- Binding -> 60

Evidence arrays sort first by this integer rank. The rank is normative and independent of spelling, declaration order, or implementation enum values.

## 4. GuideReason ranks

GuideReasonCode is a closed enum. Unknown values fail closed.

- ExactOrdinalMatch -> 10
- MissingM3UId -> 20
- MissingXMLTVId -> 30
- EmptyXMLTVId -> 40
- WhitespaceXMLTVId -> 50
- NoXMLTVMatch -> 60
- DuplicateXMLTVId -> 70
- M3UIdentityCollision -> 80
- AmbiguousXMLTVCandidates -> 90
- ConflictingIdentity -> 100
- InvalidSourceSet -> 110

GuideReasonCode ranks are used for deterministic BindingRecord and guide ReviewRecord ordering. The rank never changes the raw ordinal-equality predicate.

## 5. ChangeReason ranks

ChangeReasonCode is a closed enum. Unknown values fail closed.

- NoChange -> 10
- AddedIdentity -> 20
- RemovedIdentity -> 30
- RenamedPresentation -> 40
- StreamChanged -> 50
- StreamAndPresentationChanged -> 60
- RawIdentityChanged -> 70
- MissingIdentity -> 80
- IdentityCollision -> 90
- AmbiguousMatch -> 100
- InsufficientEvidence -> 110

ChangeReasonCode is a reason/evidence field only. Classification precedence remains the ChangeRecord precedence in PART-B. Reason rank does not permit automatic rename or guide binding.

## 6. ArtifactRole ranks

ArtifactRole is a closed enum. Unknown values fail closed.

- CandidateM3U -> 10
- CandidateXMLTV -> 20
- CandidateReviewJSON -> 30
- CandidateReviewMarkdown -> 40
- DecisionManifest -> 50
- AcceptedM3U -> 60
- AcceptedXMLTV -> 70
- AcceptedOutputManifest -> 80
- AcceptedState -> 90
- GenerationManifest -> 100
- Pointer -> 110
- Journal -> 120

ArtifactRecord arrays sort by ArtifactRole rank, then RelativePath ordinal bytes. ArtifactRole is a semantic role label; its rank is not a filesystem path and does not participate in a content hash except through the declared ArtifactRecord projection.

## 7. Journal schema

Journal property order is:

Version, TransactionId, JournalStage, ExpectedOldPointerHash, ExpectedNewPointerHash, ExpectedOldGenerationId, ExpectedNewGenerationId, MutationRecords, OldJournalHash, JournalHash

Version is the literal integer 2. TransactionId is a non-empty lowercase 32-hex operational identifier. JournalStage is the closed enum None, Prepared, GenerationPublished, PointerSwapped, or Committed with ranks None=0, Prepared=1, GenerationPublished=2, PointerSwapped=3, Committed=4. Unknown stages fail closed.

ExpectedOldPointerHash and ExpectedNewPointerHash are null or lowercase 64-hex PointerHash values. ExpectedOldGenerationId and ExpectedNewGenerationId are null or lowercase 32-hex GenerationId values. Prepared requires ExpectedNewPointerHash and ExpectedNewGenerationId; GenerationPublished additionally requires a published final generation; PointerSwapped additionally requires the new pointer and, when an old pointer existed, its exact .previous backup. Committed requires the complete new pointer/generation pair.

MutationRecords is an array of unique MutationRecord objects sorted by MutationOrdinal ascending. OldJournalHash is null only for None -> Prepared when no prior authoritative journal exists. For every later publication it is a lowercase 64-hex hash of the prior authoritative journal. JournalHash is lowercase 64-hex and is calculated over this object with JournalHash omitted. NewJournalHash is not a property.

Journal publication is valid only after staged bytes are written, Flush(true) completes, the file is closed, reopened, schema/hash verified, and the authoritative replacement succeeds. The authoritative destination is state/accepted-lineup.journal.json; its backup is state/accepted-lineup.journal.json.previous.

## 8. MutationRecord schema

MutationRecord property order is:

MutationOrdinal, MutationKind, RelativePath, ExpectedOldPresence, ExpectedOldByteHash, ExpectedOldFileIdentity, ExpectedNewPresence, ExpectedNewByteHash, ExpectedNewFileIdentity

MutationOrdinal is a unique zero-based integer in journal operation order. MutationKind is the closed enum Create, Replace, Move, Delete, or Verify. RelativePath is a fixed repository-relative path and cannot be absolute, UNC, or reparse-based.

ExpectedOldPresence and ExpectedNewPresence are Present or Absent. A Present expected byte hash is a lowercase 64-hex content hash in the artifact's declared domain; an Absent hash is null. ExpectedOldFileIdentity and ExpectedNewFileIdentity are null when the corresponding presence is Absent and otherwise are FileIdentity objects. MutationRecord is operational journal metadata. Its FileIdentity values, path, transaction, and ordinal are excluded from every semantic hash.

Each MutationRecord describes one exact operation boundary. Create requires old Absent/new Present; Delete requires old Present/new Absent; Replace requires both Present; Move records the source and destination as two records with distinct ordinals; Verify leaves bytes unchanged and records equal old/new identities. A mismatch of expected presence, byte hash, or FileIdentity stops recovery and yields FAIL_CLOSED_RECOVERY_REQUIRED.

## 9. FileIdentity schema

FileIdentity property order is:

VolumeSerial, FileId, ByteLength, LastWriteUtcTicks

VolumeSerial, ByteLength, and LastWriteUtcTicks are unsigned decimal integers. FileId is a non-empty lowercase 64-hex identifier obtained from the opened local file handle. FileIdentity is present only for an existing regular file and is null for an absent path. FileIdentity is collected after reopening and before each mutation, then checked again immediately before mutation.

FileIdentity is operational recovery metadata only. It never participates in CandidateManifestHash, DecisionManifestHash, OutputManifestHash, GenerationManifestHash, AcceptedStateHash, PointerHash, JournalHash, BuildIdentity, StructuralEvidenceHash, or CollisionEvidenceDigest. A changed FileIdentity is a TOCTOU failure even when the semantic content hash is unchanged.

## Closure inventory

The following symbols each have exactly one definition in this artifact directory:

- hash domains: structural-evidence/v2, collision-evidence/v2
- enums: ReviewEvidenceType, GuideReasonCode, ChangeReasonCode, ArtifactRole, JournalStage, MutationKind
- schemas: StructuralEvidenceInput, CollisionIdentity, CollisionEvidenceInput, Journal, MutationRecord, FileIdentity
- property orders: StructuralEvidenceInput, CollisionIdentity, CollisionEvidenceInput, Journal, MutationRecord, FileIdentity
- projections: StructuralEvidenceHash, CollisionEvidenceDigest, JournalHash, MutationRecord operational projection
- recovery classifications: INITIAL_BASELINE_REQUIRED, ACCEPTED_STATE_VALID, FAIL_CLOSED_RECOVERY_REQUIRED
