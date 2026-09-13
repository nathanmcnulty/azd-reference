# Deployment receipt changelog

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
