# Changelog

## 0.1.0

Initial pilot of a shared Intune data-gathering script package publisher and
readback helper. AV exclusions and Firewall traffic are independently packaged
consumers. Publication uses an explicit Graph caller, matching target/collector
tenant assertions, hashed script files, reviewed assignment targets, and a daily
schedule. Control-plane acceptance does not establish endpoint execution.
