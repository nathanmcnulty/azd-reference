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

## 0.1.2

- Verify complete component lock schema and every copied host entry point.
- Reject non-hexadecimal schedule package hashes at the template boundary.
- Stage explicitly declared companion artifacts and verify their hashes before execution.
- Constrain hosted file references to the downloaded evidence root.

- Reuse an already uploaded immutable package only after verifying its downloaded content hash; never overwrite it.

## 0.1.3

- Require the configured engine entry point to be tracked in the reviewed source commit.
