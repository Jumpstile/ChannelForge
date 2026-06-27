\# Go / No-Go Checklist



A release is not ready because it works locally.



A release is ready only when we are willing to stand behind it.



\## Engineering



\- \[ ] Full test suite passes locally.

\- \[ ] CI is green.

\- \[ ] PSScriptAnalyzer is clean or documented.

\- \[ ] Code review is complete.

\- \[ ] No release-blocking TODOs remain.



\## Security



\- \[ ] Deep bug sweep completed.

\- \[ ] Vulnerability review completed.

\- \[ ] Secrets scan completed.

\- \[ ] Path validation reviewed.

\- \[ ] Input validation reviewed.

\- \[ ] Logging reviewed for secret leakage.

\- \[ ] Dependency review completed.



\## Safety



\- \[ ] Pre-operation backup tested.

\- \[ ] Post-operation backup tested.

\- \[ ] Restore process tested.

\- \[ ] Production writes require explicit approval.

\- \[ ] Failure modes are documented.



\## Documentation



\- \[ ] README updated.

\- \[ ] PROJECT.md updated if needed.

\- \[ ] STYLEGUIDE.md updated if needed.

\- \[ ] ADRs updated if architecture changed.

\- \[ ] Beginner instructions verified.

\- \[ ] Troubleshooting notes updated.



\## User Experience



\- \[ ] Fresh install tested.

\- \[ ] Upgrade tested.

\- \[ ] Error messages are understandable.

\- \[ ] Success messages are clear.

\- \[ ] User can verify outcome.



\## Decision



\- \[ ] GO

\- \[ ] NO-GO



If any required item is incomplete, the decision is NO-GO.

