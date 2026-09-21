# Deployment receipt changelog

## 0.2.1

- Reissue the unchanged 0.2 evidence-binding contract at a new immutable patch
  version so maintainers can create a signed, GitHub-verified release tag.
- The published 0.2.0 tag remains immutable but is not an attested release because
  its annotated tag object was unsigned.

## 0.2.0

- Add optional schema 1.1 management evidence binding for project, target,
  source, and operation correlation while retaining unbound schema 1.0 output.
- Add bounded, allowlisted next actions with explicit owners and priorities.
- Keep arbitrary receipt details, operational-action text, and artifact paths
  outside the management projection boundary.

## 0.1.1

- Revalidate direct receipt objects before writing, including receipt identity,
  bounded collection counts, and artifact text.
- Reject ambiguous output paths and recheck the target directory and path
  components before the atomic move.
- The writer detects obvious sensitive values and unsafe paths; it cannot prove
  that arbitrary free text contains no secret, and a same-user process can
  still replace filesystem paths after the final reparse-point check.

## 0.1.0

- Add a candidate shared writer for deployment receipt schema version 1.0.
- Default output to `reports/deployment-receipt.json` and write only within a
  non-reparse repository root through an atomic temporary file.
- Reject obvious credential-bearing keys and values before schema validation.
- Keep this component unintegrated until a solution adopts the producer path.
