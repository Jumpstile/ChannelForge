\# ChannelForge Engineering Charter



ChannelForge is a source-of-truth IPTV build system.



It is not tied to any single IPTV provider, playlist manager, or playback platform. Providers change. Applications change. Formats change. ChannelForge owns the data model and generates deployment artifacts for supported platforms.



\## Principles



1\. Source of truth  

&#x20;  One canonical representation of provider sources, EPG sources, channel rules, numbering rules, and output targets.



2\. Deterministic builds  

&#x20;  Same inputs must produce the same outputs.



3\. Explainable decisions  

&#x20;  Every category, number, and EPG decision must be traceable to a rule.



4\. Fail safely  

&#x20;  Validation happens before deployment. Production files are never overwritten without explicit approval.



5\. Secrets stay private  

&#x20;  Real provider URLs, account IDs, tokens, generated outputs, and backups must not be committed to public repositories.



6\. Test everything practical  

&#x20;  Parsers, rules, numbering, and reports should have Pester coverage before v1.0.

