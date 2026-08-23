# Security boundaries

## Reference source

`azd-reference` is trusted by maintainers during authoring and synchronization.
It is not trusted implicitly by a deployed solution. Consumers execute only the
vendored files reviewed and committed in their own repositories.

The consumer lock detects local drift and records provenance. It is not a digital
signature: anyone able to change both a managed file and its lock entry can
recalculate the hash.

## Synchronization

- Resolve every source and target beneath an explicit root.
- Reject absolute paths, parent traversal, symlinks, and reparse-point traversal.
- Pin the exact source commit and hash exact checked-out bytes.
- Refuse dirty canonical source and dirty managed consumer files.
- Stage all files before replacement and restore prior content on failure.
- Never infer file deletion from a changed manifest.
- Never execute consumer code while holding a future cross-repository write token.

## Authentication

- Reuse an exact cached tenant, subscription, environment, and scope match.
- Aggregate required scopes and permit at most one normal browser/broker connection
  for a lifecycle operation.
- Never use device-code authentication.
- Noninteractive automation fails with remediation when its workload identity is
  insufficient; it does not fall back to an interactive flow.

## Sensitive delivery endpoints

Webhook URLs, Logic App callback URLs, SAS query strings, and authorization query
parameters are bearer credentials. Treat them as secrets and exclude them from
receipts, validation reports, locks, logs, and ordinary outputs.

## Future updater

Cross-repository update automation is deferred. When introduced, use a GitHub App
limited to selected repositories with Contents write, Pull requests write, and
Metadata read. It may open update pull requests but must never approve or merge
them. Remove the installation token before consumer CI executes.
