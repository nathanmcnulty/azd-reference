# Component lifecycle standard

## States

- **Candidate**: useful implementation identified in a solution repository.
- **Pilot**: boundary and contract are being tested by selected consumers.
- **Stable**: versioned component supported for portfolio synchronization.
- **Deprecated**: supported temporarily with a documented replacement.
- **Retired**: no longer synchronized; existing consumers remain self-contained.

## Promotion criteria

A candidate becomes stable only when:

- its reusable behavior is distinct from solution-specific policy;
- ownership of every managed file is unambiguous;
- update and drift behavior are tested;
- authentication and secret boundaries are documented;
- at least two consumer shapes have been considered; and
- rollback means reverting the consumer commit, not reaching a private service.

## Versioning

Use semantic versions per component, beginning at `0.x` during pilots:

- patch: compatible fixes and documentation;
- minor: compatible capabilities or new optional fields;
- major: consumer changes are required.

Do not reuse a component version for different content. The lock records both the
component version and exact source commit. An optional portfolio baseline may
record a tested combination without forcing every solution to update together.

## Drift

Drift means a managed consumer file no longer matches the hash recorded in its
lock. Synchronization must stop before overwriting drift unless the author uses an
explicit override after reviewing the difference. Hashes detect drift; they do
not prove authenticity when an attacker can change both files and lock metadata.
