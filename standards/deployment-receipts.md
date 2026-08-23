# Deployment receipt standard

A deployment receipt records intended and applied configuration plus remaining
operational verification. It is distinct from a validation report, which records
checks actually executed.

The reusable receipt envelope contains:

- schema version and generation time;
- template name and version;
- deployment mode (`plan` or `enforce`);
- relative artifact references;
- applied, unchanged, skipped, warning, and failed operation counts;
- feature-specific details in an explicitly named `details` object; and
- unresolved operational actions such as consent or live delivery proof.

Receipts must not serialize local absolute paths, access tokens, callback URLs,
connection strings, or tenant values that are not necessary to understand the
deployment result.
