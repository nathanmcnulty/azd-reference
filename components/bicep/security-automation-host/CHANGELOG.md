# Changelog

## 0.1.0

- Optional PowerShell 7.4 Flex, Automation and Logic App orchestration hosts.
- Local mode provisions no resources; scheduled processing starts disabled.
- Private Blob containers and managed identity storage access, without Graph grants.

## 0.1.1

- Separate Function host storage and scope evidence/package readers and report writers to containers.
- Refresh scheduled bundle parameters after publication and verify Automation pause requests.
- Reject dirty sources, component drift, mixed runtime revisions and unsafe POST pagination.
- Upload a final report completion manifest; keep incomplete prefixes unaccepted.
- Add azd hooks and package/transition regression tests.
