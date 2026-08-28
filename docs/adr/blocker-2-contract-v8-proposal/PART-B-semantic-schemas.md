## 4. Exact successor schemas

All listed objects use the property order shown. Required properties may not be missing. Null is permitted only where stated. Arrays are unique, sorted by the stated key, and duplicates are invalid.

| Domain | Ordered schema and rules |
|---|---|
| `pointer/v2` | `Version,GenerationId,GenerationManifestHash,AcceptedStateHash,AcceptedOutputManifestHash,PointerHash`; all except PointerHash are required lowercase IDs/hashes; PointerHash omits itself; hash domain `pointer/v2`. |
| `accepted-state/v2` | `Version,GenerationId,BuildIdentity,CandidateManifestHash,DecisionManifestHash,AcceptedOutputManifestHash,IncludedCandidateEntryIds,ExcludedCandidateEntryIds,AcceptedBindingIds,AcceptedXMLTVStatus,AcceptedAtUtc,AcceptedStateHash`; IDs arrays sorted unique; AcceptedAtUtc is RFC3339 UTC metadata excluded from semantic hash; hash domain `accepted-state/v2`. |
| `active-m3u/v2` | Exact candidate M3U byte projection: `Version,GenerationId,AcceptedStateHash,OutputManifestHash,ContentHash,ByteLength,RelativePath`; ContentHash is direct domain hash of exact bytes; no URL/path outside fixed relative path; hash domain `active-m3u/v2`. |
| `active-xmltv/v2` | `Version,GenerationId,AcceptedStateHash,OutputManifestHash,Status,ContentHash,ByteLength,RelativePath`; Status Generated requires all content fields; NotGenerated requires ContentHash=null, ByteLength=0, RelativePath=null; hash domain `active-xmltv/v2`. |
| `previous-m3u/v2` | Same ordered fields as active-m3u plus `PreviousGenerationId`; exact prior accepted artifact only; null is forbidden; hash domain `previous-m3u/v2`. |
| `previous-xmltv/v2` | Same ordered fields as active-xmltv plus `PreviousGenerationId`; Generated/NotGenerated null rules identical; hash domain `previous-xmltv/v2`. |
| `decision-m3u/v2` | `Version,CandidateManifestHash,BuildIdentity,AcceptedParentGenerationManifestHash,IncludedCandidateEntryIds,ExcludedCandidateEntryIds,DecisionIds,DecisionManifestHash`; arrays sorted unique; candidate/parent hashes required; self hash omitted; hash domain `decision-m3u/v2`. |
| `decision-xmltv/v2` | `Version,CandidateManifestHash,BuildIdentity,AcceptedParentGenerationManifestHash,AcceptedXMLTVStatus,IncludedCandidateEntryIds,ExcludedCandidateEntryIds,DecisionIds,DecisionManifestHash`; XMLTV status null rules match active XMLTV; self hash omitted; hash domain `decision-xmltv/v2`. |
| `generation-manifest/v2` | `Version,GenerationId,BuildIdentity,CandidateManifestHash,DecisionManifestHash,AcceptedStateHash,AcceptedOutputManifestHash,ActiveM3UHash,ActiveXMLTVHash,PreviousOutputManifestHash,GenerationManifestHash`; all hashes required except PreviousOutputManifestHash on first generation; self hash omitted; hash domain `generation-manifest/v2`. |
| `previous-output-manifest/v2` | `Version,GenerationId,ActiveM3UHash,ActiveXMLTVHash,AcceptedStateHash,OutputManifestHash`; exact previous generation output references; first generation is absent, never null object; self hash omitted; hash domain `previous-output-manifest/v2`. |

Exact byte serialization is compact ordered UTF-8 JSON with no BOM or trailing newline. Numeric ByteLength is unsigned decimal. Relative paths are fixed names within the generation namespace. A generation is coherent only if every hash and ID chain resolves to the same GenerationId and CandidateManifestHash.

## 5. DuplicateCount disposition

`DuplicateCount` is derived evidence owned by the occurrence population. It is not a member of RawM3UOccurrence, RawXMLTVChannelOccurrence, or RawProgrammeOccurrence and is excluded from their occurrence digests. It equals the number of non-representative exact duplicates associated with a selected representative; the representative is excluded. It is an unsigned 32-bit integer in review/collision evidence and is carried only where multiplicity is reported.

## 6. Journal authority

The Journal schema is defined exactly once in PART-C. References to journal fields, phases, OldJournalHash, and JournalHash refer to that definition and do not create a competing field sequence here.
