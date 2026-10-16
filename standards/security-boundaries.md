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
- Never execute consumer code while holding a cross-repository write token.

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

## Portfolio updater

Cross-repository draft publication is implemented in
[the portfolio update workflow](../docs/portfolio-updates.md#automated-draft-update-pull-requests).
It uses a GitHub App limited to registered repositories with Contents write,
Pull requests write, and Metadata read. It must never approve or merge its PRs.
Consumer validation runs on a credential-free preparation runner; the App token
exists only on a separate publication runner that restores the validated branch.

Manual dispatch requires an exact consumer ID and defaults to plan-only. That
mode does not prepare branches, request the publication environment, mint an App
token, or publish. Every publication candidate is rechecked against the trusted
registry and requested consumer before App authentication; downloaded bundles
cannot select a different repository, component, version, or branch. Scheduled
and registry-triggered runs retain the existing portfolio-wide scope.

Implementation is not evidence of operational App configuration or a successful
publication. Verify a real bounded draft-PR run separately before claiming that
end-to-end publication works.
