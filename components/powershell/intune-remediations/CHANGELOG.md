# Changelog

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
