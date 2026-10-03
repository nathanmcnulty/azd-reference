# Changelog

## 0.1.0

- Pilot PowerShell evidence processing runtime for local, Function and Automation hosts.
- Read-only Graph transport, private Blob evidence transfer, bounded pagination and immutable runbook packages.
- Scheduled processing emits review artifacts; publishing policies requires a separate workflow.

## 0.1.1

- Separate Function host storage and scope evidence/package readers and report writers to containers.
- Refresh scheduled bundle parameters after publication and verify Automation pause requests.
- Reject dirty sources, component drift, mixed runtime revisions and unsafe POST pagination.
- Upload a final report completion manifest; keep incomplete prefixes unaccepted.
- Add azd hooks and package/transition regression tests.
