# Changelog

## 0.1.5

Treat device run-state IDs as opaque service strings and preserve them exactly in
evidence. Resolve managed-device identity from the expanded relationship, then
verify it through the canonical managed-device resource without putting the
opaque state ID in a URI. Omit the live-rejected `isGlobalScript` property from
PATCH bodies while retaining it in exact readback validation.

## 0.1.4

Accept native unfiltered zero-GUID filter metadata and exact composite assignment
IDs. Include/exclude filter types remain distinct and fail the unfiltered guard.

## 0.1.3

Use the documented whole-set assign action for script assignment; the individual
assignment POST route was rejected by the live commercial service. Preserve exact
complete-set guards and durable pre-write checkpoints.

## 0.1.2

Accept the native schedule type with or without the optional OData hash prefix.

## 0.1.1

Treat Intune's observed service version separately from the local package authoring
version. Bind reuse to the full current service state and exact script bytes.
Targeted runs also verify the exact daily UTC schedule, and allow only the reviewed
no-op companion hashes when on-demand execution could invoke remediation.

## 0.1.0

Initial pilot of a shared Intune data-gathering script package publisher and
readback helper. AV exclusions and Firewall traffic are independently packaged
consumers. Publication uses an explicit Graph caller, matching target/collector
tenant assertions, hashed script files, reviewed assignment targets, and a daily
schedule. Control-plane acceptance does not establish endpoint execution.
