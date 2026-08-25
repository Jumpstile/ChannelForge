# ChannelForge blocker #2 — standalone replacement contract: immutable generation promotion


Status: design/review evidence only. This contract supersedes the prior blocker #2 contracts, including comment 5410667973. It authorizes no implementation, branch, pull request, merge, deployment, or release decision.

## 1. Sole publication model

ChannelForge v2 uses immutable generation promotion. Acceptance never mutates an active M3U file, active XMLTV file, accepted output file, or accepted generation directory. A complete accepted generation is created under a private staging directory, validated, renamed once to an immutable generation directory, and made current only by atomically replacing one small accepted-generation pointer.

The only authoritative current pointer is:

state/accepted-lineup.json

The only authoritative previous pointer is the exact backup created by replacing the current pointer:

state/accepted-lineup.json.previous

The authoritative journal is:

state/accepted-lineup.journal.json

The authoritative journal backup is:

state/accepted-lineup.journal.json.previous

The immutable generation root is:

state/generations/

A generation directory is:

state/generations/<GenerationId>/

A generation contains exactly these files:

generation.manifest.json
accepted-state.json
accepted-output.manifest.json
decision-manifest.json
merged.m3u
merged.xml

merged.xml is present only when AcceptedXMLTVStatus is Generated. A generation directory never contains a subdirectory, cache, URL-bearing manifest field, absolute path, or reparse point. A generation directory is immutable after publication; any attempted modification, replacement, deletion, reparse conversion, or child addition causes fail-closed recovery.

The accepted-lineup pointer contains the complete generation identity and the relative generation directory. It does not contain output content. The accepted-output manifest inside the generation is authoritative for the output bytes. An accepted output is read by resolving the current pointer to its generation and then validating the generation manifest and output manifest. No output is inferred from output/, rollback/, caches, a prior build, or a source file.

Legacy compatibility files output/merged.m3u and output/merged.xml are non-authoritative. Build-Lineup and acceptance do not mutate them. A later explicitly scoped compatibility publisher may create them from the current generation, but that operation is not part of blocker #2 and cannot affect accepted state or recovery.

There is no active-output swap in this contract. Every acceptance crash resolves to the old pointer/generation or the new pointer/generation; there is no mixed accepted output state.

## 2. Physical paths, local authority, and path safety

All paths above are repository-relative paths beneath one verified local clone root. UNC paths, SMB paths, NAS paths, symbolic links, junctions, mount points, reparse points, alternate data streams, and paths escaping the clone root are rejected for state, candidates, generations, journals, staging, or outputs. The root and every parent are checked before opening and rechecked immediately before each mutation. A path is never accepted merely because its textual spelling appears contained.

The acceptance lock is:

state/lineup-operation.lock

The acceptance transaction staging directory is:

state/.staging/<TransactionId>/

Within it:

generation/<GenerationId>/
accepted-lineup.json
accepted-lineup.json.previous
accepted-lineup.journal.json
accepted-lineup.journal.json.previous

A candidate staging directory is separate:

output/candidates/.staging/<TransactionId>/

A final candidate namespace is:

output/candidates/<CandidateManifestHash>/

Decision staging is:

output/candidates/<CandidateManifestHash>/decisions/.staging-<DecisionManifestHash>-<TransactionId>/

The candidate and decision namespaces are immutable after their final directory move. A candidate namespace is never treated as accepted state. A decision namespace is never accepted unless its decision manifest is referenced by a newly accepted generation.

All final namespaces are created with Directory.Move from a verified staging directory. Directory.Move is permitted only when the final name is absent. If the final name exists, its complete manifest and every referenced artifact must byte-match the candidate; otherwise the operation fails closed. A final namespace is never overwritten or merged.

## 3. Canonical bytes and hash domains

Every canonical JSON file is UTF-8 without BOM, has no trailing newline, has the declared property order, contains no insignificant spaces, and uses LF only where a JSON string value itself contains a permitted newline. Objects contain exactly the declared properties; unknown properties, omitted required properties, duplicate properties, duplicate set members, and wrong nullability fail closed.

JSON strings are compared as Unicode scalar sequences before escaping. They are emitted with double quotes. The only short escapes are quote, reverse solidus, backspace, form feed, line feed, carriage return, and tab. Every other code point is emitted as lowercase \u followed by four lowercase hexadecimal UTF-16 code units; astral scalars are emitted as their two lowercase surrogate escapes. Solidus is not escaped. No locale, culture, parser order, filesystem order, enum declaration order, current time, randomness, cache state, or implementation-specific serializer participates.

Unsigned integer values are decimal ASCII with no leading zero except zero. Negative integers, floating point values, exponent notation, and numeric-looking strings where an integer is required are invalid. Booleans are true or false. Null is the only representation of a permitted absent value; missing and null are not interchangeable.

For domain D and canonical bytes B, H(D,B) is lowercase SHA-256 over UTF-8 bytes of D, one byte 00, then B. Domain strings are exact ASCII. No other hash formula is permitted.

The exhaustive v2 semantic domain inventory is:

