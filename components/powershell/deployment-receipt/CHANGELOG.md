# Deployment receipt changelog

## 0.1.0

- Add a candidate shared writer for deployment receipt schema version 1.0.
- Default output to `reports/deployment-receipt.json` and write only within a
  non-reparse repository root through an atomic temporary file.
- Reject obvious credential-bearing keys and values before schema validation.
- Keep this component unintegrated until a solution adopts the producer path.
