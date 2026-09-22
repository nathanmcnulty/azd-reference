# Catalog validation: maintainer guide

Use this guide for the everyday catalog process. The
[implementation plan](catalog-validation-implementation-plan.md) contains the
full architecture, contracts, threat model, and pilot history.

## Current operating decision

- Use the reusable GitHub Actions validator. The GitHub App remains deferred.
- Keep catalog validation non-required. A pilot check is informational and is
  not authorization to change repository rules.
- Treat `.azd/catalog.json` as display metadata only. A passing check proves
  acceptance by the machine-readable schema and bounded processing rules, not
  that a solution deploys or that its claims are correct.
- Keep deployments self-contained. They must not depend on the validator,
  `azd-reference`, or `azd-website`.

## Ownership at a glance

| Location | Owns |
| --- | --- |
| `azd-reference` | The canonical standard, schema, validator, immutable workflow release, desired portfolio state, and evidence. |
| `azd-work-in-progress` | Staging for solution-specific work. An explicitly enrolled staged solution may be validated by an explicit path and is not automatically enrolled as a standalone repository. |
| Standalone solution repository | Verified solution facts in root `.azd/catalog.json` and, when enrolled, a minimal caller workflow pinned to a reviewed full commit SHA. |
| `azd-website` | Website-only editorial overrides and a provenance-locked copy of the canonical schema. |

## Add or update a solution

1. Verify the solution's README, `azure.yaml`, supported deployment path, and
   cleanup guidance. Do not infer catalog claims from plans or unfinished code.
2. Add or update `.azd/catalog.json` using the
   [catalog metadata standard](../standards/catalog-metadata.md). Include only
   verified display facts and omit unknown optional values.
3. Validate the file against the canonical schema. From the `azd-reference`
   root, a local shape-and-type check can use:

   ```powershell
   Get-Content -LiteralPath <path-to-catalog.json> -Raw |
     Test-Json -SchemaFile ./schemas/catalog-metadata.schema.json
   ```

   The pinned [reusable workflow](../.github/workflows/catalog-metadata.yml)
   performs the complete hosted validation, including bounded blob processing.
   A staged caller must pass the explicit path rather than treating the staging
   repository root as a catalog entry:

   ```yaml
   uses: nathanmcnulty/azd-reference/.github/workflows/catalog-metadata.yml@<reviewed-40-character-sha>
   with:
     catalog-path: azd-example/.azd/catalog.json
   ```

4. Only after explicit approval for the named consumer or rollout ring, add
   the minimal caller pinned to the reviewed full `azd-reference` workflow
   commit and record a standalone repository as `pilot` in the governance
   registry. Editing metadata does not authorize publishing a caller, changing
   the registry, or changing the repository's Actions policy. Publication
   alone does not enroll a repository.
5. Review both pull-request and default-branch results. Keep the check
   non-required unless a separate, recorded approval authorizes the central
   enforcement gate and the individual repository transition.

Repository CI and human review still own deployment validation, cleanup,
permissions, consent, cost, security, and whether the displayed claims match
implemented behavior. The catalog validator must never execute repository
commands, hooks, packages, templates, or application code.

## Interpret a result

| Observation | Meaning and response |
| --- | --- |
| Success | The pinned validator accepted the display metadata. Continue normal repository review and CI. |
| `catalogMissing` or a schema/processing-limit finding | Fix the repository-owned metadata. This is a deterministic content failure. Human review still owns writing guidance and factual accuracy. |
| `operational_error`, integrity failure, or unavailable source commit | Investigate GitHub availability, the immutable pin, or source access. Do not report the metadata as invalid and never convert the result to success. |
| `action_required` on an untrusted fork | GitHub is waiting for first-time-contributor approval. Approve only the intended static catalog workflow when the test is deliberate; do not approve repository-defined workflows merely to obtain catalog evidence. |
| No catalog check | Confirm whether the repository is actually enrolled and whether its caller and event filters are present. A `pending` repository is expected to have no check. |

The stable standalone Check Run context is
`azd catalog metadata / azd catalog metadata`. Its integration ID is observed
live and must be rechecked before any ruleset change; neither value alone is an
independent anti-tamper boundary.

## Update the schema or validator

1. Make the canonical change in `azd-reference` and run its conformance tests.
2. Review the workflow, schema, validator, dependency pins, and release
   manifest together. Publish the canonical immutable revision first.
3. After the canonical revision exists, update the desired workflow revision in
   central governance separately from consumer adoption. A newer revision does
   not invalidate an older reviewed pin automatically.
4. Update each authorized caller through an independently reviewed pull
   request. Do not make automatic writes, approvals, or merges.
5. Update the website's provenance lock through a separate reviewed change.
   Website overrides remain website-only and never flow back into repository
   metadata or the canonical schema.

Never fetch validator or schema content from a mutable branch at validation or
deployment time.

## Audit or roll back a pilot

From the `azd-reference` root, use the read-only audit to compare an enrolled
repository with the centrally managed pin and caller shape:

```powershell
./tooling/Get-AzdGitHubGovernanceStatus.ps1 `
  -Repository nathanmcnulty/azd-example `
  -CatalogValidationOnly `
  -AsJson
```

The audit reads repository state; it does not write settings or execute
consumer code. To leave a pilot after explicit authorization, remove the
non-required caller in a reviewed repository change and return its central
registry state to `pending` in a separate reviewed change. Preserve the
failure evidence. Never hide an operational error by converting it to success.

## Hard boundaries

- Do not make the check required without explicit approval recorded through
  the central enforcement gate and the repository-specific approval fields.
- Do not treat `public`, `pilot`, `passing`, or `published` as synonyms for
  `required`.
- Do not let catalog validation write repository contents, create pull
  requests, approve workflows or reviews, or merge changes.
- Do not put deployment behavior or GUI contracts into `.azd/catalog.json`.
- Do not move website editorial overrides into solution repositories.
- Do not use the validator as a deployment dependency or execute
  repository-defined code.

For current hosted evidence and known GitHub behavior, see the
[pilot evidence record](catalog-validation-pilot-evidence.md).