pointer/v2
logical-source-key/v2
logical-source-id/v2
entry-id/v2
review-id/v2
binding-key/v2
binding-record/v2
input-m3u/v2
raw-m3u-occurrence/v2
candidate-m3u/v2
input-xmltv/v2
raw-xmltv-occurrence/v2
raw-programme/v2
guide-candidate-occurrence/v2
candidate-xmltv/v2
stream-fingerprint/v2
safe-text-policy/v2
safe-tvg-name-fingerprint/v2
structural-evidence/v2
collision-evidence/v2
candidate-manifest/v2
candidate-review-json/v2
candidate-review-markdown/v2
decision-manifest/v2
decision-m3u/v2
decision-xmltv/v2
output-manifest/v2
previous-output-manifest/v2
generation-manifest/v2
accepted-state/v2
active-m3u/v2
active-xmltv/v2
previous-m3u/v2
previous-xmltv/v2
journal/v2

Every semantic hash field names its domain and projection. A semantic hash excludes absolute paths, relative storage paths, directory names, file identity, volume identity, timestamps, lock identity, transaction IDs, stage names, backup names, and audit-only metadata unless this contract explicitly says otherwise. Therefore identical logical input produces identical semantic bytes and hashes on different filesystems.

Operational filesystem metadata is separate. FileIdentity is:

{ VolumeSerial: unsigned integer, FileId: lowercase 64-hex stable file identifier, ByteLength: unsigned integer, LastWriteUtcTicks: unsigned integer }

FileIdentity is obtained only from the opened file handle and is used only in Journal MutationRecord expected-old/new checks. FileIdentity never participates in CandidateManifestHash, DecisionManifestHash, OutputManifestHash, GenerationManifestHash, AcceptedStateHash, or BuildIdentity.

No content-addressed object contains a self-artifact. CandidateManifestHash omits its own hash property and contains no ArtifactRecord for itself. DecisionManifestHash omits its own hash. OutputManifestHash, GenerationManifestHash, AcceptedStateHash, PointerHash, and JournalHash each omit only their own hash property. A hash dependency always points backward:

raw source -> candidate artifact/manifest -> decision -> output manifest/state -> generation manifest -> accepted pointer.

A candidate namespace path is derived from CandidateManifestHash but the path is not a hash input. A generation directory name is GenerationId and is not a semantic hash input. The parent generation hash in a decision is the hash of a pre-existing generation and is never the hash of the generation being created. The dependency graph is acyclic.

SHA-256 provides deterministic identity, integrity, corruption detection, and change detection under a trusted local filesystem and ACL model. It does not authenticate a hostile local writer who can replace both bytes and hashes. Authentication against such a writer is out of scope.

## 4. Source identity and safe text

LogicalSourceId is H(logical-source-id/v2, canonical LogicalSourceIdInput). LogicalSourceKey is a length-prefixed tuple, not a delimiter-concatenated string:

LogicalSourceKeyInput = { ProviderName, SourceName, SourceKind, SourceOrdinal }

Each component is a Unicode string encoded as an unsigned UTF-8 byte length followed by its UTF-8 bytes; SourceOrdinal is an unsigned integer. Empty components are allowed only where the schema says so. U+001F is ordinary data and cannot collide with another tuple. The source key is lower-level identity only; it does not authorize a URL or credential.

SafeTextPolicyV1 is exact. A value is Digest rather than Text if it contains a NUL, CR, LF, any C0 control other than TAB, DEL, a code point outside the permitted scalar set, an absolute Windows path, a rooted Windows path, a POSIX absolute path, a UNC path, a recognized URI scheme token, or a value that fails the required field grammar.

Windows drive absolute path: ASCII letter, colon, then slash or reverse solidus; rooted Windows path: slash or reverse solidus at the beginning; POSIX absolute path: slash at the beginning. UNC path: two consecutive slash or reverse solidus characters followed by a non-empty server component, one separator, and a non-empty share component. Both slash and reverse solidus are separators for detection; mixed separators are still detected. A drive letter is exactly one ASCII letter followed by colon; malformed near-misses such as 1:\x, A;:\x, or A:\ with no path segment are not drive paths unless another rule matches. UNC server/share components end at the next separator, cannot be empty, and cannot contain NUL, CR, LF, or a separator.

Scheme detection uses only ASCII letters as the first character and ASCII letters, digits, plus, hyphen, and period thereafter; length is 2 through 32; the token must start at position zero or after a non-ASCII-alphanumeric boundary; it must be followed immediately by colon; case is folded to ASCII lower only for deciding whether a scheme is present; no whitespace is allowed between token and colon. A colon elsewhere is not a scheme. Recognized schemes are http, https, rtmp, rtsp, ftp, file, data, ssh, and credential-bearing or provider-specific tokens matching this grammar. A path/scheme match emits Digest; otherwise permitted field text emits Text. SafeTextPolicyV1 itself is hashed in safe-text-policy/v2.

SafeTvgNameFingerprint is H(safe-tvg-name-fingerprint/v2, SafeTvgNameInput), where SafeTvgNameInput property order is Version, RawTvgName, SafeDisplayText, PolicyResult. RawTvgName is the exact parsed value; SafeDisplayText is the exact SafeTextPolicyV1 result when Text and null when Digest; PolicyResult is Text or Digest. No Unicode normalization, trim, case folding, or path redaction is applied to RawTvgName. SafeTvgNameFingerprint is presentation evidence only. It is not M3U/XMLTV binding evidence, an identity key, or a replacement for RawTvgId. It may be included in presentation evidence and output fields but never in GuideCandidateEvidenceDigest.
