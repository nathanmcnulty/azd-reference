# Standalone solution promotion standard

Use this process when a solution moves from `azd-work-in-progress` into its
own independently supported repository. Promotion is complete only when the
standalone repository, the `azd-reference` registry, and the incubation
repository agree on the new source of truth.

## Readiness gate

Before creating the public repository, the solution owner must prove:

- the solution has its own root `azure.yaml`, deployment hooks, validation
  entry point, README, `SECURITY.md`, license, and third-party notices;
- repository validation passes from a clean checkout, including reproducible
  generated artifacts and component-lock hash checks;
- each reusable `azd-reference` component is vendored at an immutable release
  version in `azd-components.lock.json`, with the exact source revision and
  file hashes recorded;
- optional Azure, Graph, Intune, Defender, or Sentinel paths have evidence
  appropriate to their risk. Mocked tests do not substitute for an authorized
  live check when the promotion claims a live integration;
- the tracked source contains no credentials, tenant or subscription data,
  personal identifiers, local `.azure` or `.artifacts` state, downloaded
  installers, or private pilot reports; and
- the public repository has a pinned-action validation workflow, grouped and
  bounded Dependabot configuration, and concise `.azd/catalog.json` metadata.

The catalog is display metadata only. Permissions, tenant scope, costs,
cleanup, and operational caveats remain in the README and `docs/`.

## Promotion sequence

1. **Freeze incubation.** Merge the final solution change in
   `azd-work-in-progress`. Record the exact source commit, tracked file list,
   validation result, live evidence location, and the component-lock status.
2. **Export the solution.** Copy only tracked solution files from that commit
   into a standalone checkout. Preserve exact bytes; if history cannot be
   preserved, record the source commit in the promotion PR. Never export
   `.azure`, `.artifacts`, `.env`, MSI packages, credentials, or local reports.
3. **Bootstrap the standalone repository.** Create the public repository with
   the selected license, default branch, security contact, validation workflow,
   Dependabot policy, catalog metadata, and third-party notices. Run the
   solution's validation entry point from the standalone root and compare the
   exported file manifest with the frozen incubation commit.
4. **Register the consumer.** Open an `azd-reference` PR that adds or updates
   the `portfolio/consumers.json` entry with the public repository URL,
   checkout directory, solution root, default branch, validation workflow,
   validation entry point and timeout, rollout ring, adoption state, explicit
   portfolio baseline, and every vendored component version. Update
   `docs/component-candidates.md` when the solution introduces or clarifies a
   reusable boundary.
5. **Remove the incubation copy.** After the standalone repository and
   registry PRs are merged, open a separate `azd-work-in-progress` PR that
   removes the solution subtree and its solution-specific workflow or catalog
   references. Do not delete neighboring solutions, unrelated untracked files,
   or tenant resources as part of this repository move.
6. **Close out the promotion.** Run the reference portfolio status audit from
   the public checkout root, run component drift validation, verify the public
   workflow, and link the standalone, registry, and removal PRs in the final
   record. Archive temporary branches only after the merged commits and rollback
   links are recorded.

## Pull-request order and evidence

The promotion should produce three linked changes:

| Change | Required result |
| --- | --- |
| Standalone repository | Public default branch contains only reviewed, self-contained source and its validation workflow passes. |
| `azd-reference` registry | The public URL, baseline, component versions, and validation contract are schema-valid and the status audit has no new findings. |
| `azd-work-in-progress` removal | The incubation subtree and only its dedicated workflow/references are removed; the parent repository remains healthy. |

The standalone and registry changes may be prepared together, but the registry
must not merge before the public default branch exists. The removal PR waits for
both of those merges. Each PR body should include the source commit, resulting
commit, validation command and result, relevant live-evidence boundary, and the
rollback commit or revert procedure.

## Rollback and external state

Promotion is a source-repository operation. It does not automatically delete
Azure resources, Intune objects, Defender library files, Sentinel rules, or
tenant associations. Handle those objects through the solution's explicit
cleanup path and record ownership separately.

If a standalone or registry change is rejected, leave the incubation copy in
place. If the removal PR has already merged, revert that PR before changing the
public repository. Reverting the registry entry and restoring the incubation
subtree are independent recovery actions; do not rewrite public history.
