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

### Missing enrolled file

A second disposable fork pull request proved the hosted deterministic-failure
path:

- closed, unmerged pull request: `nathanmcnulty/azd-santa#6`;
- exact fork head SHA: `d48ed7b6263867d25387afe63b46c570ab97a710`;
- catalog workflow run: `35662758412`;
- the first attempt again concluded `action_required` and only the catalog
  workflow was approved;
- the job failed in four seconds with a `catalogMissing` failure annotation on
  `.azd/catalog.json`;
- the result retained the stable catalog check name and integration ID `15368`;
- after closing the pull request and deleting its branch, a manual rerun failed
  identically at the same repository and SHA;
- repository-defined validation and dependency-review workflows were not
  approved for this proof.

The fork's `main` branch was synchronized to the upstream commit before the
test, and the test branch was deleted afterward. No fork change was merged.

## App Control staged-path proof

Date: 2026-09-21

Evidence:

- repository: private staging repository `nathanmcnulty/azd-work-in-progress`;
- staged solution path: `azd-app-control`;
- merged pull request: `nathanmcnulty/azd-work-in-progress#27`;
- exact default-branch merge SHA:
  `b9e39265df8d59e83ba77bb88a12030178cad6c1`;
- catalog path: `azd-app-control/.azd/catalog.json`;
- caller pin: `0b79d2e1e1c920a13cede11d42c72b799cc2310c`;
- pull-request catalog run `35657460248` completed successfully in five
  seconds;
- default-branch catalog run `35657592915` completed successfully and its
  manual rerun remained bound to the merge SHA;
- observed check name:
  `azd App Control catalog metadata / azd catalog metadata`;
- observed source integration ID: `15368`;
- the existing App Control Phase 0 workflow also passed independently, keeping
  static catalog validation separate from repository-defined tests.

The staged metadata intentionally omits `quickstartCommands`. The Phase 0
scaffold has no supported deployment quickstart, so adding one would turn
display metadata into an unsupported behavioral claim.

## Runtime and maintenance sample

Fourteen completed jobs were sampled across Emergency Access, Risk-Based
Conditional Access, Santa, and staged App Control. They covered pull requests,
default-branch pushes, and manual reruns.

- all 14 completed successfully;
- observed job duration ranged from four to six seconds, with a 4.5-second
  median;
- no accepted catalog file produced an unexpected validation failure;
- callers required only an immutable workflow pin and, for staged App Control,
  an explicit catalog path;
- the only observed approval friction was GitHub's expected
  `first_time_contributors` gate for the public fork.

This is a small pilot sample, not an availability service-level objective.
Continue monitoring operational errors and false positives during broader
non-required use.

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
- Two standalone repositories and one explicit staged path now exercise the
  same immutable validator release without repository-specific validator code.

## Remaining pilot evidence

- delete the verified disposable `patriot-nmcnulty/azd-santa` fork and rerun a
  stored event to observe genuinely inaccessible-repository behavior. The
  scoped CLI token cannot perform this step because it lacks `delete_repo`;
- obtain an explicit maintainer decision on the first-time contributor delay
  before any required-check proposal.
