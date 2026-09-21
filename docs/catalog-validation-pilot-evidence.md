# Catalog validation pilot evidence

Status: Non-required pilot in progress

This record captures hosted GitHub evidence for the reusable catalog validator.
It does not authorize required-check enforcement, deployment changes, or
automatic repository mutation.

## Santa public-fork proof

Date: 2026-09-21

Repositories and identities:

- base repository: `nathanmcnulty/azd-santa`;
- disposable public fork: `patriot-nmcnulty/azd-santa`;
- fork commit author and committer: `patriot-nmcnulty`;
- base-repository commits, rules, and settings were not changed by the fork
  identity.

Evidence:

- closed, unmerged pull request: `nathanmcnulty/azd-santa#4`;
- exact fork head SHA: `352a5e828c7c1159abf6553694ee3bb1ac45ad00`;
- catalog workflow run: `35655914160`;
- first attempt concluded `action_required` under the repository's
  `first_time_contributors` approval policy;
- only the catalog workflow was approved; the solution validation and
  dependency-review workflows were not approved for this proof;
- the approved catalog job completed successfully with check name
  `azd catalog metadata / azd catalog metadata` and GitHub Actions integration
  ID `15368`;
- the job was bound to the exact fork SHA and reported
  `patriot-nmcnulty/azd-santa` as its head repository;
- manual reruns remained bound to the same repository and SHA and completed
  successfully;
- after the pull request was closed without merge and its fork branch returned
  `404`, a stored-event rerun still completed successfully at the same SHA.

The successful post-deletion rerun proves that deleting the branch reference
does not immediately make the event commit inaccessible to GitHub. It does not
prove behavior after deleting or privatizing the fork repository. That remains
an explicit operational-error test gap.

## Current assessment

- The reusable workflow can validate a public-fork commit without secrets or
  write permissions after a maintainer approves the first-time contributor
  run.
- The stable Check Run identity observed on the fork matches the canonical
  governance tuple.
- First-time contributor approval is a real availability delay. The catalog
  check must remain non-required unless the maintainer explicitly accepts that
  delay or changes the repository approval policy through a separate decision.
- This evidence does not justify a GitHub App. The Actions-first design remains
  sufficient for the current pilot.

## Remaining pilot evidence

- exercise an inaccessible or deleted fork repository without deleting a fork
  that contains user work;
- validate a committed staged-solution path in `azd-work-in-progress`;
- record measured runtime and false-positive observations across at least two
  standalone pilots and the staged pilot;
- obtain an explicit maintainer decision on the first-time contributor delay
  before any required-check proposal.
